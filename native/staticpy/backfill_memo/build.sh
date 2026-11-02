#!/bin/bash
# build.sh — WordCard 助记回填（LLM）StaticPy POC（自包含）
# 用法: wc_backfill_memo <db> [limit] [url] [model]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
BUILD="${XDG_CACHE_HOME:-$HOME/.cache}/wordcard-staticpy-backfill-memo"
STATICPY_ROOT="${STATICPY_ROOT:-/opt/StaticPy}"
BUILD_COMPILER="$STATICPY_ROOT/staticpy/static_build_comfycli.sh"
FFI="$ROOT/native/staticpy/ffi.static.py"
mkdir -p "$BUILD" /tmp/opencode
[ -f "$BUILD_COMPILER" ] && [ -f "$FFI" ] || { echo "missing StaticPy compiler/ffi" >&2; exit 1; }

cat > "$BUILD/wc_backfill_memo.c" <<'C'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "wordcard.h"

int wc_translate(const char *text, const char *out_path, const char *url, const char *model);

int wc_backfill_memo(const char *db_path, int limit, const char *url, const char *model) {
    wordcard_db_t *db = wc_load_db(db_path);
    if (!db) return -1;
    size_t n = wc_item_count(db);
    int done = 0;
    for (size_t i = 0; i < n; i++) {
        item_entry_t *it = wc_find_item_by_id(db, wc_item_id_at(db, i));
        if (!it) continue;
        if (strncmp(it->explanation, "【用法】", strlen("【用法】")) == 0) continue;
        char prompt[2048];
        snprintf(prompt, sizeof(prompt),
                 "用中文为英语单词“%s”写一句简短的用法/场景助记，只输出助记，不要解释。词义：%s。上下文：%.200s",
                 it->question, it->answer, it->explanation);
        char tmp[256] = "/tmp/opencode/wc_memo.txt";
        if (wc_translate(prompt, tmp, url, model) != 0) continue;
        FILE *f = fopen(tmp, "r");
        if (!f) continue;
        char memo[1024] = {0}; size_t r = fread(memo, 1, sizeof(memo)-1, f); fclose(f);
        memo[r] = 0;
        while (r && (memo[r-1]=='\n'||memo[r-1]=='\r'||memo[r-1]==' ')) memo[--r] = 0;
        if (!memo[0]) continue;
        char neu[2048];
        snprintf(neu, sizeof(neu), "【用法】%s\n%s", memo, it->explanation);
        if (wc_update_item_explanation(db, it->id, neu) == 0) done++;
        if (limit > 0 && done >= limit) break;
    }
    wc_save_db(db, db_path);
    wc_db_free(db);
    return done;
}
C

cat > "$BUILD/wc_backfill_memo.static.py" <<'PY'
extern fn wc_backfill_memo(db: str, limit: int, url: str, model: str) -> int from "wc_backfill_memo"

def main():
    args = list_to_py_list(argv())
    n: int = py_list_length(args)
    if n < 2:
        print("usage: wc_backfill_memo <db> [limit] [url] [model]")
        exit_program(1)
    limit: int = 0
    if n > 2: limit = string_to_int(py_list_ref(args, 2))
    url: str = ""
    if n > 3: url = py_list_ref(args, 3)
    model: str = ""
    if n > 4: model = py_list_ref(args, 4)
    print(wc_backfill_memo(py_list_ref(args, 1), limit, url, model))
PY

CC="${CC:-gcc}"
$CC -O2 -fPIC -shared -I"$ROOT/src" "$BUILD/wc_backfill_memo.c" \
  -L"$ROOT/src" -lwordcard -L"$ROOT/native/staticpy/translate" -lwc_translate -lcurl -lcjson \
  -Wl,-rpath,'$ORIGIN/../../../src:$ORIGIN/../translate' \
  -o "$HERE/libwc_backfill_memo.so"

sed '/^extern fn /d' "$BUILD/wc_backfill_memo.static.py" > "$BUILD/wc_backfill_memo.body.py"
grep -E '^extern fn wc_backfill_memo' "$FFI" > "$BUILD/wc_backfill_memo.ffi.py"
cat "$BUILD/wc_backfill_memo.ffi.py" "$BUILD/wc_backfill_memo.body.py" > "$BUILD/wc_backfill_memo.combined.py"
bash "$BUILD_COMPILER" "$BUILD/wc_backfill_memo.combined.py" wc_backfill_memo >/tmp/opencode/wc_backfill_memo_build.log 2>&1
mv -f "$STATICPY_ROOT/wc_backfill_memo" "$HERE/wc_backfill_memo"
mv -f "$STATICPY_ROOT/wc_backfill_memo.so" "$HERE/wc_backfill_memo.so"
echo "built: $HERE/wc_backfill_memo"
