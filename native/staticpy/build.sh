#!/bin/bash
# build.sh — WordCard StaticPy 原生 CLI（自包含）
# 只保留本脚本；C helper / StaticPy 源码在构建时生成到 ~/.cache。
#
# 用法:
#   bash native/staticpy/build.sh          # 编译 -> native/staticpy/wc_native
#   bash native/staticpy/build.sh --run    # 编译并运行
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
BUILD="${XDG_CACHE_HOME:-$HOME/.cache}/wordcard-staticpy"
STATICPY_ROOT="${STATICPY_ROOT:-/opt/StaticPy}"
BUILD_COMPILER="$STATICPY_ROOT/staticpy/static_build_comfycli.sh"
FFI="$ROOT/native/staticpy/ffi.static.py"
mkdir -p "$BUILD" /tmp/opencode
[ -f "$BUILD_COMPILER" ] && [ -f "$FFI" ] || { echo "missing StaticPy compiler: $BUILD_COMPILER" >&2; exit 1; }
if [ "${WC_REBUILD_CORE:-0}" = "1" ]; then make -C "$ROOT/src" wordcard >/dev/null; fi


cat > "$BUILD/wc_native.static.py" <<'PY'
extern fn wc_static_version() -> str from "wc_static"
extern fn wc_static_summary(db_path: str) -> str from "wc_static"
extern fn wc_static_dump(db_path: str, out_path: str) -> int from "wc_static"

def main():
    print(wc_static_version())
    print(wc_static_summary("data/wordcard.db"))
    n = wc_static_dump("data/wordcard.db", "/tmp/opencode/wc_static_dump.tsv")
    print(n)
PY

CC="${CC:-gcc}"
$CC -O2 -fPIC -shared -I"$ROOT/src" "$ROOT/native/src/wc_static.c" \
  -L"$ROOT/src" -lwordcard -Wl,-rpath,'$ORIGIN/../../src' \
  -o "$HERE/libwc_static.so"

sed '/^extern fn /d' "$BUILD/wc_native.static.py" > "$BUILD/wc_native.body.py"
grep -E '^extern fn wc_static_' "$FFI" > "$BUILD/wc_native.ffi.py"
cat "$BUILD/wc_native.ffi.py" "$BUILD/wc_native.body.py" > "$BUILD/wc_native.combined.py"
bash "$BUILD_COMPILER" \
  "$BUILD/wc_native.combined.py" wc_native >/tmp/opencode/wc_static_build.log 2>&1
mv -f "$STATICPY_ROOT/wc_native" "$HERE/wc_native"
mv -f "$STATICPY_ROOT/wc_native.so" "$HERE/wc_native.so"

echo "built: $HERE/wc_native"

# 其余 StaticPy 脚本共用 ffi.static.py，一次编译全部
for sub in voice capture text card card_txt card_cn import_md import_wordlist import_book ebook_json ebook_text translate define ocr wordlists backfill backfill_memo vocab_card cli; do
  if [ -f "$HERE/$sub/build.sh" ]; then
    bash "$HERE/$sub/build.sh"
  fi
done

if [ "${1:-}" = "--run" ]; then
  cd "$ROOT"
  LD_LIBRARY_PATH="$HERE:$ROOT/src" "$HERE/wc_native"
fi
