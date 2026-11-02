#!/bin/bash
# build.sh — WordCard 单词卡（vocab_card）StaticPy POC（自包含）
# 用法: wc_vocab_card <book> <outdir> [max_words] [dict.tsv]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
BUILD="${XDG_CACHE_HOME:-$HOME/.cache}/wordcard-staticpy-vocab-card"
STATICPY_ROOT="${STATICPY_ROOT:-/opt/StaticPy}"
BUILD_COMPILER="$STATICPY_ROOT/staticpy/static_build_comfycli.sh"
FFI="$ROOT/native/staticpy/ffi.static.py"
mkdir -p "$BUILD" /tmp/opencode
[ -f "$BUILD_COMPILER" ] && [ -f "$FFI" ] || { echo "missing StaticPy compiler/ffi" >&2; exit 1; }


cat > "$BUILD/wc_vocab_card.static.py" <<'PY'
extern fn wc_vocab_card(book: str, outdir: str, max_words: int, dict: str) -> int from "wc_vocab_card"

def main():
    args = list_to_py_list(argv())
    n: int = py_list_length(args)
    if n < 3:
        print("usage: wc_vocab_card <book> <outdir> [max_words] [dict.tsv]")
        exit_program(1)
    max_words: int = 10
    if n > 3: max_words = string_to_int(py_list_ref(args, 3))
    dict: str = "data/wordlists/cet4.tsv"
    if n > 4: dict = py_list_ref(args, 4)
    print(wc_vocab_card(py_list_ref(args, 1), py_list_ref(args, 2), max_words, dict))
PY

CC="${CC:-gcc}"
$CC -O2 -fPIC -shared -I"$ROOT/src" -I"$ROOT/src/wordpick" "$ROOT/native/src/wc_vocab_card.c" \
  -L"$ROOT/importer/libs" -lmobiparse -lpdfparse -lepubparse \
  -L"$ROOT/src" -lwordpick -ltxt2png \
  -Wl,-rpath,'$ORIGIN/../../../importer/libs:$ORIGIN/../../../src' \
  -o "$HERE/libwc_vocab_card.so"

sed '/^extern fn /d' "$BUILD/wc_vocab_card.static.py" > "$BUILD/wc_vocab_card.body.py"
grep -E '^extern fn wc_vocab_card' "$FFI" > "$BUILD/wc_vocab_card.ffi.py"
cat "$BUILD/wc_vocab_card.ffi.py" "$BUILD/wc_vocab_card.body.py" > "$BUILD/wc_vocab_card.combined.py"
bash "$BUILD_COMPILER" "$BUILD/wc_vocab_card.combined.py" wc_vocab_card >/tmp/opencode/wc_vocab_card_build.log 2>&1
mv -f "$STATICPY_ROOT/wc_vocab_card" "$HERE/wc_vocab_card"
mv -f "$STATICPY_ROOT/wc_vocab_card.so" "$HERE/wc_vocab_card.so"
echo "built: $HERE/wc_vocab_card"
