#!/bin/bash
# build.sh — WordCard 释义回填 StaticPy 原生 POC（自包含）
# 用法: wc_backfill <db> <dict.tsv>
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
BUILD="${XDG_CACHE_HOME:-$HOME/.cache}/wordcard-staticpy-backfill"
STATICPY_ROOT="${STATICPY_ROOT:-/opt/StaticPy}"
BUILD_COMPILER="$STATICPY_ROOT/staticpy/static_build_comfycli.sh"
FFI="$ROOT/native/staticpy/ffi.static.py"
mkdir -p "$BUILD" /tmp/opencode
[ -f "$BUILD_COMPILER" ] && [ -f "$FFI" ] || { echo "missing StaticPy compiler/ffi" >&2; exit 1; }


cat > "$BUILD/wc_backfill.static.py" <<'PY'
extern fn wc_backfill(db: str, dict: str) -> int from "wc_backfill"

def main():
    args = list_to_py_list(argv())
    if py_list_length(args) < 3:
        print("usage: wc_backfill <db> <dict.tsv>")
        exit_program(1)
    print(wc_backfill(py_list_ref(args, 1), py_list_ref(args, 2)))
PY

CC="${CC:-gcc}"
$CC -O2 -fPIC -shared -I"$ROOT/src" "$ROOT/native/src/wc_backfill.c" \
  -L"$ROOT/src" -lwordcard -Wl,-rpath,'$ORIGIN/../../../src' \
  -o "$HERE/libwc_backfill.so"

sed '/^extern fn /d' "$BUILD/wc_backfill.static.py" > "$BUILD/wc_backfill.body.py"
grep -E '^extern fn wc_backfill' "$FFI" > "$BUILD/wc_backfill.ffi.py"
cat "$BUILD/wc_backfill.ffi.py" "$BUILD/wc_backfill.body.py" > "$BUILD/wc_backfill.combined.py"
bash "$BUILD_COMPILER" "$BUILD/wc_backfill.combined.py" wc_backfill >/tmp/opencode/wc_backfill_build.log 2>&1
mv -f "$STATICPY_ROOT/wc_backfill" "$HERE/wc_backfill"
mv -f "$STATICPY_ROOT/wc_backfill.so" "$HERE/wc_backfill.so"
echo "built: $HERE/wc_backfill"
