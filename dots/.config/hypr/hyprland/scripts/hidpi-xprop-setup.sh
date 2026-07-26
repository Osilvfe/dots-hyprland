#!/usr/bin/env bash
# XWayland HiDPI via _XWAYLAND_GLOBAL_OUTPUT_SCALE (PR #6446)
# 1.5x monitor → integer scale = 2
systemctl --user enable --now xsettingsd.service
sleep 3
echo "Xft.dpi: 192" | xrdb -merge
xprop -root -format _XWAYLAND_GLOBAL_OUTPUT_SCALE 32c -set _XWAYLAND_GLOBAL_OUTPUT_SCALE 2
