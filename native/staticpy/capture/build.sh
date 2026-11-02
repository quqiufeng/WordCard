#!/bin/bash
# build.sh — WordCard 录音 capture StaticPy 原生 POC（自包含）
# 用法: wc_capture <out.wav> [seconds] [device]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
BUILD="${XDG_CACHE_HOME:-$HOME/.cache}/wordcard-staticpy-capture"
STATICPY_ROOT="${STATICPY_ROOT:-/opt/StaticPy}"
BUILD_COMPILER="$STATICPY_ROOT/staticpy/static_build_comfycli.sh"
FFI="$ROOT/native/staticpy/ffi.static.py"
mkdir -p "$BUILD" /tmp/opencode
[ -f "$BUILD_COMPILER" ] && [ -f "$FFI" ] || { echo "missing StaticPy compiler/ffi" >&2; exit 1; }


cat > "$BUILD/wc_capture.static.py" <<'PY'
extern fn wc_capture(out: str, seconds: int, device: str) -> int from "wc_capture"

def main():
    args = list_to_py_list(argv())
    n: int = py_list_length(args)
    if n < 2:
        print("usage: wc_capture <out.wav> [seconds] [device]")
        exit_program(1)
    seconds: int = 2
    if n > 2: seconds = string_to_int(py_list_ref(args, 2))
    device: str = "plughw:CARD=Webcams,0"
    if n > 3: device = py_list_ref(args, 3)
    print(wc_capture(py_list_ref(args, 1), seconds, device))
PY

CC="${CC:-gcc}"
$CC -O2 -fPIC -shared -I"$ROOT/voice/wrappers" "$ROOT/native/src/wc_capture.c" \
  -L"$ROOT/voice/libs" -lvoice_engine -Wl,-rpath,'$ORIGIN/../../../voice/libs' \
  -o "$HERE/libwc_capture.so"

sed '/^extern fn /d' "$BUILD/wc_capture.static.py" > "$BUILD/wc_capture.body.py"
grep -E '^extern fn wc_capture' "$FFI" > "$BUILD/wc_capture.ffi.py"
cat "$BUILD/wc_capture.ffi.py" "$BUILD/wc_capture.body.py" > "$BUILD/wc_capture.combined.py"
bash "$BUILD_COMPILER" "$BUILD/wc_capture.combined.py" wc_capture >/tmp/opencode/wc_capture_build.log 2>&1
mv -f "$STATICPY_ROOT/wc_capture" "$HERE/wc_capture"
mv -f "$STATICPY_ROOT/wc_capture.so" "$HERE/wc_capture.so"
echo "built: $HERE/wc_capture"
