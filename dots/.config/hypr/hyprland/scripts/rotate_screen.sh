#!/usr/bin/env bash
# Screen rotation script for Hyprland on tablets / touch devices
# Supports manual rotation (0, 1, 2, 3, toggle, next) and auto-rotation via iio-sensor-proxy

STATE_FILE="${XDG_RUNTIME_DIR:-/tmp}/hypr_rotation"
AUTO_PID_FILE="${XDG_RUNTIME_DIR:-/tmp}/hypr_autorotate.pid"

get_current_transform() {
    if [[ -f "$STATE_FILE" ]]; then
        cat "$STATE_FILE"
    else
        # Try detecting from hyprctl monitors
        local rot
        rot=$(hyprctl monitors -j 2>/dev/null | jq -r '.[0].transform // 0' 2>/dev/null)
        echo "${rot:-0}"
    fi
}

get_primary_monitor() {
    local mon
    mon=$(hyprctl monitors -j 2>/dev/null | jq -r '.[0].name // empty' 2>/dev/null)
    if [[ -z "$mon" ]]; then
        # Default fallback for Snapdragon tablets or internal displays
        mon="DSI-1"
    fi
    echo "$mon"
}

apply_rotation() {
    local rot="$1"
    local mon
    mon=$(get_primary_monitor)

    # 0 = normal (landscape)
    # 1 = 90 deg (portrait)
    # 2 = 180 deg (inverted landscape)
    # 3 = 270 deg (inverted portrait)
    hyprctl keyword monitor "${mon},preferred,auto,auto,transform,${rot}" >/dev/null 2>&1
    hyprctl keyword input:touchdevice:transform "${rot}" >/dev/null 2>&1
    hyprctl keyword input:tablet:transform "${rot}" >/dev/null 2>&1

    echo "$rot" > "$STATE_FILE"

    # Notify Quickshell via IPC if running
    if command -v qs >/dev/null 2>&1; then
        qs -c ii ipc call orientation set "$rot" >/dev/null 2>&1 || true
    fi

    local desc="横屏 (0°)"
    case "$rot" in
        1) desc="竖屏 (90°)" ;;
        2) desc="倒置横屏 (180°)" ;;
        3) desc="反向竖屏 (270°)" ;;
    esac

    if command -v notify-send >/dev/null 2>&1; then
        notify-send -a "系统显示" -i "screen_rotation" -u low "屏幕方向已旋转" "当前方向：${desc}"
    fi
}

start_autorotate() {
    if [[ -f "$AUTO_PID_FILE" ]] && kill -0 "$(cat "$AUTO_PID_FILE")" 2>/dev/null; then
        echo "Auto-rotate is already running (PID: $(cat "$AUTO_PID_FILE"))"
        return 0
    fi

    if ! command -v monitor-sensor >/dev/null 2>&1; then
        echo "monitor-sensor not found. Please install iio-sensor-proxy." >&2
        return 1
    fi

    (
        monitor-sensor 2>/dev/null | while read -r line; do
            case "$line" in
                *": normal"*) apply_rotation 0 ;;
                *": bottom-up"*) apply_rotation 2 ;;
                *": right-up"*) apply_rotation 1 ;;
                *": left-up"*) apply_rotation 3 ;;
            esac
        done
    ) &
    echo $! > "$AUTO_PID_FILE"
    echo "Auto-rotate started (PID: $!)"
}

stop_autorotate() {
    if [[ -f "$AUTO_PID_FILE" ]]; then
        local pid
        pid=$(cat "$AUTO_PID_FILE")
        kill "$pid" 2>/dev/null || true
        rm -f "$AUTO_PID_FILE"
        echo "Auto-rotate stopped."
    fi
}

toggle_autorotate() {
    if [[ -f "$AUTO_PID_FILE" ]] && kill -0 "$(cat "$AUTO_PID_FILE")" 2>/dev/null; then
        stop_autorotate
        if command -v notify-send >/dev/null 2>&1; then
            notify-send -a "系统显示" -i "screen_rotation" -u low "重力自动旋转" "已关闭"
        fi
    else
        start_autorotate
        if command -v notify-send >/dev/null 2>&1; then
            notify-send -a "系统显示" -i "screen_rotation" -u low "重力自动旋转" "已开启"
        fi
    fi
}

ACTION="${1:-toggle}"

case "$ACTION" in
    0|1|2|3)
        apply_rotation "$ACTION"
        ;;
    toggle)
        CURRENT=$(get_current_transform)
        if [[ "$CURRENT" -eq 1 || "$CURRENT" -eq 3 ]]; then
            apply_rotation 0
        else
            apply_rotation 1
        fi
        ;;
    next)
        CURRENT=$(get_current_transform)
        NEXT=$(( (CURRENT + 1) % 4 ))
        apply_rotation "$NEXT"
        ;;
    auto-start)
        start_autorotate
        ;;
    auto-stop)
        stop_autorotate
        ;;
    auto-toggle)
        toggle_autorotate
        ;;
    status)
        get_current_transform
        ;;
    *)
        echo "Usage: $0 [0|1|2|3|toggle|next|auto-start|auto-stop|auto-toggle|status]"
        exit 1
        ;;
esac
