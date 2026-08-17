#!/usr/bin/env bash
# One hyprctl JSON call instead of a 5-process text pipeline.
MAIN_KB_CAPS=$(hyprctl devices -j | jq -r '.keyboards[] | select(.main == true) | .capsLock' | head -1)
if [ "$MAIN_KB_CAPS" = "true" ]; then
    echo "Caps Lock active"
fi
