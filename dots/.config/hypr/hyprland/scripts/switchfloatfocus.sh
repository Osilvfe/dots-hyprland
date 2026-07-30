#!/bin/bash
ADDR=$(hyprctl activewindow -j | jq -r '.address // empty')

if [ -z "$ADDR" ]; then
    hyprctl dispatch focuscurrentorlast
    exit
fi

FLOAT=$(hyprctl activewindow -j | jq -r '.floating')

if [ "$FLOAT" = "true" ]; then
    TGT=$(hyprctl clients -j | jq -r '
        map(select(.floating == false and .mapped == true))
        | sort_by(.focusHistoryID)
        | last | .address // empty
    ')
else
    TGT=$(hyprctl clients -j | jq -r '
        map(select(.floating == true and .mapped == true and .address != "'"$ADDR"'"))
        | sort_by(.focusHistoryID)
        | last | .address // empty
    ')
fi

if [ -n "$TGT" ]; then
    hyprctl eval "hl.dispatch(hl.dsp.focus({ window = 'address:$TGT' }))"
fi
