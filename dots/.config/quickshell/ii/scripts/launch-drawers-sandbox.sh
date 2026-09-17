#!/usr/bin/env bash
# 一键启动 Caelestia 一体化环绕内框与流体抽屉测试沙盒
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QML_FILE="$SCRIPT_DIR/../modules/ii/drawers/DrawersSandbox.qml"

export QML_IMPORT_PATH="$HOME/.local/lib/qt6/qml:${QML_IMPORT_PATH:-}"
export QML2_IMPORT_PATH="$HOME/.local/lib/qt6/qml:${QML2_IMPORT_PATH:-}"

echo "==> 启动流体画框沙盒: $QML_FILE"
exec qs -p "$QML_FILE"
