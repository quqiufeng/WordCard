#!/bin/bash
# build.sh — WordCard 卡片布局 StaticPy 原生版（POC，自包含）
# 本地只保留本脚本；C/StaticPy 源码在构建时生成到 ~/.cache。
#
# 用法:
#   bash native/staticpy/card/build.sh          # -> native/staticpy/card/wc_card
#   bash native/staticpy/card/build.sh --run    # 编译并渲染 /tmp/opencode/wc_card.png
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
BUILD="${XDG_CACHE_HOME:-$HOME/.cache}/wordcard-staticpy-card"
STATICPY_ROOT="${STATICPY_ROOT:-/opt/StaticPy}"
BUILD_COMPILER="$STATICPY_ROOT/staticpy/static_build_comfycli.sh"
FFI="$ROOT/native/staticpy/ffi.static.py"
mkdir -p "$BUILD" /tmp/opencode
[ -f "$BUILD_COMPILER" ] && [ -f "$FFI" ] || { echo "missing StaticPy compiler: $BUILD_COMPILER" >&2; exit 1; }


cat > "$BUILD/wc_card.static.py" <<'PY'
extern fn wc_canvas_create(w: int, h: int, bg: int) -> ptr from "wc_card"
extern fn wc_canvas_destroy(c: ptr) -> int from "wc_card"
extern fn wc_canvas_text(c: ptr, font: str, fs: float, text: str, x: int, y: int, color: int) -> int from "wc_card"
extern fn wc_canvas_measure(c: ptr, font: str, fs: float, text: str) -> int from "wc_card"
extern fn wc_canvas_line(c: ptr, x1: float, y1: float, x2: float, y2: float, color: int, width: float) -> int from "wc_card"
extern fn wc_canvas_rect(c: ptr, x: float, y: float, w: float, h: float, color: int, filled: int) -> int from "wc_card"
extern fn wc_canvas_save(c: ptr, path: str) -> int from "wc_card"

def main():
    font: str = "/opt/WordCard/LXGWWenKai-Regular.ttf"
    ink: int = 0x1B365D
    body: int = 0x2B2A26
    muted: int = 0x6B665C
    line: int = 0xE4DFD3
    c = wc_canvas_create(780, 1000, 0xF5F4ED)

    wc_canvas_text(c, font, 30, "WordCard · 读前预习", 40, 78, ink)
    wc_canvas_line(c, 40, 108, 740, 108, line, 1)

    wc_canvas_text(c, font, 20, "原文", 40, 158, ink)
    wc_canvas_text(c, font, 18, "The quick brown fox jumps over the lazy dog.", 40, 200, body)
    wc_canvas_text(c, font, 18, "Vocabulary learning should be deliberate and consistent.", 40, 232, body)

    wc_canvas_text(c, font, 20, "中英对照", 40, 304, ink)
    wc_canvas_text(c, font, 18, "敏捷的棕色狐狸跳过了懒狗。", 40, 346, body)
    wc_canvas_text(c, font, 18, "词汇学习应当刻意且持续。", 40, 378, body)

    wc_canvas_text(c, font, 20, "词汇表", 40, 450, ink)
    wc_canvas_rect(c, 40, 470, 700, 40, 0xFBFAF4, 1)
    wc_canvas_text(c, font, 17, "durable", 56, 497, ink)
    wc_canvas_text(c, font, 17, "a. 持久的；耐用的", 220, 497, muted)
    wc_canvas_text(c, font, 17, "deliberate", 56, 545, ink)
    wc_canvas_text(c, font, 17, "a. 刻意的；深思熟虑的", 220, 545, muted)
    wc_canvas_text(c, font, 17, "consistent", 56, 593, ink)
    wc_canvas_text(c, font, 17, "a. 持续的；一致的", 220, 593, muted)

    wc_canvas_text(c, font, 14, "WordCard · libwordcard.so · StaticPy ELF", 40, 960, muted)
    print(wc_canvas_save(c, "/tmp/opencode/wc_card.png"))
    print(wc_canvas_destroy(c))
PY

CC="${CC:-gcc}"
$CC -O2 -fPIC -shared -I"$ROOT/src" "$ROOT/native/src/wc_card.c" \
  -L"$ROOT/src" -ltxt2png -Wl,-rpath,'$ORIGIN/../../../src' \
  -o "$HERE/libwc_card.so"

sed '/^extern fn /d' "$BUILD/wc_card.static.py" > "$BUILD/wc_card.body.py"
grep -E '^extern fn wc_canvas_' "$FFI" > "$BUILD/wc_card.ffi.py"
cat "$BUILD/wc_card.ffi.py" "$BUILD/wc_card.body.py" > "$BUILD/wc_card.combined.py"
bash "$BUILD_COMPILER" \
  "$BUILD/wc_card.combined.py" wc_card >/tmp/opencode/wc_card_build.log 2>&1
mv -f "$STATICPY_ROOT/wc_card" "$HERE/wc_card"
mv -f "$STATICPY_ROOT/wc_card.so" "$HERE/wc_card.so"

echo "built: $HERE/wc_card"
if [ "${1:-}" = "--run" ]; then
  cd "$ROOT"
  LD_LIBRARY_PATH="$HERE:$ROOT/src" "$HERE/wc_card"
fi
