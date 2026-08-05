#!/usr/bin/env bash

CONFIG_FILE="$HOME/.config/illogical-impulse/config.json"
JSON_PATH=".screenRecord.savePath"

CUSTOM_PATH=$(jq -r "$JSON_PATH" "$CONFIG_FILE" 2>/dev/null)

RECORDING_DIR=""

if [[ -n "$CUSTOM_PATH" ]]; then
    RECORDING_DIR="$CUSTOM_PATH"
else
    RECORDING_DIR="$HOME/Videos" # Use default path
fi

getdate() {
    date '+%Y-%m-%d_%H.%M.%S'
}
getaudiooutput() {
    pactl list sources | grep 'Name' | grep 'monitor' | cut -d ' ' -f2
}
getactivemonitor() {
    hyprctl monitors -j | jq -r '.[] | select(.focused == true) | .name'
}

mkdir -p "$RECORDING_DIR"
cd "$RECORDING_DIR" || exit

# parse args
ARGS=("$@")
MANUAL_REGION=""
AUDIO_SRCS=()
FULLSCREEN_FLAG=0
GIF_FLAG=0
WINDOW_FLAG=0
for ((i=0;i<${#ARGS[@]};i++)); do
    if [[ "${ARGS[i]}" == "--region" ]]; then
        if (( i+1 < ${#ARGS[@]} )); then
            MANUAL_REGION="${ARGS[i+1]}"
        else
            notify-send "Recording cancelled" "No region specified for --region" -a 'Recorder' & disown
            exit 1
        fi
    elif [[ "${ARGS[i]}" == "--audio-src" ]]; then
        if (( i+1 < ${#ARGS[@]} )); then
            AUDIO_SRCS+=("${ARGS[i+1]}")
        fi
    elif [[ "${ARGS[i]}" == "--fullscreen" ]]; then
        FULLSCREEN_FLAG=1
    elif [[ "${ARGS[i]}" == "--window" ]]; then
        WINDOW_FLAG=1
    elif [[ "${ARGS[i]}" == "--gif" ]]; then
        GIF_FLAG=1
    fi
done

# 收集音频源（可多个：系统 + 麦克风同时录制）
AUDIO_ARGS=()
for src in "${AUDIO_SRCS[@]}"; do
    AUDIO_ARGS+=(--audio="$src")
done

if pgrep wf-recorder > /dev/null; then
    qs -c ii ipc call recording status none 2>/dev/null &
    notify-send "Recording Stopped" "Stopped" -a 'Recorder' &
    pkill -INT wf-recorder &
else
    # Resolve region (window -> active window geometry)
    if [[ $WINDOW_FLAG -eq 1 ]]; then
        if ! region="$(hyprctl activewindow -j | jq -r '"\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"' 2>/dev/null)"; then
            notify-send "Recording cancelled" "No active window" -a 'Recorder' & disown
            exit 1
        fi
    elif [[ $FULLSCREEN_FLAG -ne 1 ]]; then
        if [[ -n "$MANUAL_REGION" ]]; then
            region="$MANUAL_REGION"
        else
            if ! region="$(slurp 2>&1)"; then
                notify-send "Recording cancelled" "Selection was cancelled" -a 'Recorder' & disown
                exit 1
            fi
        fi
    fi

    if [[ $GIF_FLAG -eq 1 ]]; then
        notify-send "Starting recording" 'recording_'"$(getdate)"'.gif' -a 'Recorder' & disown
        qs -c ii ipc call recording status gif 2>/dev/null &
        tmp_file="./.tmp_recording_$(getdate).mp4"
        if [[ $FULLSCREEN_FLAG -eq 1 ]]; then
            wf-recorder -o "$(getactivemonitor)" --pixel-format yuv420p -f "$tmp_file" "${AUDIO_ARGS[@]}"
        else
            wf-recorder --pixel-format yuv420p -f "$tmp_file" --geometry "$region" "${AUDIO_ARGS[@]}"
        fi
        ffmpeg -y -i "$tmp_file" -vf "fps=15,scale=-2:720:flags=lanczos" "recording_$(getdate).gif" >/dev/null 2>&1
        rm -f "$tmp_file"
        qs -c ii ipc call recording status none 2>/dev/null &
    else
        notify-send "Starting recording" 'recording_'"$(getdate)"'.mp4' -a 'Recorder' & disown
        qs -c ii ipc call recording status screen 2>/dev/null &
        if [[ $FULLSCREEN_FLAG -eq 1 ]]; then
            wf-recorder -o "$(getactivemonitor)" --pixel-format yuv420p -f './recording_'"$(getdate)"'.mp4' "${AUDIO_ARGS[@]}"
        else
            wf-recorder --pixel-format yuv420p -f './recording_'"$(getdate)"'.mp4' --geometry "$region" "${AUDIO_ARGS[@]}"
        fi
        qs -c ii ipc call recording status none 2>/dev/null &
    fi
fi
