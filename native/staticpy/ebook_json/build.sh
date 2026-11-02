#!/bin/bash
# build.sh — 电子书解析为 App 可直接消费的 JSON（StaticPy）
# 用法: wc_ebook_json <book> <out.json> [max_words] [dict.tsv] [freq.tsv]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
BUILD="${XDG_CACHE_HOME:-$HOME/.cache}/wordcard-staticpy-ebook-json"
STATICPY_ROOT="${STATICPY_ROOT:-/opt/StaticPy}"
BUILD_COMPILER="$STATICPY_ROOT/staticpy/static_build_comfycli.sh"
FFI="$ROOT/native/staticpy/ffi.static.py"
mkdir -p "$BUILD" /tmp/opencode
[ -f "$BUILD_COMPILER" ] && [ -f "$FFI" ] || { echo "missing StaticPy compiler/ffi" >&2; exit 1; }


cat > "$BUILD/wc_ebook_json.static.py" <<'PY'
extern fn wc_ebook_json(path: str, out: str, max_words: int, dict: str, freq: str) -> int from "wc_ebook_json"

def main():
    args = list_to_py_list(argv())
    n: int = py_list_length(args)
    if n < 3:
        print("usage: wc_ebook_json <book> <out.json> [max_words] [dict.tsv] [freq.tsv]")
        exit_program(1)
    max_words: int = 200
    if n > 3: max_words = string_to_int(py_list_ref(args, 3))
    dict: str = "data/wordlists/cet4.tsv"
    if n > 4: dict = py_list_ref(args, 4)
    freq: str = "src/wordpick/en_freq.tsv"
    if n > 5: freq = py_list_ref(args, 5)
    print(wc_ebook_json(py_list_ref(args, 1), py_list_ref(args, 2),
                        max_words, dict, freq))
PY

CC="${CC:-gcc}"
$CC -O2 -fPIC -shared -I"$ROOT/src" -I"$ROOT/src/wordpick" \
  "$ROOT/native/src/wc_ebook_json.c" \
  -L"$ROOT/importer/libs" -lmobiparse -lpdfparse -lepubparse \
  -L"$ROOT/src" -lwordpick -lcjson \
  -Wl,-rpath,'$ORIGIN/../../../importer/libs:$ORIGIN/../../../src' \
  -o "$HERE/libwc_ebook_json.so"

sed '/^extern fn /d' "$BUILD/wc_ebook_json.static.py" > "$BUILD/wc_ebook_json.body.py"
grep -E '^extern fn wc_ebook_json' "$FFI" > "$BUILD/wc_ebook_json.ffi.py"
cat "$BUILD/wc_ebook_json.ffi.py" "$BUILD/wc_ebook_json.body.py" > "$BUILD/wc_ebook_json.combined.py"
bash "$BUILD_COMPILER" "$BUILD/wc_ebook_json.combined.py" wc_ebook_json >/tmp/opencode/wc_ebook_json_build.log 2>&1
mv -f "$STATICPY_ROOT/wc_ebook_json" "$HERE/wc_ebook_json"
mv -f "$STATICPY_ROOT/wc_ebook_json.so" "$HERE/wc_ebook_json.so"
echo "built: $HERE/wc_ebook_json"
