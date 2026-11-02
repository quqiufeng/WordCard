#!/bin/bash
# build.sh — WordCard 选词 + 卡片渲染 StaticPy 原生版（自包含）
# 本地只保留本脚本；C/StaticPy 源码在构建时生成到 ~/.cache。
#
# 用法:
#   bash native/staticpy/text/build.sh          # -> native/staticpy/text/wc_text
#   bash native/staticpy/text/build.sh --run    # 编译并跑选词 + 渲染
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
BUILD="${XDG_CACHE_HOME:-$HOME/.cache}/wordcard-staticpy-text"
STATICPY_ROOT="${STATICPY_ROOT:-/opt/StaticPy}"
BUILD_COMPILER="$STATICPY_ROOT/staticpy/static_build_comfycli.sh"
FFI="$ROOT/native/staticpy/ffi.static.py"
mkdir -p "$BUILD" /tmp/opencode
[ -f "$BUILD_COMPILER" ] && [ -f "$FFI" ] || { echo "missing StaticPy compiler: $BUILD_COMPILER" >&2; exit 1; }


cat > "$BUILD/wc_text.static.py" <<'PY'
extern fn wc_wordpick_tsv(freq: str, text: str, out: str, max_words: int) -> int from "wc_text_static"
extern fn wc_wordpick_tsv_file(freq: str, text_path: str, out: str, max_words: int) -> int from "wc_text_static"
extern fn wc_render_png(text: str, font: str, out: str) -> int from "wc_text_static"

def main():
    args = list_to_py_list(argv())
    n: int = py_list_length(args)
    if n > 1 and py_list_ref(args, 1) == "--file":
        if n < 5:
            print("usage: wc_text --file <freq.tsv> <text.txt> <out.tsv> [max_words]")
            exit_program(1)
        max_words: int = 10
        if n > 5: max_words = string_to_int(py_list_ref(args, 5))
        print(wc_wordpick_tsv_file(py_list_ref(args, 2), py_list_ref(args, 3),
                                   py_list_ref(args, 4), max_words))
        exit_program(0)
    if n < 4:
        print("usage: wc_text <freq.tsv> <text> <out.tsv> [max_words]")
        exit_program(1)
    max_words: int = 10
    if n > 4: max_words = string_to_int(py_list_ref(args, 4))
    print(wc_wordpick_tsv(py_list_ref(args, 1), py_list_ref(args, 2),
                          py_list_ref(args, 3), max_words))
PY

CC="${CC:-gcc}"
$CC -O2 -fPIC -shared -I"$ROOT/src" -I"$ROOT/src/wordpick" -I"$ROOT/src/txt2png" "$ROOT/native/src/wc_text_static.c" \
  -L"$ROOT/src" -lwordpick -ltxt2png -Wl,-rpath,'$ORIGIN/../../../src' \
  -o "$HERE/libwc_text_static.so"

sed '/^extern fn /d' "$BUILD/wc_text.static.py" > "$BUILD/wc_text.body.py"
grep -E '^extern fn (wc_wordpick_tsv|wc_render_png)' "$FFI" > "$BUILD/wc_text.ffi.py"
cat "$BUILD/wc_text.ffi.py" "$BUILD/wc_text.body.py" > "$BUILD/wc_text.combined.py"
bash "$BUILD_COMPILER" \
  "$BUILD/wc_text.combined.py" wc_text >/tmp/opencode/wc_text_build.log 2>&1
mv -f "$STATICPY_ROOT/wc_text" "$HERE/wc_text"
mv -f "$STATICPY_ROOT/wc_text.so" "$HERE/wc_text.so"

echo "built: $HERE/wc_text"
if [ "${1:-}" = "--run" ]; then
  cd "$ROOT"
  LD_LIBRARY_PATH="$HERE:$ROOT/src" "$HERE/wc_text"
fi
