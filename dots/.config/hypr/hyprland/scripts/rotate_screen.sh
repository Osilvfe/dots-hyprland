#!/usr/bin/env bash
# Screen rotation for the Hyprland 0.56 Lua configuration backend.

RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
STATE_FILE="${RUNTIME_DIR}/hypr_rotation"
AUTO_STATE_FILE="${RUNTIME_DIR}/hypr_autorotate"
AUTO_PID_FILE="${RUNTIME_DIR}/hypr_autorotate.pid"
AUTO_SESSION_FILE="${RUNTIME_DIR}/hypr_autorotate.session"
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"

if [[ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
    HYPRLAND_INSTANCE_SIGNATURE=$(find "${RUNTIME_DIR}/hypr" -mindepth 1 -maxdepth 1 -type d -printf '%P\n' 2>/dev/null | head -n 1 || true)
    export HYPRLAND_INSTANCE_SIGNATURE
fi
if [[ -z "${WAYLAND_DISPLAY:-}" ]]; then
    WAYLAND_DISPLAY=$(find "${RUNTIME_DIR}" -maxdepth 1 -name "wayland-*" -printf '%P\n' 2>/dev/null | head -n 1 || true)
    export WAYLAND_DISPLAY
fi
if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" && -S "${RUNTIME_DIR}/bus" ]]; then
    export DBUS_SESSION_BUS_ADDRESS="unix:path=${RUNTIME_DIR}/bus"
fi

atomic_write() {
    local path="$1"
    local value="$2"
    local temporary="${path}.tmp.$$"

    printf '%s\n' "$value" > "$temporary" && mv -f "$temporary" "$path"
}

get_primary_monitor() {
    local monitor

    monitor=$(hyprctl monitors -j 2>/dev/null | jq -r '
        ([.[] | select(.name | test("^(DSI|eDP|LVDS)-"; "i"))][0].name) //
        ([.[] | select(.focused == true)][0].name) //
        (.[0].name // empty)
    ' 2>/dev/null)
    printf '%s\n' "${monitor:-DSI-1}"
}

get_current_transform() {
    local monitor transform

    monitor=$(get_primary_monitor)
    transform=$(hyprctl monitors -j 2>/dev/null \
        | jq -r --arg monitor "$monitor" '.[] | select(.name == $monitor) | .transform // 0' \
        2>/dev/null | head -n 1)

    if [[ "$transform" =~ ^[0-3]$ ]]; then
        printf '%s\n' "$transform"
    elif [[ -f "$STATE_FILE" ]]; then
        cat "$STATE_FILE"
    else
        printf '0\n'
    fi
}

publish_transform() {
    local transform="$1"
    local send_ipc="${2:-true}"

    atomic_write "$STATE_FILE" "$transform"
    if [[ "$send_ipc" == "true" ]] && command -v qs >/dev/null 2>&1; then
        env HOME="${HOME:-/home/$(id -un)}" XDG_RUNTIME_DIR="${RUNTIME_DIR}" qs -c ii ipc call orientation set "$transform" >/dev/null 2>&1 || true
    fi
}

publish_auto_state() {
    local enabled="$1"
    local send_ipc="${2:-true}"
    local qs_value="false"

    [[ "$enabled" == "1" ]] && qs_value="true"
    atomic_write "$AUTO_STATE_FILE" "$enabled"
    if [[ "$send_ipc" == "true" ]] && command -v qs >/dev/null 2>&1; then
        env HOME="${HOME:-/home/$(id -un)}" XDG_RUNTIME_DIR="${RUNTIME_DIR}" qs -c ii ipc call orientation setAuto "$qs_value" >/dev/null 2>&1 || true
    fi
}

apply_rotation() {
    local transform="$1"
    local notify_change="${2:-true}"
    local monitor current escaped_monitor description

    [[ "$transform" =~ ^[0-3]$ ]] || return 2
    command -v hyprctl >/dev/null 2>&1 || return 1

    monitor=$(get_primary_monitor)
    current=$(get_current_transform)
    escaped_monitor=${monitor//\\/\\\\}
    escaped_monitor=${escaped_monitor//\"/\\\"}

    # `hyprctl keyword` is unavailable with Hyprland's Lua backend. Partial Lua
    # updates preserve this display's current mode, position and scale.
    if ! hyprctl eval \
        "hl.monitor({ output = \"${escaped_monitor}\", transform = ${transform} })" \
        >/dev/null 2>&1; then
        return 1
    fi
    if ! hyprctl eval \
        "hl.config({ input = { touchdevice = { transform = ${transform} }, tablet = { transform = ${transform} } } })" \
        >/dev/null 2>&1; then
        return 1
    fi

    publish_transform "$transform"
    [[ "$notify_change" == "true" && "$current" != "$transform" ]] || return 0
    command -v notify-send >/dev/null 2>&1 || return 0

    description="横屏 (0°)"
    case "$transform" in
        1) description="竖屏 (90°)" ;;
        2) description="倒置横屏 (180°)" ;;
        3) description="反向竖屏 (270°)" ;;
    esac
    notify-send -a "系统显示" -i screen_rotation -u low \
        "屏幕方向已旋转" "当前方向：${description}"
}

pid_is_auto_worker() {
    local pid="$1"
    local args

    [[ "$pid" =~ ^[0-9]+$ ]] || return 1
    kill -0 "$pid" 2>/dev/null || return 1
    args=$(tr '\0' ' ' < "/proc/${pid}/cmdline" 2>/dev/null || true)
    [[ "$args" == *"$SCRIPT_PATH"* && "$args" == *"auto-worker"* ]]
}

stop_pid_tree() {
    local pid="$1"
    local sid

    pid_is_auto_worker "$pid" || return 0
    sid=$(ps -o sid= -p "$pid" 2>/dev/null | tr -d ' ')
    if [[ "$sid" == "$pid" ]]; then
        kill -- "-${pid}" 2>/dev/null || true
    else
        pkill -TERM -P "$pid" 2>/dev/null || true
        kill "$pid" 2>/dev/null || true
    fi
}

auto_running() {
    local pid=""
    local saved_session=""
    local current_session="${HYPRLAND_INSTANCE_SIGNATURE:-unknown}"

    [[ -f "$AUTO_PID_FILE" ]] && read -r pid < "$AUTO_PID_FILE"
    [[ -f "$AUTO_SESSION_FILE" ]] && read -r saved_session < "$AUTO_SESSION_FILE"
    [[ "$saved_session" == "$current_session" ]] && pid_is_auto_worker "$pid"
}

auto_worker() {
    local fifo="${RUNTIME_DIR}/hypr_autorotate.sensor.${BASHPID}"
    local sensor_pid=""
    local cleaned="0"
    local line transform

    cleanup() {
        [[ "$cleaned" == "1" ]] && return 0
        cleaned="1"
        [[ -n "$sensor_pid" ]] && kill "$sensor_pid" 2>/dev/null || true
        rm -f "$fifo"
        publish_auto_state 0
    }
    trap cleanup EXIT INT TERM HUP

    rm -f "$fifo"
    mkfifo -m 600 "$fifo" || return 1

    export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=${RUNTIME_DIR}/bus}"

    if command -v systemd-run >/dev/null 2>&1; then
        systemd-run --user --pipe -q stdbuf -oL monitor-sensor --accel > "$fifo" 2>/dev/null &
    elif command -v stdbuf >/dev/null 2>&1; then
        stdbuf -oL monitor-sensor --accel > "$fifo" 2>/dev/null &
    else
        monitor-sensor --accel > "$fifo" 2>/dev/null &
    fi
    sensor_pid=$!
    publish_auto_state 1

    while IFS= read -r line; do
        transform=""
        case "$line" in
            *"orientation: normal"*|*"orientation changed: normal"*) transform=0 ;;
            *"orientation: bottom-up"*|*"orientation changed: bottom-up"*) transform=2 ;;
            *"orientation: right-up"*|*"orientation changed: right-up"*) transform=1 ;;
            *"orientation: left-up"*|*"orientation changed: left-up"*) transform=3 ;;
        esac
        [[ -n "$transform" ]] && apply_rotation "$transform" false
    done < "$fifo"
}

