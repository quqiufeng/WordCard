#!/bin/bash
# build.sh — 本地电子书全文提取（MOBI/AZW3/PDF/EPUB/TXT）
# 用法: wc_ebook_text <book> <out.txt>
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
CC="${CC:-gcc}"

$CC -O2 -I"$ROOT/importer/libs" "$ROOT/native/src/ebook_text.c" \
  -L"$ROOT/importer/libs" -lmobiparse -lpdfparse -lepubparse \
  -Wl,-rpath,'$ORIGIN/../../../importer/libs' \
  -o "$HERE/wc_ebook_text"

echo "built: $HERE/wc_ebook_text"
