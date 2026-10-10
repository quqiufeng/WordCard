#!/usr/bin/env bash
# run.sh — 启动 WordCard 桌面应用
#
# 若尚未构建，会先调用 build.sh 再启动。
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
BUNDLE="$HERE/build/linux/x64/release/bundle"
BIN="$BUNDLE/wordcard"

# 运行时定位 C 核心库（libwordcard.so 等）
export LD_LIBRARY_PATH="$ROOT/src:$ROOT/libs:$ROOT/voice/libs:${LD_LIBRARY_PATH:-}"

if [ ! -x "$BIN" ]; then
    echo "尚未构建，正在编译 ..."
    "$HERE/build.sh" || { echo "构建失败，无法启动。" >&2; exit 1; }
fi

exec "$BIN" "$@"
