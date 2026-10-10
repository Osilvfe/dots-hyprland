#!/usr/bin/env bash
# Inhibit systemd-logind from handling physical power button during this Hyprland session,
# allowing Hyprland/Quickshell to intercept XF86PowerOff and show the session power menu.
# This inhibitor terminates automatically when Hyprland exits, leaving other environments untouched.

exec systemd-inhibit \
    --what=handle-power-key \
    --who="Hyprland Session" \
    --why="Power button handled by Quickshell power menu" \
    sleep infinity
