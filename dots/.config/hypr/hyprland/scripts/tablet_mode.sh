#!/usr/bin/env bash
# Track the detachable OnePlus Pogo keyboard and publish Hyprland tablet mode.

RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
STATE_FILE="${RUNTIME_DIR}/hypr_tablet_mode"
LISTEN_PID_FILE="${RUNTIME_DIR}/hypr_tablet_mode_listen.pid"
LISTEN_SESSION_FILE="${RUNTIME_DIR}/hypr_tablet_mode_listen.session"
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"

atomic_write() {
    local path="$1"
    local value="$2"
    local temporary="${path}.tmp.$$"

    printf '%s\n' "$value" > "$temporary" && mv -f "$temporary" "$path"
}

find_pogo_event() {
    local input name phys event

    for input in /sys/class/input/input*; do
        [[ -d "$input" ]] || continue
        name=$(cat "$input/name" 2>/dev/null || true)
        phys=$(cat "$input/phys" 2>/dev/null || true)

        if [[ "${name,,}" != "oneplus pogo keyboard" && "${phys,,}" != oneplus-pogo/* ]]; then
            continue
        fi

        for event in "$input"/event*; do
            [[ -e "$event" ]] || continue
            printf '/dev/input/%s\n' "$(basename "$event")"
            return 0
        done
    done

    return 1
}

detect_tablet_mode() {
    local event query_status

    # The Pogo input device is registered only while the connector is present.
    # Its kernel driver also exposes SW_TABLET_MODE for folded/detached states.
    if ! event=$(find_pogo_event); then
        printf '1\n'
        return 0
    fi

    if command -v evtest >/dev/null 2>&1 && [[ -r "$event" ]]; then
        evtest --query "$event" EV_SW SW_TABLET_MODE >/dev/null 2>&1
        query_status=$?
        case "$query_status" in
            10)
                printf '1\n'
                return 0
                ;;
            0)
                printf '0\n'
                return 0
                ;;
        esac
    fi

    # Access to /dev/input is optional. Presence of the exact Pogo device is a
    # safe desktop-mode fallback; unrelated keyboards must never affect this.
    printf '0\n'
}

publish_state() {
    local mode="$1"
    local notify_change="${2:-true}"
    local send_ipc="${3:-true}"
    local old_mode="unknown"
    local qs_value="false"

    [[ -f "$STATE_FILE" ]] && read -r old_mode < "$STATE_FILE"
    [[ "$mode" == "1" ]] && qs_value="true"
    atomic_write "$STATE_FILE" "$mode"

    if [[ "$send_ipc" == "true" ]] && command -v qs >/dev/null 2>&1; then
        qs -c ii ipc call tabletMode set "$qs_value" >/dev/null 2>&1 || true
    fi

    if [[ "$notify_change" == "true" && "$old_mode" != "unknown" && "$old_mode" != "$mode" ]] \
        && command -v notify-send >/dev/null 2>&1; then
        if [[ "$mode" == "1" ]]; then
            notify-send -a "系统模式" -i tablet -u low \
                "平板模式已激活" "Pogo 键盘已拆卸，已启用全触控交互"
        else
            notify-send -a "系统模式" -i keyboard -u low \
                "桌面模式已恢复" "Pogo 键盘已吸附连接"
        fi
    fi
}

pid_is_listener() {
    local pid="$1"
    local args

    [[ "$pid" =~ ^[0-9]+$ ]] || return 1
    kill -0 "$pid" 2>/dev/null || return 1
    args=$(tr '\0' ' ' < "/proc/${pid}/cmdline" 2>/dev/null || true)
    [[ "$args" == *"$SCRIPT_PATH"* && "$args" == *"listen-worker"* ]]
}

stop_pid_tree() {
    local pid="$1"
    local sid

    pid_is_listener "$pid" || return 0
    sid=$(ps -o sid= -p "$pid" 2>/dev/null | tr -d ' ')
    if [[ "$sid" == "$pid" ]]; then
        kill -- "-${pid}" 2>/dev/null || true
    else
        pkill -TERM -P "$pid" 2>/dev/null || true
        kill "$pid" 2>/dev/null || true
    fi
}

stop_listener() {
    local pid=""

    [[ -f "$LISTEN_PID_FILE" ]] && read -r pid < "$LISTEN_PID_FILE"
    [[ -n "$pid" ]] && stop_pid_tree "$pid"
    rm -f "$LISTEN_PID_FILE" "$LISTEN_SESSION_FILE"
}

listener_worker() {
    local fifo="${RUNTIME_DIR}/hypr_tablet_mode.udev.${BASHPID}"
    local monitor_pid=""
    local stopping="0"
    local line

    cleanup() {
        [[ -n "$monitor_pid" ]] && kill "$monitor_pid" 2>/dev/null || true
        monitor_pid=""
        rm -f "$fifo"
    }
    stop_worker() {
        stopping="1"
        cleanup
    }
    trap cleanup EXIT
    trap stop_worker INT TERM HUP

    publish_state "$(detect_tablet_mode)" false
    command -v udevadm >/dev/null 2>&1 || return 1

    while [[ "$stopping" == "0" ]]; do
        rm -f "$fifo"
        mkfifo -m 600 "$fifo" || return 1
        udevadm monitor --udev --subsystem-match=input > "$fifo" 2>/dev/null &
        monitor_pid=$!

        while IFS= read -r line; do
            [[ "$stopping" == "0" ]] || break
            case "$line" in
                *" add "*|*" remove "*|*" change "*)
                    # One event can create several input nodes. Let udev settle,
                    # then derive the state from the exact Pogo device.
                    sleep 0.35
                    publish_state "$(detect_tablet_mode)"
                    ;;
            esac
        done < "$fifo"

        wait "$monitor_pid" 2>/dev/null || true
        monitor_pid=""
        rm -f "$fifo"
        [[ "$stopping" == "0" ]] && sleep 1
    done
}

start_listener() {
    local pid=""
    local saved_session=""
    local current_session="${HYPRLAND_INSTANCE_SIGNATURE:-unknown}"

    [[ -f "$LISTEN_PID_FILE" ]] && read -r pid < "$LISTEN_PID_FILE"
    [[ -f "$LISTEN_SESSION_FILE" ]] && read -r saved_session < "$LISTEN_SESSION_FILE"
    if [[ "$saved_session" == "$current_session" ]] && pid_is_listener "$pid"; then
        publish_state "$(detect_tablet_mode)" false
        printf 'Tablet mode listener already running (PID: %s)\n' "$pid"
        return 0
    fi

    [[ -n "$pid" ]] && stop_pid_tree "$pid"
    rm -f "$LISTEN_PID_FILE" "$LISTEN_SESSION_FILE"

    setsid "$SCRIPT_PATH" listen-worker >/dev/null 2>&1 &
    pid=$!
    atomic_write "$LISTEN_PID_FILE" "$pid"
    atomic_write "$LISTEN_SESSION_FILE" "$current_session"
    printf 'Tablet mode listener started (PID: %s)\n' "$pid"
}

ACTION="${1:-check}"

case "$ACTION" in
    check)
        MODE=$(detect_tablet_mode)
        publish_state "$MODE" false false
        printf '%s\n' "$MODE"
        ;;
    status)
        if [[ -f "$STATE_FILE" ]]; then
            cat "$STATE_FILE"
        else
            detect_tablet_mode
        fi
        ;;
    pogo-status)
        if [[ "$(detect_tablet_mode)" == "0" ]]; then
            printf 'attached\n'
        else
            printf 'detached\n'
        fi
        ;;
    toggle)
        CURRENT="0"
        [[ -f "$STATE_FILE" ]] && read -r CURRENT < "$STATE_FILE"
        if [[ "$CURRENT" == "1" ]]; then
            publish_state "0"
        else
            publish_state "1"
        fi
        ;;
    listen)
        start_listener
        ;;
    listen-worker)
        listener_worker
        ;;
    stop-listen)
        stop_listener
        printf 'Tablet mode listener stopped.\n'
        ;;
    *)
        printf 'Usage: %s [check|status|pogo-status|toggle|listen|stop-listen]\n' "$0" >&2
        exit 1
        ;;
esac
