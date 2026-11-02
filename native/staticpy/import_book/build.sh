#!/bin/bash
# build.sh — WordCard 电子书导入（PDF/MOBI/EPUB/MD）StaticPy POC（自包含）
# 用法: wc_import_book <book> <db> <tag> [max_words]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
BUILD="${XDG_CACHE_HOME:-$HOME/.cache}/wordcard-staticpy-import-book"
STATICPY_ROOT="${STATICPY_ROOT:-/opt/StaticPy}"
BUILD_COMPILER="$STATICPY_ROOT/staticpy/static_build_comfycli.sh"
FFI="$ROOT/native/staticpy/ffi.static.py"
mkdir -p "$BUILD" /tmp/opencode
[ -f "$BUILD_COMPILER" ] && [ -f "$FFI" ] || { echo "missing StaticPy compiler/ffi" >&2; exit 1; }


cat > "$BUILD/wc_import_book.static.py" <<'PY'
extern fn wc_import_book(path: str, db: str, tag: str, max_words: int, freq: str) -> int from "wc_import_book"

def main():
    args = list_to_py_list(argv())
    n: int = py_list_length(args)
    if n < 4:
        print("usage: wc_import_book <book> <db> <tag> [max_words] [freq.tsv]")
        exit_program(1)
    max_words: int = 50
    if n > 4: max_words = string_to_int(py_list_ref(args, 4))
    freq: str = "src/wordpick/en_freq.tsv"
    if n > 5: freq = py_list_ref(args, 5)
    print(wc_import_book(py_list_ref(args, 1), py_list_ref(args, 2),
                         py_list_ref(args, 3), max_words, freq))
PY

CC="${CC:-gcc}"
$CC -O2 -fPIC -shared -I"$ROOT/src" -I"$ROOT/src/wordpick" "$ROOT/native/src/wc_import_book.c" \
  -L"$ROOT/importer/libs" -lmobiparse -lpdfparse -lepubparse \
  -L"$ROOT/src" -lwordpick -lwordcard \
  -Wl,-rpath,'$ORIGIN/../../../importer/libs:$ORIGIN/../../../src' \
  -o "$HERE/libwc_import_book.so"

sed '/^extern fn /d' "$BUILD/wc_import_book.static.py" > "$BUILD/wc_import_book.body.py"
grep -E '^extern fn wc_import_book' "$FFI" > "$BUILD/wc_import_book.ffi.py"
cat "$BUILD/wc_import_book.ffi.py" "$BUILD/wc_import_book.body.py" > "$BUILD/wc_import_book.combined.py"
bash "$BUILD_COMPILER" "$BUILD/wc_import_book.combined.py" wc_import_book >/tmp/opencode/wc_import_book_build.log 2>&1
mv -f "$STATICPY_ROOT/wc_import_book" "$HERE/wc_import_book"
mv -f "$STATICPY_ROOT/wc_import_book.so" "$HERE/wc_import_book.so"
echo "built: $HERE/wc_import_book"
