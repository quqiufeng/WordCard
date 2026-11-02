#!/bin/bash
# build.sh — WordCard Markdown 导入（StaticPy 原生 POC，自包含）
# 用法:
#   bash native/staticpy/import_md/build.sh
#   LD_LIBRARY_PATH=native/staticpy/import_md:src native/staticpy/import_md/wc_import_md \
#     <page.md> <db> <tag> [max_words]
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
BUILD="${XDG_CACHE_HOME:-$HOME/.cache}/wordcard-staticpy-import-md"
STATICPY_ROOT="${STATICPY_ROOT:-/opt/StaticPy}"
BUILD_COMPILER="$STATICPY_ROOT/staticpy/static_build_comfycli.sh"
FFI="$ROOT/native/staticpy/ffi.static.py"
mkdir -p "$BUILD" /tmp/opencode
[ -f "$BUILD_COMPILER" ] && [ -f "$FFI" ] || { echo "missing StaticPy compiler/ffi" >&2; exit 1; }


cat > "$BUILD/wc_import_md.static.py" <<'PY'
extern fn wc_import_md(md: str, db: str, tag: str, max_words: int, freq: str) -> int from "wc_import_md"

def main():
    args = list_to_py_list(argv())
    n: int = py_list_length(args)
    if n < 4:
        print("usage: wc_import_md <page.md> <db> <tag> [max_words] [freq.tsv]")
        exit_program(1)
    max_words: int = 50
    if n > 4:
        max_words = string_to_int(py_list_ref(args, 4))
    freq: str = "src/wordpick/en_freq.tsv"
    if n > 5:
        freq = py_list_ref(args, 5)
    print(wc_import_md(py_list_ref(args, 1), py_list_ref(args, 2),
                       py_list_ref(args, 3), max_words, freq))
PY

CC="${CC:-gcc}"
$CC -O2 -fPIC -shared -I"$ROOT/src" -I"$ROOT/src/wordpick" "$ROOT/native/src/wc_import_md.c" \
  -L"$ROOT/src" -lwordpick -lwordcard -Wl,-rpath,'$ORIGIN/../../../src' \
  -o "$HERE/libwc_import_md.so"

sed '/^extern fn /d' "$BUILD/wc_import_md.static.py" > "$BUILD/wc_import_md.body.py"
grep -E '^extern fn wc_import_md' "$FFI" > "$BUILD/wc_import_md.ffi.py"
cat "$BUILD/wc_import_md.ffi.py" "$BUILD/wc_import_md.body.py" > "$BUILD/wc_import_md.combined.py"
bash "$BUILD_COMPILER" \
  "$BUILD/wc_import_md.combined.py" wc_import_md >/tmp/opencode/wc_import_md_build.log 2>&1
mv -f "$STATICPY_ROOT/wc_import_md" "$HERE/wc_import_md"
mv -f "$STATICPY_ROOT/wc_import_md.so" "$HERE/wc_import_md.so"

echo "built: $HERE/wc_import_md"
