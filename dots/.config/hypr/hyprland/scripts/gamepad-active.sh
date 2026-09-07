#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source_file="$script_dir/gamepad-active.rs"
cache_root="${XDG_CACHE_HOME:-$HOME/.cache}/hypr/helpers"
binary="$cache_root/gamepad-active"

mkdir -p "$cache_root"

if [[ ! -x "$binary" || "$source_file" -nt "$binary" ]]; then
    temporary_binary="$binary.tmp.$$"
    trap 'rm -f "$temporary_binary"' EXIT
    rustc -O "$source_file" -o "$temporary_binary"
    chmod 755 "$temporary_binary"
    mv -f "$temporary_binary" "$binary"
    trap - EXIT
fi

exec "$binary" "$@"
