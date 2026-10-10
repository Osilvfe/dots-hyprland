#!/usr/bin/env python3
"""
Hyprland Session Restore Engine
Saves active GUI windows and their workspace placement before shutdown/reboot,
and restores them automatically on next login (macOS style).
"""

import sys
import os
import re
import json
import glob
import time
import subprocess
from typing import Dict, List, Optional, Any

STATE_DIR = os.path.expanduser("~/.local/state/hyprland")
STATE_FILE = os.path.join(STATE_DIR, "session-restore.json")

# Classes / programs to exclude from session persistence
EXCLUDE_CLASSES = {
    "",
    "quickshell",
    "hyprlock",
    "wleave",
    "xwaylandvideobridge",
    "polkit",
    "org.kde.polkit-kde-authentication-agent-1",
    "pinentry",
    "pinentry-gtk",
    "pinentry-qt",
    "xdg-desktop-portal-gtk",
    "xdg-desktop-portal-hyprland",
}

TERMINAL_COMMANDS = {
    "kitty": lambda cwd: f"kitty --directory {repr(cwd)}" if cwd else "kitty",
    "foot": lambda cwd: f"foot -D {repr(cwd)}" if cwd else "foot",
    "alacritty": lambda cwd: f"alacritty --working-directory {repr(cwd)}" if cwd else "alacritty",
    "ghostty": lambda cwd: f"ghostty --working-directory={repr(cwd)}" if cwd else "ghostty",
    "wezterm": lambda cwd: f"wezterm start --cwd {repr(cwd)}" if cwd else "wezterm",
}


def build_desktop_app_cache() -> Dict[str, str]:
    """Scans system and user desktop entries to map WM_CLASS to Exec commands."""
    dirs = [
        "/usr/share/applications",
        os.path.expanduser("~/.local/share/applications"),
        "/var/lib/flatpak/exports/share/applications",
        os.path.expanduser("~/.local/share/flatpak/exports/share/applications"),
    ]
    mapping: Dict[str, str] = {}

    for app_dir in dirs:
        if not os.path.isdir(app_dir):
            continue
        for desktop_file in glob.glob(os.path.join(app_dir, "**/*.desktop"), recursive=True):
            try:
                with open(desktop_file, "r", encoding="utf-8", errors="ignore") as f:
                    content = f.read()

                # Ignore NoDisplay=true unless it has specific classes
                is_nodisplay = bool(re.search(r"^NoDisplay=true", content, re.M | re.I))

                exec_match = re.search(r"^Exec=(.*)$", content, re.M)
                if not exec_match:
                    continue
                cmd = exec_match.group(1).strip()
                # Clean up desktop %U, %u, %F, %f, %i, %c, %k arguments
                cmd = re.sub(r"%[a-zA-Z]", "", cmd).strip()
                if not cmd:
                    continue

                basename = os.path.splitext(os.path.basename(desktop_file))[0].lower()
                if not is_nodisplay:
                    mapping[basename] = cmd

                # Check StartupWMClass
                wm_match = re.search(r"^StartupWMClass=(.*)$", content, re.M)
                if wm_match:
                    wm_class = wm_match.group(1).strip()
                    mapping[wm_class] = cmd
                    mapping[wm_class.lower()] = cmd

                # Also map application Name as fallback
                name_match = re.search(r"^Name=(.*)$", content, re.M)
                if name_match:
                    app_name = name_match.group(1).strip().lower()
                    if app_name not in mapping and not is_nodisplay:
                        mapping[app_name] = cmd

            except Exception:
                continue

    return mapping


def get_process_cwd(pid: int) -> Optional[str]:
    """Reads working directory for a given process PID."""
    try:
        target = os.readlink(f"/proc/{pid}/cwd")
        if os.path.isdir(target):
            return target
    except Exception:
        pass
    return None


def resolve_executable_for_client(client: Dict[str, Any], desktop_cache: Dict[str, str]) -> Optional[str]:
    """Resolves proper startup command line for a client."""
    c_class = client.get("class", "").strip()
    c_init_class = client.get("initialClass", "").strip()
    c_pid = client.get("pid", 0)

    # 1. Terminal special handling with CWD preservation
    norm_class = c_class.lower()
    norm_init = c_init_class.lower()
    for term_name, cmd_generator in TERMINAL_COMMANDS.items():
        if term_name in norm_class or term_name in norm_init:
            cwd = get_process_cwd(c_pid) if c_pid else None
            return cmd_generator(cwd)

    # 2. Check desktop file cache
    candidates = [c_class, c_init_class, norm_class, norm_init]
    for cand in candidates:
        if cand and cand in desktop_cache:
            return desktop_cache[cand]

    # Try matching desktop filename patterns (e.g. org.telegram.desktop -> telegram)
    for cand in [norm_class, norm_init]:
        if not cand:
            continue
        parts = cand.split(".")
        if len(parts) > 1 and parts[-1] in desktop_cache:
            return desktop_cache[parts[-1]]

    # 3. Fallback to process binary if valid and not an internal helper
    if c_pid and os.path.exists(f"/proc/{c_pid}"):
        try:
            exe_target = os.readlink(f"/proc/{c_pid}/exe")
            exe_name = os.path.basename(exe_target)
            if exe_name not in ["electron", "python", "python3", "bash", "sh", "zsh"]:
                return exe_target
        except Exception:
            pass

    return None


