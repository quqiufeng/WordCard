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

# 1.5) StaticPy 原生能力（可选：编译器不存在时跳过）
if [ -f /opt/StaticPy/staticpy/static_build_comfycli.sh ] &&
   [ -f "$ROOT/native/staticpy/translate/build.sh" ] &&
   [ -f "$ROOT/native/staticpy/define/build.sh" ]; then
    echo "[1.5/3] 编译 StaticPy wc_translate/wc_define/wc_ocr/wc_voice/wc_ebook_json ..."
    bash "$ROOT/native/staticpy/translate/build.sh" >/tmp/opencode/wc_translate_build.log 2>&1 || true
    bash "$ROOT/native/staticpy/define/build.sh" >/tmp/opencode/wc_define_build.log 2>&1 || true
    bash "$ROOT/native/staticpy/ocr/build.sh" >/tmp/opencode/wc_ocr_build.log 2>&1 || true
    bash "$ROOT/native/staticpy/voice/build.sh" >/tmp/opencode/wc_voice_build.log 2>&1 || true
    bash "$ROOT/native/staticpy/ebook_json/build.sh" >/tmp/opencode/wc_ebook_json_build.log 2>&1 || true
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
