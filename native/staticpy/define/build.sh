#!/bin/bash
# build.sh — WordCard 查词 StaticPy 原生 POC（自包含）
# 用法: bash native/staticpy/define/build.sh
#       wc_define abandon orbit --dict data/wordlists/cet4.tsv
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
BUILD="${XDG_CACHE_HOME:-$HOME/.cache}/wordcard-staticpy-define"
STATICPY_ROOT="${STATICPY_ROOT:-/opt/StaticPy}"
BUILD_COMPILER="$STATICPY_ROOT/staticpy/static_build_comfycli.sh"
FFI="$ROOT/native/staticpy/ffi.static.py"
mkdir -p "$BUILD" /tmp/opencode
[ -f "$BUILD_COMPILER" ] && [ -f "$FFI" ] || { echo "missing StaticPy compiler/ffi" >&2; exit 1; }


cat > "$BUILD/wc_define.static.py" <<'PY'
extern fn wc_define_word(word: str, dict: str, url: str, model: str) -> str from "wc_define"

def main():
    args = list_to_py_list(argv())
    n: int = py_list_length(args)
    if n < 2:
        print("usage: wc_define <word> [word...] [--dict path] [--url url] [--model name]")
        exit_program(1)
    dict: str = "data/wordlists/cet4.tsv"
    url: str = ""
    model: str = ""
    words = py_list()
    i: int = 1
    while i < n:
        a: str = py_list_ref(args, i)
        if a == "--dict" and i + 1 < n:
            dict = py_list_ref(args, i + 1); i += 2
        elif a == "--url" and i + 1 < n:
            url = py_list_ref(args, i + 1); i += 2
        elif a == "--model" and i + 1 < n:
            model = py_list_ref(args, i + 1); i += 2
        else:
            words = py_list_append(words, a); i += 1
    i = 0
    while i < py_list_length(words):
        print(wc_define_word(py_list_ref(words, i), dict, url, model))
        i += 1
PY

CC="${CC:-gcc}"
$CC -O2 -fPIC -shared "$ROOT/native/src/wc_define.c" \
  -L"$ROOT/native/staticpy/translate" -lwc_translate -lcurl -lcjson \
  -Wl,-rpath,'$ORIGIN/../translate' -o "$HERE/libwc_define.so"

sed '/^extern fn /d' "$BUILD/wc_define.static.py" > "$BUILD/wc_define.body.py"
grep -E '^extern fn wc_define_' "$FFI" > "$BUILD/wc_define.ffi.py"
cat "$BUILD/wc_define.ffi.py" "$BUILD/wc_define.body.py" > "$BUILD/wc_define.combined.py"
bash "$BUILD_COMPILER" "$BUILD/wc_define.combined.py" wc_define >/tmp/opencode/wc_define_build.log 2>&1
mv -f "$STATICPY_ROOT/wc_define" "$HERE/wc_define"
mv -f "$STATICPY_ROOT/wc_define.so" "$HERE/wc_define.so"
echo "built: $HERE/wc_define"
