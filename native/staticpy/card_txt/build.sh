#!/bin/bash
# build.sh — WordCard 从 _trans.txt 生成卡片（StaticPy 原生 POC，自包含）
# 用法:
#   bash native/staticpy/card_txt/build.sh
#   LD_LIBRARY_PATH=native/staticpy/card_txt:src native/staticpy/card_txt/wc_card_txt \
#     output/solar_system_trans.txt /tmp/opencode/wc_card_txt.png /tmp/opencode/wc_card_txt.md
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
BUILD="${XDG_CACHE_HOME:-$HOME/.cache}/wordcard-staticpy-card-txt"
STATICPY_ROOT="${STATICPY_ROOT:-/opt/StaticPy}"
BUILD_COMPILER="$STATICPY_ROOT/staticpy/static_build_comfycli.sh"
FFI="$ROOT/native/staticpy/ffi.static.py"
mkdir -p "$BUILD" /tmp/opencode
[ -f "$BUILD_COMPILER" ] && [ -f "$FFI" ] || { echo "missing StaticPy compiler/ffi" >&2; exit 1; }


cat > "$BUILD/wc_card_txt.static.py" <<'PY'
extern fn wc_card_txt(input: str, png: str, md: str, pdf: str) -> int from "wc_card_txt"

def main():
    args = list_to_py_list(argv())
    n: int = py_list_length(args)
    if n < 4:
        print("usage: wc_card_txt <trans.txt> <out.png> <out.md> [out.pdf]")
        exit_program(1)
    pdf: str = ""
    if n > 4:
        pdf = py_list_ref(args, 4)
    print(wc_card_txt(py_list_ref(args, 1), py_list_ref(args, 2), py_list_ref(args, 3), pdf))
PY

CC="${CC:-gcc}"
$CC -O2 -fPIC -shared -I"$ROOT/src" "$ROOT/native/src/card_txt.c" \
  -L"$ROOT/src" -ltxt2png -Wl,-rpath,'$ORIGIN/../../../src' \
  -o "$HERE/libwc_card_txt.so"

sed '/^extern fn /d' "$BUILD/wc_card_txt.static.py" > "$BUILD/wc_card_txt.body.py"
grep -E '^extern fn wc_card_txt' "$FFI" > "$BUILD/wc_card_txt.ffi.py"
cat "$BUILD/wc_card_txt.ffi.py" "$BUILD/wc_card_txt.body.py" > "$BUILD/wc_card_txt.combined.py"
bash "$BUILD_COMPILER" \
  "$BUILD/wc_card_txt.combined.py" wc_card_txt >/tmp/opencode/wc_card_txt_build.log 2>&1
mv -f "$STATICPY_ROOT/wc_card_txt" "$HERE/wc_card_txt"
mv -f "$STATICPY_ROOT/wc_card_txt.so" "$HERE/wc_card_txt.so"

echo "built: $HERE/wc_card_txt"
