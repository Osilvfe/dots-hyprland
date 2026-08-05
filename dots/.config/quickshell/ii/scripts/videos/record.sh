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

# parse --region <value> without modifying $@ so other flags like --fullscreen still work
ARGS=("$@")
MANUAL_REGION=""
SOUND_FLAG=0
FULLSCREEN_FLAG=0
GIF_FLAG=0
for ((i=0;i<${#ARGS[@]};i++)); do
    if [[ "${ARGS[i]}" == "--region" ]]; then
        if (( i+1 < ${#ARGS[@]} )); then
            MANUAL_REGION="${ARGS[i+1]}"
        else
            notify-send "Recording cancelled" "No region specified for --region" -a 'Recorder' & disown
            exit 1
        fi
    elif [[ "${ARGS[i]}" == "--sound" ]]; then
        SOUND_FLAG=1
    elif [[ "${ARGS[i]}" == "--fullscreen" ]]; then
        FULLSCREEN_FLAG=1
    elif [[ "${ARGS[i]}" == "--gif" ]]; then
        GIF_FLAG=1
    fi
done

if pgrep wf-recorder > /dev/null; then
    qs -c ii ipc call recording status none 2>/dev/null &
    notify-send "Recording Stopped" "Stopped" -a 'Recorder' &
    pkill -INT wf-recorder &
else
    if [[ $FULLSCREEN_FLAG -eq 1 ]]; then
        if [[ $GIF_FLAG -eq 1 ]]; then
            notify-send "Starting recording" 'recording_'"$(getdate)"'.gif' -a 'Recorder' & disown
            qs -c ii ipc call recording status gif 2>/dev/null &
            tmp_file="./.tmp_recording_$(getdate).mp4"
            if [[ $SOUND_FLAG -eq 1 ]]; then
                wf-recorder -o "$(getactivemonitor)" --pixel-format yuv420p -f "$tmp_file" --audio="$(getaudiooutput)"
            else
                wf-recorder -o "$(getactivemonitor)" --pixel-format yuv420p -f "$tmp_file"
            fi
            ffmpeg -y -i "$tmp_file" -vf "fps=15,scale=-2:720:flags=lanczos" "recording_$(getdate).gif" >/dev/null 2>&1
            rm -f "$tmp_file"
            qs -c ii ipc call recording status none 2>/dev/null &
        else
            notify-send "Starting recording" 'recording_'"$(getdate)"'.mp4' -a 'Recorder' & disown
            qs -c ii ipc call recording status screen 2>/dev/null &
            if [[ $SOUND_FLAG -eq 1 ]]; then
                wf-recorder -o "$(getactivemonitor)" --pixel-format yuv420p -f './recording_'"$(getdate)"'.mp4' --audio="$(getaudiooutput)"
            else
                wf-recorder -o "$(getactivemonitor)" --pixel-format yuv420p -f './recording_'"$(getdate)"'.mp4'
            fi
            qs -c ii ipc call recording status none 2>/dev/null &
        fi
    else
        # If a manual region was provided via --region, use it; otherwise run slurp as before.
        if [[ -n "$MANUAL_REGION" ]]; then
            region="$MANUAL_REGION"
        else
            if ! region="$(slurp 2>&1)"; then
                notify-send "Recording cancelled" "Selection was cancelled" -a 'Recorder' & disown
                exit 1
            fi
        fi

        if [[ $GIF_FLAG -eq 1 ]]; then
            notify-send "Starting recording" 'recording_'"$(getdate)"'.gif' -a 'Recorder' & disown
            qs -c ii ipc call recording status gif 2>/dev/null &
            tmp_file="./.tmp_recording_$(getdate).mp4"
            if [[ $SOUND_FLAG -eq 1 ]]; then
                wf-recorder --pixel-format yuv420p -f "$tmp_file" --geometry "$region" --audio="$(getaudiooutput)"
            else
                wf-recorder --pixel-format yuv420p -f "$tmp_file" --geometry "$region"
            fi
            ffmpeg -y -i "$tmp_file" -vf "fps=15,scale=-2:720:flags=lanczos" "recording_$(getdate).gif" >/dev/null 2>&1
            rm -f "$tmp_file"
            qs -c ii ipc call recording status none 2>/dev/null &
        else
            notify-send "Starting recording" 'recording_'"$(getdate)"'.mp4' -a 'Recorder' & disown
            qs -c ii ipc call recording status screen 2>/dev/null &
            if [[ $SOUND_FLAG -eq 1 ]]; then
                wf-recorder --pixel-format yuv420p -f './recording_'"$(getdate)"'.mp4' --geometry "$region" --audio="$(getaudiooutput)"
            else
                wf-recorder --pixel-format yuv420p -f './recording_'"$(getdate)"'.mp4' --geometry "$region"
            fi
            qs -c ii ipc call recording status none 2>/dev/null &
        fi
    fi
fi