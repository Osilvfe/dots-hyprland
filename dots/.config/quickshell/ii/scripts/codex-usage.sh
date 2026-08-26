#!/usr/bin/env bash
# Print the current Codex rate-limit snapshot as one JSON line.
# The Codex app-server owns authentication; this script never reads credentials.

set -u

if ! command -v codex >/dev/null 2>&1; then
    exit 1
fi

coproc codex_server { codex app-server --stdio 2>/dev/null; }

cleanup() {
    if [[ -n "${codex_server_PID:-}" ]]; then
        exec {codex_server[1]}>&- 2>/dev/null || true
        kill "$codex_server_PID" 2>/dev/null || true
        wait "$codex_server_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

printf '%s\n' '{"method":"initialize","id":1,"params":{"clientInfo":{"name":"quickshell-codex-usage","title":"Quickshell Codex usage","version":"1.0"}}}' >&"${codex_server[1]}"

if ! IFS= read -r -t 10 init_response <&"${codex_server[0]}"; then
    exit 1
fi

if [[ "$init_response" != *'"id":1'* || "$init_response" == *'"error"'* ]]; then
    exit 1
fi

printf '%s\n' '{"method":"initialized"}' '{"method":"account/rateLimits/read","id":2}' >&"${codex_server[1]}"

while IFS= read -r -t 10 response <&"${codex_server[0]}"; do
    if [[ "$response" == *'"id":2'* ]]; then
        [[ "$response" == *'"error"'* ]] && exit 1
        printf '%s\n' "$response"
        exit 0
    fi
done

exit 1
