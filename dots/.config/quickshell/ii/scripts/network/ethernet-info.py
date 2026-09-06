#!/usr/bin/env python3
import json
import os
import subprocess
import sys

def get_ethernet_info():
    env = os.environ.copy()
    env["LANG"] = "C"
    env["LC_ALL"] = "C"

    # 1. Query device status
    try:
        status_proc = subprocess.run(
            ["nmcli", "-t", "-f", "DEVICE,TYPE,STATE,CONNECTION,CON-UUID", "device", "status"],
            capture_output=True,
            text=True,
            env=env,
            timeout=5
        )
        if status_proc.returncode != 0:
            return []
        lines = status_proc.stdout.strip().split("\n")
    except Exception:
        return []

    devices = []
    for line in lines:
        if not line:
            continue
        parts = line.split(":")
        if len(parts) >= 3 and parts[1] == "ethernet":
            dev_name = parts[0]
            dev_state = parts[2]
            active_conn = parts[3] if len(parts) > 3 else ""
            active_uuid = parts[4] if len(parts) > 4 else ""

            dev = {
                "device": dev_name,
                "state": dev_state,
                "connection": active_conn,
                "conUuid": active_uuid,
                "carrier": False,
                "speed": "",
                "hwaddr": "",
                "ipv4": [],
                "gateway4": "",
                "dns4": [],
                "ipv6": [],
                "savedConnections": [],
                "autoconnect": True
            }

            # 2. Detailed info for device
            try:
                show_proc = subprocess.run(
                    [
                        "nmcli", "-t", "-m", "multiline", "-f",
                        "GENERAL.HWADDR,WIRED-PROPERTIES.CARRIER,CAPABILITIES.SPEED,IP4.ADDRESS,IP4.GATEWAY,IP4.DNS,IP6.ADDRESS",
                        "device", "show", dev_name
                    ],
                    capture_output=True,
                    text=True,
                    env=env,
                    timeout=5
                )
                if show_proc.returncode == 0:
                    for s_line in show_proc.stdout.strip().split("\n"):
                        if not s_line or ":" not in s_line:
                            continue
                        k, v = s_line.split(":", 1)
                        k, v = k.strip(), v.strip()
                        if k == "GENERAL.HWADDR":
                            dev["hwaddr"] = v
                        elif k == "WIRED-PROPERTIES.CARRIER":
                            dev["carrier"] = (v.lower() == "on")
                        elif k == "CAPABILITIES.SPEED":
                            dev["speed"] = v if v.lower() != "unknown" else ""
                        elif k.startswith("IP4.ADDRESS"):
                            if v and v not in dev["ipv4"]:
                                dev["ipv4"].append(v)
                        elif k == "IP4.GATEWAY":
                            dev["gateway4"] = v
                        elif k.startswith("IP4.DNS"):
                            if v and v not in dev["dns4"]:
                                dev["dns4"].append(v)
                        elif k.startswith("IP6.ADDRESS"):
                            if v and v not in dev["ipv6"]:
                                dev["ipv6"].append(v)
            except Exception:
                pass

            # 3. Saved connections matching device or ethernet type
            try:
                conn_proc = subprocess.run(
                    ["nmcli", "-t", "-f", "NAME,UUID,TYPE,AUTOCONNECT,DEVICE", "connection", "show"],
                    capture_output=True,
                    text=True,
                    env=env,
                    timeout=5
                )
                if conn_proc.returncode == 0:
                    for c_line in conn_proc.stdout.strip().split("\n"):
                        if not c_line:
                            continue
                        c_parts = c_line.split(":")
                        if len(c_parts) >= 4 and ("ethernet" in c_parts[2] or "802-3" in c_parts[2]):
                            conn_dev = c_parts[4] if len(c_parts) > 4 else ""
                            c_name = c_parts[0]
                            c_uuid = c_parts[1]
                            c_auto = (c_parts[3].lower() == "yes")
                            if conn_dev == dev_name or conn_dev == "" or active_conn == c_name:
                                dev["savedConnections"].append({
                                    "name": c_name,
                                    "uuid": c_uuid,
                                    "autoconnect": c_auto
                                })
                                if not dev["conUuid"]:
                                    dev["conUuid"] = c_uuid
                                    dev["autoconnect"] = c_auto
                                elif dev["conUuid"] == c_uuid:
                                    dev["autoconnect"] = c_auto
            except Exception:
                pass

            devices.append(dev)

    return devices

if __name__ == "__main__":
    data = get_ethernet_info()
    print(json.dumps(data))
