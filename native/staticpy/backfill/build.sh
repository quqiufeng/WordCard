#!/bin/bash
# build.sh — WordCard 释义回填 StaticPy 原生 POC（自包含）
# 用法: wc_backfill <db> <dict.tsv>
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
BUILD="${XDG_CACHE_HOME:-$HOME/.cache}/wordcard-staticpy-backfill"
STATICPY_ROOT="${STATICPY_ROOT:-/opt/StaticPy}"
BUILD_COMPILER="$STATICPY_ROOT/staticpy/static_build_comfycli.sh"
FFI="$ROOT/native/staticpy/ffi.static.py"
mkdir -p "$BUILD" /tmp/opencode
[ -f "$BUILD_COMPILER" ] && [ -f "$FFI" ] || { echo "missing StaticPy compiler/ffi" >&2; exit 1; }

cat > "$BUILD/wc_backfill.c" <<'C'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "wordcard.h"

static char *field(char *s, char sep, char **rest) {
    char *p = strchr(s, sep);
    if (p) { *p = 0; *rest = p + 1; } else *rest = NULL;
    return s;
}

int wc_backfill(const char *db_path, const char *dict) {
    FILE *f = fopen(dict, "r");
    if (!f) return -1;
    wordcard_db_t *db = wc_load_db(db_path);
    if (!db) { fclose(f); return -2; }
    char line[4096];
    int updated = 0;
    while (fgets(line, sizeof(line), f)) {
        size_t n = strlen(line);
        while (n && (line[n-1] == '\n' || line[n-1] == '\r')) line[--n] = 0;
        if (!line[0]) continue;
        char *rest1, *rest2, *rest3, *rest4;
        char *word = field(line, '\t', &rest1);
        if (!rest1) continue;
        char *ph = field(rest1, '\t', &rest2);
        if (!rest2) continue;
        char *pos = field(rest2, '\t', &rest3);
        if (!rest3) continue;
        char *tr = field(rest3, '\t', &rest4);
        if (!word[0] || !tr[0]) continue;
        item_entry_t *it = wc_find_item_by_question(db, word);
        if (!it || it->answer[0]) continue;
        char answer[512];
        if (pos[0]) snprintf(answer, sizeof(answer), "[%s] %s", pos, tr);
        else snprintf(answer, sizeof(answer), "%s", tr);
        if (wc_update_item_answer(db, it->id, answer) == 0) {
            if (!it->hint[0]) snprintf(it->hint, sizeof(it->hint), "%s", ph);
            updated++;
        }
    }
    fclose(f);
    wc_save_db(db, db_path);
    wc_db_free(db);
    return updated;
}
C

cat > "$BUILD/wc_backfill.static.py" <<'PY'
extern fn wc_backfill(db: str, dict: str) -> int from "wc_backfill"

def main():
    args = list_to_py_list(argv())
    if py_list_length(args) < 3:
        print("usage: wc_backfill <db> <dict.tsv>")
        exit_program(1)
    print(wc_backfill(py_list_ref(args, 1), py_list_ref(args, 2)))
PY

CC="${CC:-gcc}"
$CC -O2 -fPIC -shared -I"$ROOT/src" "$BUILD/wc_backfill.c" \
  -L"$ROOT/src" -lwordcard -Wl,-rpath,'$ORIGIN/../../../src' \
  -o "$HERE/libwc_backfill.so"

sed '/^extern fn /d' "$BUILD/wc_backfill.static.py" > "$BUILD/wc_backfill.body.py"
grep -E '^extern fn wc_backfill' "$FFI" > "$BUILD/wc_backfill.ffi.py"
cat "$BUILD/wc_backfill.ffi.py" "$BUILD/wc_backfill.body.py" > "$BUILD/wc_backfill.combined.py"
bash "$BUILD_COMPILER" "$BUILD/wc_backfill.combined.py" wc_backfill >/tmp/opencode/wc_backfill_build.log 2>&1
mv -f "$STATICPY_ROOT/wc_backfill" "$HERE/wc_backfill"
mv -f "$STATICPY_ROOT/wc_backfill.so" "$HERE/wc_backfill.so"
echo "built: $HERE/wc_backfill"
