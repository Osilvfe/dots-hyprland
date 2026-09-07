#!/usr/bin/env bash
# Wrapper forwarding to compiled Rust ethernet-info
exec "$(dirname "$0")/ethernet-info.sh" "$@"
