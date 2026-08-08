#!/usr/bin/env bash
# Ensure kded6 (which owns org.kde.StatusNotifierWatcher) is running before qs
# starts. kded6 is stable in normal use; it is only absent when something
# (e.g. a crash) took it down, so we bring it back here. qs must NOT grab the
# watcher role itself, otherwise restarting qs orphans every SNI item.
set -u

# Fast, non-blocking check: if a watcher already exists, do nothing.
if timeout 2 busctl --user status org.kde.StatusNotifierWatcher >/dev/null 2>&1; then
    exit 0
fi

# No watcher present: start kded6 in the background and return immediately.
nohup /usr/bin/kded6 >/dev/null 2>&1 &

# Give it a moment to register the watcher (but never block the caller).
for _ in $(seq 1 20); do
    if timeout 2 busctl --user status org.kde.StatusNotifierWatcher >/dev/null 2>&1; then
        exit 0
    fi
    sleep 0.25
done

exit 1