start_autorotate() {
    local pid=""
    local current_session="${HYPRLAND_INSTANCE_SIGNATURE:-unknown}"

    if auto_running; then
        publish_auto_state 1
        printf 'Auto-rotate is already running.\n'
        return 0
    fi
    command -v monitor-sensor >/dev/null 2>&1 || {
        printf 'monitor-sensor not found; install iio-sensor-proxy.\n' >&2
        publish_auto_state 0
        return 1
    }

    [[ -f "$AUTO_PID_FILE" ]] && read -r pid < "$AUTO_PID_FILE"
    [[ -n "$pid" ]] && stop_pid_tree "$pid"
    rm -f "$AUTO_PID_FILE" "$AUTO_SESSION_FILE"

    setsid "$SCRIPT_PATH" auto-worker >/dev/null 2>&1 &
    pid=$!
    atomic_write "$AUTO_PID_FILE" "$pid"
    atomic_write "$AUTO_SESSION_FILE" "$current_session"
    printf 'Auto-rotate started (PID: %s)\n' "$pid"
}

stop_autorotate() {
    local pid=""

    [[ -f "$AUTO_PID_FILE" ]] && read -r pid < "$AUTO_PID_FILE"
    [[ -n "$pid" ]] && stop_pid_tree "$pid"
    rm -f "$AUTO_PID_FILE" "$AUTO_SESSION_FILE"
    publish_auto_state 0
    printf 'Auto-rotate stopped.\n'
}

toggle_autorotate() {
    if auto_running; then
        stop_autorotate
        command -v notify-send >/dev/null 2>&1 \
            && notify-send -a "系统显示" -i screen_rotation -u low "重力自动旋转" "已关闭"
    else
        if start_autorotate && command -v notify-send >/dev/null 2>&1; then
            notify-send -a "系统显示" -i screen_rotation -u low "重力自动旋转" "已开启"
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
        if [[ "$CURRENT" == "1" || "$CURRENT" == "3" ]]; then
            apply_rotation 0
        else
            apply_rotation 1
        fi
        ;;
    next)
        CURRENT=$(get_current_transform)
        apply_rotation "$(( (CURRENT + 1) % 4 ))"
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
    auto-worker)
        auto_worker
        ;;
    auto-status)
        if auto_running; then
            publish_auto_state 1
            printf '1\n'
        else
            publish_auto_state 0
            printf '0\n'
        fi
        ;;
    check)
        CURRENT=$(get_current_transform)
        publish_transform "$CURRENT" false
        if auto_running; then
            publish_auto_state 1 false
        else
            publish_auto_state 0 false
        fi
        ;;
    status)
        get_current_transform
        ;;
    *)
        printf 'Usage: %s [0|1|2|3|toggle|next|auto-start|auto-stop|auto-toggle|auto-status|check|status]\n' "$0" >&2
        exit 1
        ;;
esac