def save_session() -> bool:
    """Captures currently open windows and writes session state."""
    try:
        raw_clients = subprocess.check_output(["hyprctl", "clients", "-j"], text=True)
        clients = json.loads(raw_clients)
    except Exception as e:
        print(f"Error querying hyprctl clients: {e}", file=sys.stderr)
        return False

    desktop_cache = build_desktop_app_cache()
    saved_windows = []
    seen_exec_per_workspace = set()

    for c in clients:
        c_class = c.get("class", "").strip()
        if not c_class or c_class.lower() in EXCLUDE_CLASSES:
            continue
        if any(c_class.lower().startswith(ex) for ex in ["polkit", "pinentry", "quickshell"]):
            continue

        ws_info = c.get("workspace", {})
        ws_id = ws_info.get("id", 1)
        # Skip special/scratchpad or invalid sentinel workspaces (negative or > 100)
        if ws_id < 1 or ws_id > 100:
            continue

        # Skip hidden or unmapped windows
        if c.get("hidden", False) or not c.get("mapped", True):
            continue

        exec_cmd = resolve_executable_for_client(c, desktop_cache)
        if not exec_cmd:
            continue

        # Prevent duplicate launch commands on the same workspace
        dedup_key = (ws_id, exec_cmd)
        if dedup_key in seen_exec_per_workspace:
            continue
        seen_exec_per_workspace.add(dedup_key)

        saved_windows.append({
            "class": c_class,
            "initialClass": c.get("initialClass", ""),
            "title": c.get("title", ""),
            "workspace": ws_id,
            "exec": exec_cmd,
            "floating": c.get("floating", False),
        })

    os.makedirs(STATE_DIR, exist_ok=True)
    payload = {
        "timestamp": int(time.time()),
        "windowCount": len(saved_windows),
        "windows": saved_windows,
    }

    tmp_file = f"{STATE_FILE}.tmp"
    with open(tmp_file, "w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2, ensure_ascii=False)
    os.replace(tmp_file, STATE_FILE)

    print(f"Session saved successfully ({len(saved_windows)} windows).")
    return True


def restore_session() -> bool:
    """Restores saved windows into their respective workspaces."""
    if not os.path.exists(STATE_FILE):
        print("No saved session file found.")
        return False

    try:
        with open(STATE_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception as e:
        print(f"Error reading session file: {e}", file=sys.stderr)
        return False

    windows = data.get("windows", [])
    if not windows:
        print("Session file has no windows to restore.")
        return False

    print(f"Restoring {len(windows)} windows...")
    for item in windows:
        ws = item.get("workspace", 1)
        exec_cmd = item.get("exec", "")
        if not exec_cmd:
            continue

        # Launch into target workspace silently via Hyprland dispatch
        hypr_exec_arg = f"[workspace {ws} silent] {exec_cmd}"
        try:
            subprocess.run(["hyprctl", "dispatch", "exec", hypr_exec_arg], check=False)
            # Short stagger to prevent system launch storm
            time.sleep(0.18)
        except Exception as e:
            print(f"Failed to launch {exec_cmd}: {e}", file=sys.stderr)

    # Rename session file to mark as restored
    bak_file = f"{STATE_FILE}.bak"
    try:
        os.replace(STATE_FILE, bak_file)
    except Exception:
        pass

    print("Session restored successfully.")
    return True


def clear_session() -> bool:
    """Clears any pending session restore file."""
    for path in [STATE_FILE, f"{STATE_FILE}.tmp"]:
        if os.path.exists(path):
            try:
                os.remove(path)
            except Exception:
                pass
    print("Session file cleared.")
    return True


def status_session() -> None:
    """Prints current session restore status."""
    if not os.path.exists(STATE_FILE):
        print("No active saved session.")
        return

    try:
        with open(STATE_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
        windows = data.get("windows", [])
        ts = data.get("timestamp", 0)
        formatted_time = time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(ts)) if ts else 'unknown'
        print(f"Saved Session: {len(windows)} windows at {formatted_time}")
        for w in windows:
            print(f"  [Workspace {w.get('workspace')}] {w.get('class')}: {w.get('exec')}")
    except Exception as e:
        print(f"Error reading session: {e}")


def main():
    if len(sys.argv) < 2:
        print("Usage: session-restore.py [save|restore|clear|status]")
        sys.exit(1)

    cmd = sys.argv[1].lower()
    if cmd == "save":
        success = save_session()
        sys.exit(0 if success else 1)
    elif cmd == "restore":
        success = restore_session()
        sys.exit(0 if success else 1)
    elif cmd == "clear":
        clear_session()
        sys.exit(0)
    elif cmd == "status":
        status_session()
        sys.exit(0)
    else:
        print(f"Unknown command: {cmd}")
        sys.exit(1)


if __name__ == "__main__":
    main()
