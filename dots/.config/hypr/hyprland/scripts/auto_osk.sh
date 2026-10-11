#!/usr/bin/env bash
# Auto-show and hide on-screen keyboard based on text-input focus and tablet mode.

RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
TABLET_STATE_FILE="${RUNTIME_DIR}/hypr_tablet_mode"
PID_FILE="${RUNTIME_DIR}/hypr_auto_osk.pid"
SESSION_FILE="${RUNTIME_DIR}/hypr_auto_osk.session"
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"

if [[ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
    HYPRLAND_INSTANCE_SIGNATURE=$(find "${RUNTIME_DIR}/hypr" -mindepth 1 -maxdepth 1 -type d -printf '%P\n' 2>/dev/null | head -n 1 || true)
    export HYPRLAND_INSTANCE_SIGNATURE
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

is_tablet_mode() {
    if [[ -f "$TABLET_STATE_FILE" ]]; then
        local state
        read -r state < "$TABLET_STATE_FILE" 2>/dev/null || true
        [[ "$state" == "1" ]] && return 0
    fi
    return 1
}

pid_is_worker() {
    local pid="$1"
    local args

    [[ "$pid" =~ ^[0-9]+$ ]] || return 1
    kill -0 "$pid" 2>/dev/null || return 1
    args=$(tr '\0' ' ' < "/proc/${pid}/cmdline" 2>/dev/null || true)
    [[ "$args" == *"$SCRIPT_PATH"* && "$args" == *"worker"* ]]
}

stop_worker_proc() {
    local pid=""
    [[ -f "$PID_FILE" ]] && read -r pid < "$PID_FILE" 2>/dev/null || true
    if [[ -n "$pid" ]] && pid_is_worker "$pid"; then
        kill "$pid" 2>/dev/null || true
    fi
    pkill -f "${SCRIPT_PATH} worker" 2>/dev/null || true
    rm -f "$PID_FILE" "$SESSION_FILE"
}

worker() {
    local close_pid=""
    local monitor_pid=""
    local cleaned="0"
    local fifo="${RUNTIME_DIR}/hypr_auto_osk.fifo.${BASHPID}"
    local line

    cleanup() {
        [[ "$cleaned" == "1" ]] && return 0
        cleaned="1"
        [[ -n "$close_pid" ]] && kill "$close_pid" 2>/dev/null || true
        [[ -n "$monitor_pid" ]] && kill "$monitor_pid" 2>/dev/null || true
        rm -f "$fifo"
    }
    trap cleanup EXIT INT TERM HUP

    export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=${RUNTIME_DIR}/bus}"

    while true; do
        rm -f "$fifo"
        mkfifo -m 600 "$fifo" || { sleep 1; continue; }

        if command -v stdbuf >/dev/null 2>&1; then
            stdbuf -oL busctl --user monitor org.fcitx.Fcitx5 > "$fifo" 2>/dev/null &
        else
            busctl --user monitor org.fcitx.Fcitx5 > "$fifo" 2>/dev/null &
        fi
        monitor_pid=$!

        while IFS= read -r line; do
            if [[ "$line" == *"Member=FocusIn"* ]]; then
                # Cancel any pending debounce close
                if [[ -n "$close_pid" ]]; then
                    kill "$close_pid" 2>/dev/null || true
                    close_pid=""
                fi
                if is_tablet_mode && command -v qs >/dev/null 2>&1; then
                    env HOME="${HOME:-/home/$(id -un)}" XDG_RUNTIME_DIR="${RUNTIME_DIR}" \
                        qs -c ii ipc --any-display call osk open >/dev/null 2>&1 || true
                fi
            elif [[ "$line" == *"Member=FocusOut"* ]]; then
                if [[ -n "$close_pid" ]]; then
                    kill "$close_pid" 2>/dev/null || true
                fi
                # Debounce by 250ms to allow smooth focus transfer between input fields
                (
                    sleep 0.25
                    if is_tablet_mode && command -v qs >/dev/null 2>&1; then
                        env HOME="${HOME:-/home/$(id -un)}" XDG_RUNTIME_DIR="${RUNTIME_DIR}" \
                            qs -c ii ipc --any-display call osk close >/dev/null 2>&1 || true
                    fi
                ) &
                close_pid=$!
            fi
        done < "$fifo"

        [[ -n "$monitor_pid" ]] && kill "$monitor_pid" 2>/dev/null || true
        monitor_pid=""
        rm -f "$fifo"
        sleep 1
    done
}

start_daemon() {
    local pid=""
    local current_session="${HYPRLAND_INSTANCE_SIGNATURE:-unknown}"

    if [[ -f "$PID_FILE" ]] && read -r pid < "$PID_FILE" 2>/dev/null && pid_is_worker "$pid"; then
        printf 'Auto-OSK daemon is already running (PID: %s)\n' "$pid"
        return 0
    fi

    stop_worker_proc

    setsid "$SCRIPT_PATH" worker >/dev/null 2>&1 &
    pid=$!
    atomic_write "$PID_FILE" "$pid"
    atomic_write "$SESSION_FILE" "$current_session"
    printf 'Auto-OSK daemon started (PID: %s)\n' "$pid"
}

stop_daemon() {
    stop_worker_proc
    printf 'Auto-OSK daemon stopped.\n'
}

status_daemon() {
    local pid=""
    if [[ -f "$PID_FILE" ]] && read -r pid < "$PID_FILE" 2>/dev/null && pid_is_worker "$pid"; then
        printf '1\n'
    else
        printf '0\n'
    fi
}

ACTION="${1:-start}"

case "$ACTION" in
    start)
        start_daemon
        ;;
    stop)
        stop_daemon
        ;;
    status)
        status_daemon
        ;;
    worker)
        worker
        ;;
    restart)
        stop_daemon
        sleep 0.2
        start_daemon
        ;;
    *)
        printf 'Usage: %s [start|stop|restart|status|worker]\n' "$0" >&2
        exit 1
        ;;
esac
