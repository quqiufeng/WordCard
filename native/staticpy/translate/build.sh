#!/bin/bash
# build.sh — WordCard 翻译 StaticPy 原生 POC（自包含）
# 默认 POST 到 OpenAI 兼容接口（本地 llama / DeepSeek）
# 用法: wc_translate "text" /tmp/out.txt [url] [model]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
BUILD="${XDG_CACHE_HOME:-$HOME/.cache}/wordcard-staticpy-translate"
STATICPY_ROOT="${STATICPY_ROOT:-/opt/StaticPy}"
BUILD_COMPILER="$STATICPY_ROOT/staticpy/static_build_comfycli.sh"
FFI="$ROOT/native/staticpy/ffi.static.py"
mkdir -p "$BUILD" /tmp/opencode
[ -f "$BUILD_COMPILER" ] && [ -f "$FFI" ] || { echo "missing StaticPy compiler/ffi" >&2; exit 1; }


cat > "$BUILD/wc_translate.static.py" <<'PY'
extern fn wc_translate(text: str, out_path: str, url: str, model: str) -> int from "wc_translate"

def main():
    args = list_to_py_list(argv())
    n: int = py_list_length(args)
    if n < 3:
        print("usage: wc_translate <text> <out.txt> [url] [model]")
        exit_program(1)
    url: str = ""
    if n > 3: url = py_list_ref(args, 3)
    model: str = ""
    if n > 4: model = py_list_ref(args, 4)
    print(wc_translate(py_list_ref(args, 1), py_list_ref(args, 2), url, model))
PY

CC="${CC:-gcc}"
$CC -O2 -fPIC -shared "$ROOT/native/src/wc_translate.c" -lcurl -lcjson \
  -o "$HERE/libwc_translate.so"

sed '/^extern fn /d' "$BUILD/wc_translate.static.py" > "$BUILD/wc_translate.body.py"
grep -E '^extern fn wc_translate' "$FFI" > "$BUILD/wc_translate.ffi.py"
cat "$BUILD/wc_translate.ffi.py" "$BUILD/wc_translate.body.py" > "$BUILD/wc_translate.combined.py"
bash "$BUILD_COMPILER" "$BUILD/wc_translate.combined.py" wc_translate >/tmp/opencode/wc_translate_build.log 2>&1
mv -f "$STATICPY_ROOT/wc_translate" "$HERE/wc_translate"
mv -f "$STATICPY_ROOT/wc_translate.so" "$HERE/wc_translate.so"
echo "built: $HERE/wc_translate"
