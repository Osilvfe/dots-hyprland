#!/usr/bin/env bash
# Pogo-pin detachable keyboard detection and tablet mode manager for Hyprland
# Detects when the physical pogo-pin keyboard is attached or detached.

STATE_FILE="${XDG_RUNTIME_DIR:-/tmp}/hypr_tablet_mode"
LISTEN_PID_FILE="${XDG_RUNTIME_DIR:-/tmp}/hypr_tablet_mode_listen.pid"

is_physical_keyboard() {
    local name="$1"
    local lower
    lower=$(echo "$name" | tr '[:upper:]' '[:lower:]')

    # Ignore known virtual, button, or sensor inputs
    case "$lower" in
        *ydotool*|*virtual*|*power*|*sleep*|*gpio*|*video*|*button*|*switch*|*headset*|*wacom*|*touchscreen*|*stylus*)
            return 1
            ;;
        *)
            return 0
            ;;
    esac
}

detect_tablet_mode() {
    # Check hyprctl devices
    if ! command -v hyprctl >/dev/null 2>&1; then
        echo "0"
        return
    fi

    local dev_json
    dev_json=$(hyprctl devices -j 2>/dev/null)
    if [[ -z "$dev_json" ]]; then
        echo "0"
        return
    fi

    local keyboards
    keyboards=$(echo "$dev_json" | jq -r '.keyboards[].name // empty' 2>/dev/null)

    local physical_found=0
    while IFS= read -r kb; do
        [[ -z "$kb" ]] && continue
        if is_physical_keyboard "$kb"; then
            physical_found=1
            break
        fi
    done <<< "$keyboards"

    if [[ "$physical_found" -eq 1 ]]; then
        # Physical keyboard attached -> Laptop mode (tablet_mode = 0)
        echo "0"
    else
        # Detached -> Tablet mode (tablet_mode = 1)
        echo "1"
    fi
}

update_state() {
    local new_mode="$1"
    local old_mode="unknown"
    [[ -f "$STATE_FILE" ]] && old_mode=$(cat "$STATE_FILE")

    echo "$new_mode" > "$STATE_FILE"

    if [[ "$old_mode" != "$new_mode" ]]; then
        # Notify Quickshell via IPC
        if command -v qs >/dev/null 2>&1; then
            local qs_val="false"
            [[ "$new_mode" == "1" ]] && qs_val="true"
            qs -c ii ipc call tabletMode set "$qs_val" >/dev/null 2>&1 || true
        fi

        # User feedback notification
        if command -v notify-send >/dev/null 2>&1; then
            if [[ "$new_mode" == "1" ]]; then
                notify-send -a "系统模式" -i "tablet" -u low "平板模式已激活" "键盘已拆卸，已启用全触控交互"
            else
                notify-send -a "系统模式" -i "keyboard" -u low "笔记本模式已恢复" "键盘已吸附连接"
            fi
        fi
    fi
}

start_listen() {
    if [[ -f "$LISTEN_PID_FILE" ]] && kill -0 "$(cat "$LISTEN_PID_FILE")" 2>/dev/null; then
        echo "Tablet mode listener already running (PID: $(cat "$LISTEN_PID_FILE"))"
        return 0
    fi

    (
        # Initial check
        update_state "$(detect_tablet_mode)"

        # Monitor udev input events for pogo-pin attach/detach
        if command -v udevadm >/dev/null 2>&1; then
            udevadm monitor --subsystem-match=input 2>/dev/null | while read -r line; do
                if [[ "$line" =~ (add|remove) ]]; then
                    # Debounce
                    sleep 0.5
                    update_state "$(detect_tablet_mode)"
                fi
            done
        fi
    ) &
    echo $! > "$LISTEN_PID_FILE"
    echo "Tablet mode listener started (PID: $!)"
}

stop_listen() {
    if [[ -f "$LISTEN_PID_FILE" ]]; then
        local pid
        pid=$(cat "$LISTEN_PID_FILE")
        kill "$pid" 2>/dev/null || true
        rm -f "$LISTEN_PID_FILE"
        echo "Tablet mode listener stopped."
    fi
}

ACTION="${1:-check}"

case "$ACTION" in
    check)
        MODE=$(detect_tablet_mode)
        update_state "$MODE"
        echo "$MODE"
        ;;
    status)
        if [[ -f "$STATE_FILE" ]]; then
            cat "$STATE_FILE"
        else
            detect_tablet_mode
        fi
        ;;
    toggle)
        CURRENT="0"
        [[ -f "$STATE_FILE" ]] && CURRENT=$(cat "$STATE_FILE")
        if [[ "$CURRENT" == "1" ]]; then
            update_state "0"
        else
            update_state "1"
        fi
        ;;
    listen)
        start_listen
        ;;
    stop-listen)
        stop_listen
        ;;
    *)
        echo "Usage: $0 [check|status|toggle|listen|stop-listen]"
        exit 1
        ;;
esac
