#!/bin/bash
# build.sh — 全中文内容直接渲染为卡片（StaticPy）
# 用法: wc_card_cn <title> <content.txt> <out.png>
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
BUILD="${XDG_CACHE_HOME:-$HOME/.cache}/wordcard-staticpy-card-cn"
STATICPY_ROOT="${STATICPY_ROOT:-/opt/StaticPy}"
BUILD_COMPILER="$STATICPY_ROOT/staticpy/static_build_comfycli.sh"
FFI="$ROOT/native/staticpy/ffi.static.py"
mkdir -p "$BUILD" /tmp/opencode
[ -f "$BUILD_COMPILER" ] && [ -f "$FFI" ] || { echo "missing StaticPy compiler/ffi" >&2; exit 1; }


cat > "$BUILD/wc_card_cn.static.py" <<'PY'
extern fn wc_card_cn(title: str, content: str, png: str, height: int) -> int from "wc_card_cn"
extern fn wc_card_cn_measure(title: str, content: str) -> int from "wc_card_cn"

def main():
    args = list_to_py_list(argv())
    n: int = py_list_length(args)
    if n > 1 and py_list_ref(args, 1) == "measure":
        if n < 4:
            print("usage: wc_card_cn measure <title> <content.txt>")
            exit_program(1)
        print(wc_card_cn_measure(py_list_ref(args, 2), py_list_ref(args, 3)))
        exit_program(0)
    if n < 4:
        print("usage: wc_card_cn <title> <content.txt> <out.png> [height]")
        exit_program(1)
    height: int = 0
    if n > 4: height = string_to_int(py_list_ref(args, 4))
    print(wc_card_cn(py_list_ref(args, 1), py_list_ref(args, 2),
                     py_list_ref(args, 3), height))
PY

CC="${CC:-gcc}"
$CC -O2 -fPIC -shared -I"$ROOT/src" "$ROOT/native/src/card_cn.c" \
  -L"$ROOT/src" -ltxt2png -Wl,-rpath,'$ORIGIN/../../../src' \
  -o "$HERE/libwc_card_cn.so"

sed '/^extern fn /d' "$BUILD/wc_card_cn.static.py" > "$BUILD/wc_card_cn.body.py"
grep -E '^extern fn wc_card_cn' "$FFI" > "$BUILD/wc_card_cn.ffi.py"
cat "$BUILD/wc_card_cn.ffi.py" "$BUILD/wc_card_cn.body.py" > "$BUILD/wc_card_cn.combined.py"
bash "$BUILD_COMPILER" "$BUILD/wc_card_cn.combined.py" wc_card_cn >/tmp/opencode/wc_card_cn_build.log 2>&1
mv -f "$STATICPY_ROOT/wc_card_cn" "$HERE/wc_card_cn"
mv -f "$STATICPY_ROOT/wc_card_cn.so" "$HERE/wc_card_cn.so"
echo "built: $HERE/wc_card_cn"
