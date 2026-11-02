#!/bin/bash
# build.sh — WordCard Markdown 导入（StaticPy 原生 POC，自包含）
# 用法:
#   bash native/staticpy/import_md/build.sh
#   LD_LIBRARY_PATH=native/staticpy/import_md:src native/staticpy/import_md/wc_import_md \
#     <page.md> <db> <tag> [max_words]
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
BUILD="${XDG_CACHE_HOME:-$HOME/.cache}/wordcard-staticpy-import-md"
STATICPY_ROOT="${STATICPY_ROOT:-/opt/StaticPy}"
BUILD_COMPILER="$STATICPY_ROOT/staticpy/static_build_comfycli.sh"
FFI="$ROOT/native/staticpy/ffi.static.py"
mkdir -p "$BUILD" /tmp/opencode
[ -f "$BUILD_COMPILER" ] && [ -f "$FFI" ] || { echo "missing StaticPy compiler/ffi" >&2; exit 1; }

cat > "$BUILD/wc_import_md.c" <<'C'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include "wordcard.h"
#include "wordpick.h"

static char *read_all(const char *path) {
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
    if (n < 0 || n > 8 * 1024 * 1024) { fclose(f); return NULL; }
    char *b = (char *)malloc((size_t)n + 1);
    if (!b) { fclose(f); return NULL; }
    size_t r = fread(b, 1, (size_t)n, f); b[r] = 0; fclose(f);
    return b;
}

static char *clean_md(const char *in) {
    size_t n = strlen(in);
    char *out = (char *)malloc(n + 1);
    if (!out) return NULL;
    size_t j = 0; int fence = 0;
    const char *p = in;
    while (*p) {
        const char *e = strchr(p, '\n');
        size_t len = e ? (size_t)(e - p) : strlen(p);
        char line[4096];
        if (len >= sizeof(line)) len = sizeof(line) - 1;
        memcpy(line, p, len); line[len] = 0;
        if (strncmp(line, "```", 3) == 0) { fence = !fence; }
        else if (!fence) {
            char *s = line;
            while (*s == '#' || *s == '>' || *s == '-' || *s == '*' || *s == ' ' || *s == '\t') s++;
            for (char *q = s; *q; q++) {
                if (*q == '*' || *q == '`' || *q == '_' || *q == '~') *q = ' ';
            }
            size_t l = strlen(s);
            if (l) { memcpy(out + j, s, l); j += l; out[j++] = '\n'; }
        }
        if (!e) break;
        p = e + 1;
    }
    out[j] = 0;
    return out;
}

int wc_import_md(const char *md, const char *db_path, const char *tag,
                 int max_words, const char *freq) {
    char *raw = read_all(md);
    if (!raw) return -1;
    char *text = clean_md(raw);
    free(raw);
    if (!text) return -2;
    if (max_words <= 0) max_words = 50;
    if (max_words > 500) max_words = 500;

    void *wp = wp_create(freq);
    if (!wp) { free(text); return -3; }
    wp_config_t cfg;
    memset(&cfg, 0, sizeof(cfg));
    cfg.max_words = max_words;
    cfg.target_zipf = 3.8f;
    cfg.min_len = 5;
    cfg.mode = 0;
    cfg.level = 0;
    cfg.known_zipf = 5.0f;
    cfg.coverage_weight = 0.5f;
    wp_word_t words[512];
    int n = wp_select_ex(wp, text, &cfg, words, max_words);
    wp_destroy(wp);
    free(text);
    if (n < 0) return -4;

    wordcard_db_t *db = wc_load_db(db_path);
    if (!db) db = wc_db_init();
    if (!db) return -5;
    int added = 0;
    for (int i = 0; i < n; i++) {
        if (wc_find_item_by_question(db, words[i].word)) continue;
        item_entry_t e;
        memset(&e, 0, sizeof(e));
        size_t qn = strnlen(words[i].word, sizeof(words[i].word));
        if (qn >= sizeof(e.question)) qn = sizeof(e.question) - 1;
        memcpy(e.question, words[i].word, qn); e.question[qn] = 0;
        e.answer[0] = 0;
        snprintf(e.explanation, sizeof(e.explanation), "%s", words[i].context);
        snprintf(e.hint, sizeof(e.hint), "CEFR %d", words[i].level);
        snprintf(e.tags, sizeof(e.tags), "%s", tag ? tag : "book:untitled");
        e.category = CAT_ENGLISH_VOCAB;
        if (wc_add_item(db, &e)) added++;
    }
    wc_save_db(db, db_path);
    wc_db_free(db);
    return added;
}
C

cat > "$BUILD/wc_import_md.static.py" <<'PY'
extern fn wc_import_md(md: str, db: str, tag: str, max_words: int, freq: str) -> int from "wc_import_md"

def main():
    args = list_to_py_list(argv())
    n: int = py_list_length(args)
    if n < 4:
        print("usage: wc_import_md <page.md> <db> <tag> [max_words] [freq.tsv]")
        exit_program(1)
    max_words: int = 50
    if n > 4:
        max_words = string_to_int(py_list_ref(args, 4))
    freq: str = "src/wordpick/en_freq.tsv"
    if n > 5:
        freq = py_list_ref(args, 5)
    print(wc_import_md(py_list_ref(args, 1), py_list_ref(args, 2),
                       py_list_ref(args, 3), max_words, freq))
PY

CC="${CC:-gcc}"
$CC -O2 -fPIC -shared -I"$ROOT/src" -I"$ROOT/src/wordpick" "$BUILD/wc_import_md.c" \
  -L"$ROOT/src" -lwordpick -lwordcard -Wl,-rpath,'$ORIGIN/../../../src' \
  -o "$HERE/libwc_import_md.so"

sed '/^extern fn /d' "$BUILD/wc_import_md.static.py" > "$BUILD/wc_import_md.body.py"
grep -E '^extern fn wc_import_md' "$FFI" > "$BUILD/wc_import_md.ffi.py"
cat "$BUILD/wc_import_md.ffi.py" "$BUILD/wc_import_md.body.py" > "$BUILD/wc_import_md.combined.py"
bash "$BUILD_COMPILER" \
  "$BUILD/wc_import_md.combined.py" wc_import_md >/tmp/opencode/wc_import_md_build.log 2>&1
mv -f "$STATICPY_ROOT/wc_import_md" "$HERE/wc_import_md"
mv -f "$STATICPY_ROOT/wc_import_md.so" "$HERE/wc_import_md.so"

echo "built: $HERE/wc_import_md"
