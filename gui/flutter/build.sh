#!/usr/bin/env bash
# build.sh — 构建 WordCard 桌面应用（Ubuntu / Linux release）
#
#   ./build.sh            # 增量构建
#   FORCE_C=1 ./build.sh  # 强制重编 C 核心
#
# Flutter SDK 位置可用 FLUTTER_HOME 覆盖（默认 ~/development/flutter）。
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
FLUTTER="${FLUTTER_HOME:-$HOME/development/flutter}/bin/flutter"

# 1) C 核心引擎
if [ "${FORCE_C:-0}" = "1" ] || [ ! -f "$ROOT/src/libwordcard.so" ]; then
    echo "[1/3] 编译 C 核心 libwordcard.so ..."
    make -C "$ROOT/src"
else
    echo "[1/3] 复用已有 $ROOT/src/libwordcard.so"
fi

# 2) Flutter SDK
if [ ! -x "$FLUTTER" ]; then
    echo "未找到 Flutter SDK: $FLUTTER" >&2
    echo "安装：" >&2
    echo "  git clone -b stable https://github.com/flutter/flutter.git ~/development/flutter" >&2
    exit 1
fi

cd "$HERE"
echo "[2/3] flutter pub get ..."
"$FLUTTER" pub get

echo "[3/3] flutter build linux --release ..."
"$FLUTTER" build linux --release

echo "完成：$HERE/build/linux/x64/release/bundle/wordcard"
