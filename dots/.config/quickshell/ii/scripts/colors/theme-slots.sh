#!/usr/bin/env bash
# Save and restore wallpaper-backed theme snapshots. Each slot retains the
# wallpaper, palette type, optional custom accent color, and light/dark mode.
set -euo pipefail

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
DIR="$XDG_STATE_HOME/quickshell/user/theme-slots"
INDEX="$DIR/slots.json"
CFG="$XDG_CONFIG_HOME/illogical-impulse/config.json"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAX=10

mkdir -p "$DIR"
[ -s "$INDEX" ] || printf '[%s]' "$(printf 'null,%.0s' $(seq $((MAX - 1))))null" > "$INDEX"

die() {
    notify-send -a "Theme slots" "$1" "${2:-}" 2>/dev/null || true
    echo "$1 ${2:-}" >&2
    exit 1
}

idx_of() {
    [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ] && [ "$1" -le "$MAX" ] || die "Invalid slot" "$1 (expected 1..$MAX)"
    echo $(( $1 - 1 ))
}

case "${1:-list}" in
save)
    if [ -n "${2:-}" ]; then
        i=$(idx_of "$2")
    else
        i=$(jq 'index(null) // -1' "$INDEX")
        [ "$i" -ge 0 ] || die "All slots are full" "Delete a slot in Settings to free up space."
    fi
    wall=$(jq -r '.background.wallpaperPath' "$CFG")
    [ -f "$wall" ] || die "Wallpaper not found" "$wall"
    mode=light
    gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null | grep -q dark && mode=dark
    type=$(jq -r '.appearance.palette.type // "auto"' "$CFG")
    accent=$(jq -r '.appearance.palette.accentColor // ""' "$CFG")
    ext="${wall##*.}"
    rm -f "$DIR/slot$((i + 1))."*
    cp "$wall" "$DIR/slot$((i + 1)).$ext"
    swatches=$(magick "$wall" -resize 64x64^ +dither -colors 4 -unique-colors txt:- 2>/dev/null | grep -oE '#[0-9A-Fa-f]{6}' | head -4 | jq -R . | jq -cs .)
    [ -n "$swatches" ] && [ "$swatches" != "[]" ] || swatches='[]'
    jq --argjson i "$i" --arg file "$DIR/slot$((i + 1)).$ext" --arg mode "$mode" --arg type "$type" --arg accent "$accent" --arg date "$(date +%d/%m)" --argjson colors "$swatches" \
        '.[$i] = {file: $file, mode: $mode, type: $type, accentColor: $accent, date: $date, colors: $colors}' \
        "$INDEX" > "$INDEX.tmp" && mv "$INDEX.tmp" "$INDEX"
    notify-send -a "Theme slots" "Theme saved" "Slot $((i + 1)) - $mode - $type" 2>/dev/null || true
    ;;
restore)
    i=$(idx_of "${2:?slot required}")
    entry=$(jq -c ".[$i]" "$INDEX")
    [ "$entry" != "null" ] || die "Empty slot" "Slot $((i + 1))"
    file=$(jq -r '.file' <<<"$entry")
    mode=$(jq -r '.mode' <<<"$entry")
    type=$(jq -r '.type' <<<"$entry")
    accent=$(jq -r '.accentColor // ""' <<<"$entry")
    [ -f "$file" ] || die "Slot image is gone" "$file"
    jq --arg type "$type" --arg accent "$accent" '.appearance.palette.type = $type | .appearance.palette.accentColor = $accent' "$CFG" > "$CFG.tmp" && mv "$CFG.tmp" "$CFG"
    exec "$SCRIPT_DIR/switchwall.sh" --image "$file" --mode "$mode"
    ;;
delete)
    i=$(idx_of "${2:?slot required}")
    file=$(jq -r ".[$i].file // empty" "$INDEX")
    if [ -n "$file" ] && [ "$file" = "$(jq -r '.background.wallpaperPath' "$CFG")" ]; then
        die "Slot is active" "This slot is the current wallpaper - change wallpaper before deleting it."
    fi
    [ -n "$file" ] && rm -f "$file"
    jq --argjson i "$i" '.[$i] = null' "$INDEX" > "$INDEX.tmp" && mv "$INDEX.tmp" "$INDEX"
    ;;
list)
    cat "$INDEX"
    ;;
*)
    die "Unknown command" "$1"
    ;;
esac
