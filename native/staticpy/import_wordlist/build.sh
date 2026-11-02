#!/bin/bash
# build.sh — WordCard 考试词表导入（StaticPy 原生 POC，自包含）
# 用法: wc_import_wordlist <wordlist.tsv> <db> <name> [limit]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
BUILD="${XDG_CACHE_HOME:-$HOME/.cache}/wordcard-staticpy-import-wordlist"
STATICPY_ROOT="${STATICPY_ROOT:-/opt/StaticPy}"
BUILD_COMPILER="$STATICPY_ROOT/staticpy/static_build_comfycli.sh"
FFI="$ROOT/native/staticpy/ffi.static.py"
mkdir -p "$BUILD" /tmp/opencode
[ -f "$BUILD_COMPILER" ] && [ -f "$FFI" ] || { echo "missing StaticPy compiler/ffi" >&2; exit 1; }


cat > "$BUILD/wc_import_wordlist.static.py" <<'PY'
extern fn wc_import_wordlist(tsv: str, db: str, name: str, limit: int) -> int from "wc_import_wordlist"

def main():
    args = list_to_py_list(argv())
    n: int = py_list_length(args)
    if n < 4:
        print("usage: wc_import_wordlist <tsv> <db> <name> [limit]")
        exit_program(1)
    limit: int = 0
    if n > 4:
        limit = string_to_int(py_list_ref(args, 4))
    print(wc_import_wordlist(py_list_ref(args, 1), py_list_ref(args, 2),
                             py_list_ref(args, 3), limit))
PY

CC="${CC:-gcc}"
$CC -O2 -fPIC -shared -I"$ROOT/src" "$ROOT/native/src/wc_import_wordlist.c" \
  -L"$ROOT/src" -lwordcard -Wl,-rpath,'$ORIGIN/../../../src' \
  -o "$HERE/libwc_import_wordlist.so"

sed '/^extern fn /d' "$BUILD/wc_import_wordlist.static.py" > "$BUILD/wc_import_wordlist.body.py"
grep -E '^extern fn wc_import_wordlist' "$FFI" > "$BUILD/wc_import_wordlist.ffi.py"
cat "$BUILD/wc_import_wordlist.ffi.py" "$BUILD/wc_import_wordlist.body.py" > "$BUILD/wc_import_wordlist.combined.py"
bash "$BUILD_COMPILER" "$BUILD/wc_import_wordlist.combined.py" wc_import_wordlist >/tmp/opencode/wc_import_wordlist_build.log 2>&1
mv -f "$STATICPY_ROOT/wc_import_wordlist" "$HERE/wc_import_wordlist"
mv -f "$STATICPY_ROOT/wc_import_wordlist.so" "$HERE/wc_import_wordlist.so"
echo "built: $HERE/wc_import_wordlist"
