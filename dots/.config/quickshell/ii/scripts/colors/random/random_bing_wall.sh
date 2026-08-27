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
    printf '[bing-wallpaper] %s\n' "$1" >&2
    notify-send -a Shell 'Bing wallpaper' "$1" 2>/dev/null || true
    exit 1
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PICTURES_DIR="$(get_pictures_dir)/Wallpapers"
API_URL='https://cn.bing.com/HPImageArchive.aspx?format=js&idx=0&n=1&mkt=zh-CN'

mkdir -p "$PICTURES_DIR"

response=$(curl --fail --location --silent --show-error \
    --retry 2 --connect-timeout 10 --max-time 30 "$API_URL") \
    || fail '无法获取今日壁纸信息'

start_date=$(jq -er '.images[0].startdate' <<< "$response") \
    || fail '接口返回的数据无效'
url_base=$(jq -er '.images[0].urlbase' <<< "$response") \
    || fail '接口没有返回壁纸地址'
[[ "$start_date" =~ ^[0-9]{8}$ ]] || fail '接口返回的日期无效'
[[ "$url_base" == '/th?id='* ]] || fail '接口返回的壁纸地址无效'
download_path="$PICTURES_DIR/bing-${start_date}.jpg"

if [[ ! -s "$download_path" ]]; then
    temporary_path=$(mktemp "$PICTURES_DIR/.bing-${start_date}.XXXXXX")
    trap 'rm -f "$temporary_path"' EXIT
    curl --fail --location --silent --show-error \
        --retry 2 --connect-timeout 10 --max-time 90 \
        "https://cn.bing.com${url_base}_UHD.jpg" -o "$temporary_path" \
        || fail '今日壁纸下载失败'
    file --brief --mime-type "$temporary_path" | grep -q '^image/' \
        || fail '下载内容不是有效图片'
    mv -f "$temporary_path" "$download_path"
    trap - EXIT
fi

"$SCRIPT_DIR/../switchwall.sh" --image "$download_path"
