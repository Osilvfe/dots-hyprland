#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source_file="$script_dir/oplus-buds3-bridge.c"
cache_root="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell/helpers"
binary="$cache_root/oplus-buds3-bridge"

mkdir -p "$cache_root"

if [[ ! -x "$binary" || "$source_file" -nt "$binary" ]]; then
    temporary_binary="$binary.tmp.$$"
    trap 'rm -f "$temporary_binary"' EXIT
    cc -std=c11 -O2 -Wall -Wextra "$source_file" -o "$temporary_binary" -lbluetooth
    chmod 755 "$temporary_binary"
    mv -f "$temporary_binary" "$binary"
    trap - EXIT
fi

exec "$binary" "$@"
