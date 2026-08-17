#!/usr/bin/env bash
# Launch a standalone qs file (settings/welcome) without inheriting crash-handler
# environment from the parent shell.
#
# After qs crash-restarts, it keeps __QUICKSHELL_CRASH_INFO_FD in its environment.
# A child `qs -p settings.qml` then treats itself as a crash relaunch, ignores -p,
# and loads shell.qml instead — a second top bar and no settings window.
set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "usage: $0 <qml-file>" >&2
    exit 1
fi

unset __QUICKSHELL_CRASH_INFO_FD __QUICKSHELL_CRASH_DUMP_PID __QUICKSHELL_CRASH_SIGNAL
export XDG_CURRENT_DESKTOP="${XDG_CURRENT_DESKTOP_OVERRIDE:-gnome}"
exec qs -p "$1"
