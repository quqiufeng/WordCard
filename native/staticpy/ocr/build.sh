#!/bin/bash
# build.sh — WordCard OCR StaticPy 原生 POC（自包含）
# 用法: bash native/staticpy/ocr/build.sh
#       wc_ocr <image> <out.txt>
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
BUILD="${XDG_CACHE_HOME:-$HOME/.cache}/wordcard-staticpy-ocr"
STATICPY_ROOT="${STATICPY_ROOT:-/opt/StaticPy}"
BUILD_COMPILER="$STATICPY_ROOT/staticpy/static_build_comfycli.sh"
FFI="$ROOT/native/staticpy/ffi.static.py"
mkdir -p "$BUILD" /tmp/opencode
[ -f "$BUILD_COMPILER" ] && [ -f "$FFI" ] || { echo "missing StaticPy compiler/ffi" >&2; exit 1; }


cat > "$BUILD/wc_ocr.static.py" <<'PY'
extern fn wc_ocr(image: str, out_path: str) -> int from "wc_ocr"

def main():
    args = list_to_py_list(argv())
    if py_list_length(args) < 3:
        print("usage: wc_ocr <image> <out.txt>")
        exit_program(1)
    print(wc_ocr(py_list_ref(args, 1), py_list_ref(args, 2)))
PY

CC="${CC:-gcc}"
$CC -O2 -fPIC -shared -I/usr/include "$ROOT/native/src/wc_ocr.c" \
  -L"$ROOT/voice/libs" -locr_simple -lcjson -Wl,-rpath,'$ORIGIN/../../../voice/libs' \
  -o "$HERE/libwc_ocr.so"

sed '/^extern fn /d' "$BUILD/wc_ocr.static.py" > "$BUILD/wc_ocr.body.py"
grep -E '^extern fn wc_ocr' "$FFI" > "$BUILD/wc_ocr.ffi.py"
cat "$BUILD/wc_ocr.ffi.py" "$BUILD/wc_ocr.body.py" > "$BUILD/wc_ocr.combined.py"
bash "$BUILD_COMPILER" "$BUILD/wc_ocr.combined.py" wc_ocr >/tmp/opencode/wc_ocr_build.log 2>&1
mv -f "$STATICPY_ROOT/wc_ocr" "$HERE/wc_ocr"
mv -f "$STATICPY_ROOT/wc_ocr.so" "$HERE/wc_ocr.so"
echo "built: $HERE/wc_ocr"
