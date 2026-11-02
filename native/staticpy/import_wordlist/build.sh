#!/bin/bash
# build.sh — WordCard 考试词表导入（StaticPy 原生 POC，自包含）
# 用法: wc_import_wordlist <wordlist.tsv> <db> <name> [limit]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
BUILD="${XDG_CACHE_HOME:-$HOME/.cache}/wordcard-staticpy-import-wordlist"
STATICPY_ROOT="${STATICPY_ROOT:-/opt/StaticPy}"
BUILD_COMPILER="$STATICPY_ROOT/staticpy/static_build_comfycli.sh"
FFI="$ROOT/native/staticpy/ffi.static.py"
mkdir -p "$BUILD" /tmp/opencode
[ -f "$BUILD_COMPILER" ] && [ -f "$FFI" ] || { echo "missing StaticPy compiler/ffi" >&2; exit 1; }

cat > "$BUILD/wc_import_wordlist.c" <<'C'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "wordcard.h"

static char *field(char *s, char sep, char **rest) {
    char *p = strchr(s, sep);
    if (p) { *p = 0; *rest = p + 1; }
    else *rest = NULL;
    return s;
}

int wc_import_wordlist(const char *tsv, const char *db_path, const char *name, int limit) {
    FILE *f = fopen(tsv, "r");
    if (!f) return -1;
    wordcard_db_t *db = wc_load_db(db_path);
    if (!db) db = wc_db_init();
    if (!db) { fclose(f); return -2; }
    char line[4096];
    int added = 0, seen = 0;
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
        if (!word[0]) continue;
        if (limit > 0 && seen >= limit) break;
        seen++;
        if (wc_find_item_by_question(db, word)) continue;
        item_entry_t e;
        memset(&e, 0, sizeof(e));
        size_t wn = strlen(word); if (wn >= sizeof(e.question)) wn = sizeof(e.question) - 1;
        memcpy(e.question, word, wn); e.question[wn] = 0;
        if (pos[0]) snprintf(e.answer, sizeof(e.answer), "[%s] %s", pos, tr);
        else snprintf(e.answer, sizeof(e.answer), "%s", tr);
        snprintf(e.hint, sizeof(e.hint), "%s", ph);
        snprintf(e.tags, sizeof(e.tags), "dict:%s", name ? name : "unknown");
        e.category = CAT_ENGLISH_VOCAB;
        if (wc_add_item(db, &e)) added++;
    }
    fclose(f);
    wc_save_db(db, db_path);
    wc_db_free(db);
    return added;
}
C

cat > "$BUILD/wc_import_wordlist.static.py" <<'PY'
extern fn wc_import_wordlist(tsv: str, db: str, name: str, limit: int) -> int from "wc_import_wordlist"

def main():
    args = list_to_py_list(argv())
    n: int = py_list_length(args)
    if n < 4:
        print("usage: wc_import_wordlist <tsv> <db> <name> [limit]")
        exit_program(1)
    limit: int = 0
    if n > 4:
        limit = string_to_int(py_list_ref(args, 4))
    print(wc_import_wordlist(py_list_ref(args, 1), py_list_ref(args, 2),
                             py_list_ref(args, 3), limit))
PY

CC="${CC:-gcc}"
$CC -O2 -fPIC -shared -I"$ROOT/src" "$BUILD/wc_import_wordlist.c" \
  -L"$ROOT/src" -lwordcard -Wl,-rpath,'$ORIGIN/../../../src' \
  -o "$HERE/libwc_import_wordlist.so"

sed '/^extern fn /d' "$BUILD/wc_import_wordlist.static.py" > "$BUILD/wc_import_wordlist.body.py"
grep -E '^extern fn wc_import_wordlist' "$FFI" > "$BUILD/wc_import_wordlist.ffi.py"
cat "$BUILD/wc_import_wordlist.ffi.py" "$BUILD/wc_import_wordlist.body.py" > "$BUILD/wc_import_wordlist.combined.py"
bash "$BUILD_COMPILER" "$BUILD/wc_import_wordlist.combined.py" wc_import_wordlist >/tmp/opencode/wc_import_wordlist_build.log 2>&1
mv -f "$STATICPY_ROOT/wc_import_wordlist" "$HERE/wc_import_wordlist"
mv -f "$STATICPY_ROOT/wc_import_wordlist.so" "$HERE/wc_import_wordlist.so"
echo "built: $HERE/wc_import_wordlist"
