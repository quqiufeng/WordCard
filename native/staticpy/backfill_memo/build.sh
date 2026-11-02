#!/bin/bash
# build.sh — WordCard 助记回填（LLM）StaticPy POC（自包含）
# 用法: wc_backfill_memo <db> [limit] [url] [model]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
BUILD="${XDG_CACHE_HOME:-$HOME/.cache}/wordcard-staticpy-backfill-memo"
STATICPY_ROOT="${STATICPY_ROOT:-/opt/StaticPy}"
BUILD_COMPILER="$STATICPY_ROOT/staticpy/static_build_comfycli.sh"
FFI="$ROOT/native/staticpy/ffi.static.py"
mkdir -p "$BUILD" /tmp/opencode
[ -f "$BUILD_COMPILER" ] && [ -f "$FFI" ] || { echo "missing StaticPy compiler/ffi" >&2; exit 1; }


cat > "$BUILD/wc_backfill_memo.static.py" <<'PY'
extern fn wc_backfill_memo(db: str, limit: int, url: str, model: str) -> int from "wc_backfill_memo"

def main():
    args = list_to_py_list(argv())
    n: int = py_list_length(args)
    if n < 2:
        print("usage: wc_backfill_memo <db> [limit] [url] [model]")
        exit_program(1)
    limit: int = 0
    if n > 2: limit = string_to_int(py_list_ref(args, 2))
    url: str = ""
    if n > 3: url = py_list_ref(args, 3)
    model: str = ""
    if n > 4: model = py_list_ref(args, 4)
    print(wc_backfill_memo(py_list_ref(args, 1), limit, url, model))
PY

CC="${CC:-gcc}"
$CC -O2 -fPIC -shared -I"$ROOT/src" "$ROOT/native/src/wc_backfill_memo.c" \
  -L"$ROOT/src" -lwordcard -L"$ROOT/native/staticpy/translate" -lwc_translate -lcurl -lcjson \
  -Wl,-rpath,'$ORIGIN/../../../src:$ORIGIN/../translate' \
  -o "$HERE/libwc_backfill_memo.so"

sed '/^extern fn /d' "$BUILD/wc_backfill_memo.static.py" > "$BUILD/wc_backfill_memo.body.py"
grep -E '^extern fn wc_backfill_memo' "$FFI" > "$BUILD/wc_backfill_memo.ffi.py"
cat "$BUILD/wc_backfill_memo.ffi.py" "$BUILD/wc_backfill_memo.body.py" > "$BUILD/wc_backfill_memo.combined.py"
bash "$BUILD_COMPILER" "$BUILD/wc_backfill_memo.combined.py" wc_backfill_memo >/tmp/opencode/wc_backfill_memo_build.log 2>&1
mv -f "$STATICPY_ROOT/wc_backfill_memo" "$HERE/wc_backfill_memo"
mv -f "$STATICPY_ROOT/wc_backfill_memo.so" "$HERE/wc_backfill_memo.so"
echo "built: $HERE/wc_backfill_memo"
