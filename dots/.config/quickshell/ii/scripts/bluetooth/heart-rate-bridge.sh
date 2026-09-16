#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source_file="$script_dir/heart-rate-bridge.rs"
cache_root="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell/helpers"
binary="$cache_root/heart-rate-bridge"

mkdir -p "$cache_root"

if [[ ! -x "$binary" || "$source_file" -nt "$binary" ]]; then
    temporary_binary="$binary.tmp.$$"
    trap 'rm -f "$temporary_binary"' EXIT
    rustc -O --edition 2021 "$source_file" -o "$temporary_binary"
    chmod 755 "$temporary_binary"
    mv -f "$temporary_binary" "$binary"
    trap - EXIT
fi

pkill -x heart-rate-bridge 2>/dev/null || true
exec "$binary" "$@"
