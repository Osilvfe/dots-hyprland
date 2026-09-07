#!/usr/bin/env bash
# Wrapper forwarding to compiled Rust gamepad-active
exec "$(dirname "$0")/gamepad-active.sh" "$@"
