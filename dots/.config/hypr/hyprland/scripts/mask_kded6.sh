#!/usr/bin/env bash
# Prevent kded6 from owning org.kde.StatusNotifierWatcher so that qs (the
# restored vanilla build) can be the SNI watcher itself.
#
# On non-KDE desktops:
#   - kill any running kded6
#   - drop a fake D-Bus service file (Exec=/bin/false) so D-Bus activation
#     can never respawn kded6
#   - mask plasma-kded6.service so systemd won't start it either
# On KDE (e.g. when the user logs into a Plasma session) restore everything.
set -u

KDED6="[D-BUS Service]
Name=org.kde.kded6
Exec=/bin/false"

KDED6_PATH="$HOME/.local/share/dbus-1/services"
KDED6_FULL_PATH="$KDED6_PATH/org.kde.kded6.service"

if [[ "${XDG_CURRENT_DESKTOP:-}" == "KDE" ]]; then
    systemctl --user unmask plasma-kded6.service
    if [[ -f "$KDED6_FULL_PATH" ]]; then
        rm -f "$KDED6_FULL_PATH"
    fi
else
    killall kded6 2>/dev/null
    mkdir -p "$KDED6_PATH"
    printf '%s\n' "$KDED6" > "$KDED6_FULL_PATH"
    systemctl --user mask plasma-kded6.service
fi
