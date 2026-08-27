#!/usr/bin/env bash

set -euo pipefail

get_pictures_dir() {
    if command -v xdg-user-dir &> /dev/null; then
        xdg-user-dir PICTURES
        return
    fi

    local config_file="${XDG_CONFIG_HOME:-$HOME/.config}/user-dirs.dirs"
    if [[ -f "$config_file" ]]; then
        local pictures_path
        pictures_path=$(source "$config_file" >/dev/null 2>&1; echo "$XDG_PICTURES_DIR")
        echo "${pictures_path/#\$HOME/$HOME}"
        return
    fi

    echo "$HOME/Pictures"
}

fail() {
    printf '[wallhaven-wallpaper] %s\n' "$1" >&2
    notify-send -a Shell 'Wallhaven wallpaper' "$1" 2>/dev/null || true
    exit 1
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PICTURES_DIR="$(get_pictures_dir)/Wallpapers"
API_URL='https://wallhaven.cc/api/v1/search?categories=111&purity=100&sorting=random&atleast=1920x1080&ratios=16x9'

mkdir -p "$PICTURES_DIR"

response=$(curl --fail --location --silent --show-error \
    --retry 2 --connect-timeout 10 --max-time 45 "$API_URL") \
    || fail '无法获取随机壁纸信息'
result_count=$(jq -er '.data | length' <<< "$response") \
    || fail '接口返回的数据无效'
(( result_count > 0 )) || fail '没有符合筛选条件的壁纸'

random_index=$((RANDOM % result_count))
wallpaper_id=$(jq -er ".data[$random_index].id" <<< "$response") \
    || fail '接口没有返回壁纸 ID'
image_url=$(jq -er ".data[$random_index].path" <<< "$response") \
    || fail '接口没有返回原图地址'
[[ "$wallpaper_id" =~ ^[a-zA-Z0-9]{6}$ ]] || fail '接口返回的壁纸 ID 无效'
[[ "$image_url" == 'https://w.wallhaven.cc/full/'* ]] || fail '接口返回的原图地址无效'
extension="${image_url##*.}"
extension="${extension%%\?*}"
case "$extension" in
    jpg|jpeg|png|webp) ;;
    *) extension='jpg' ;;
esac
download_path="$PICTURES_DIR/wallhaven-${wallpaper_id}.${extension}"

if [[ ! -s "$download_path" ]]; then
    temporary_path=$(mktemp "$PICTURES_DIR/.wallhaven-${wallpaper_id}.XXXXXX")
    trap 'rm -f "$temporary_path"' EXIT
    curl --fail --location --silent --show-error \
        --retry 2 --connect-timeout 10 --max-time 120 \
        "$image_url" -o "$temporary_path" \
        || fail '随机壁纸下载失败'
    file --brief --mime-type "$temporary_path" | grep -q '^image/' \
        || fail '下载内容不是有效图片'
    mv -f "$temporary_path" "$download_path"
    trap - EXIT
fi

"$SCRIPT_DIR/../switchwall.sh" --image "$download_path"
