#!/bin/bash
# build.sh — 从 ECDICT 生成考试词表（StaticPy 原生）
# 用法: wc_build_wordlists [--refresh] [cet4 cet6 ky toefl ielts gre gk]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
BUILD="${XDG_CACHE_HOME:-$HOME/.cache}/wordcard-staticpy-wordlists"
STATICPY_ROOT="${STATICPY_ROOT:-/opt/StaticPy}"
BUILD_COMPILER="$STATICPY_ROOT/staticpy/static_build_comfycli.sh"
FFI="$ROOT/native/staticpy/ffi.static.py"
mkdir -p "$BUILD" /tmp/opencode
[ -f "$BUILD_COMPILER" ] && [ -f "$FFI" ] || { echo "missing StaticPy compiler/ffi" >&2; exit 1; }


cat > "$BUILD/wc_build_wordlists.static.py" <<'PY'
extern fn wc_build_wordlists(cache: str, out: str, mask: int, refresh: int) -> int from "wc_build_wordlists"

def main():
    args = list_to_py_list(argv())
    n: int = py_list_length(args)
    mask: int = 0
    refresh: int = 0
    i: int = 1
    while i < n:
        a: str = py_list_ref(args, i)
        if a == "--refresh": refresh = 1
        elif a == "cet4": mask = mask + 1
        elif a == "cet6": mask = mask + 2
        elif a == "ky": mask = mask + 4
        elif a == "toefl": mask = mask + 8
        elif a == "ielts": mask = mask + 16
        elif a == "gre": mask = mask + 32
        elif a == "gk": mask = mask + 64
        else:
            print("未知词表: " + a)
            exit_program(1)
        i += 1
    print(wc_build_wordlists("", "data/wordlists", mask, refresh))
PY

CC="${CC:-gcc}"
$CC -O2 -fPIC -shared "$ROOT/native/src/wc_build_wordlists.c" -lcurl -lcjson \
  -o "$HERE/libwc_build_wordlists.so"

sed '/^extern fn /d' "$BUILD/wc_build_wordlists.static.py" > "$BUILD/wc_build_wordlists.body.py"
grep -E '^extern fn wc_build_wordlists' "$FFI" > "$BUILD/wc_build_wordlists.ffi.py"
cat "$BUILD/wc_build_wordlists.ffi.py" "$BUILD/wc_build_wordlists.body.py" > "$BUILD/wc_build_wordlists.combined.py"
bash "$BUILD_COMPILER" "$BUILD/wc_build_wordlists.combined.py" wc_build_wordlists >/tmp/opencode/wc_build_wordlists_build.log 2>&1
mv -f "$STATICPY_ROOT/wc_build_wordlists" "$HERE/wc_build_wordlists"
mv -f "$STATICPY_ROOT/wc_build_wordlists.so" "$HERE/wc_build_wordlists.so"
echo "built: $HERE/wc_build_wordlists"
