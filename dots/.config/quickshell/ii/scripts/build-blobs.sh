#!/usr/bin/env bash
# build-blobs.sh: 一键编译 Rust 核心引擎与 Caelestia.Blobs QML 流体形态插件
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"
CRATE_DIR="$ROOT_DIR/sdata/crates/quickshell-blobs"
PLUGIN_DIR="$CRATE_DIR/qml-plugin"
INSTALL_DIR="$HOME/.local/lib/qt6/qml/Caelestia/Blobs"

echo "==> 1. 构建 Rust 动力学与 UBO 核心引擎..."
cd "$CRATE_DIR"
cargo build --release

echo "==> 2. 构建 QML 流体形态原生模块 (Caelestia.Blobs)..."
cmake -B "$PLUGIN_DIR/build" -S "$PLUGIN_DIR" -DCMAKE_BUILD_TYPE=Release
cmake --build "$PLUGIN_DIR/build" -j"$(nproc)"

echo "==> 3. 安装模块至 $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
cp -f "$PLUGIN_DIR/build"/libcaelestia-blobs*.so "$INSTALL_DIR/"
cp -f "$PLUGIN_DIR/build"/qmldir "$INSTALL_DIR/"
if [[ -f "$PLUGIN_DIR/build/caelestia-blobs.qmltypes" ]]; then
    cp -f "$PLUGIN_DIR/build/caelestia-blobs.qmltypes" "$INSTALL_DIR/"
fi

echo "==> 完成！Quickshell 现在可以通过 import Caelestia.Blobs 1.0 直接调用流体组件。"
