#!/bin/bash
# build.sh — WordCard 原生 CLI（StaticPy，自包含）
# 本地只保留本脚本；C/StaticPy 源码在构建时生成到 ~/.cache。
#
# 用法:
#   bash native/staticpy/cli/build.sh
#   LD_LIBRARY_PATH=native/staticpy/cli:src native/staticpy/cli/wc_cli stats
#   ... wc_cli dump [db] [out]
#   ... wc_cli add <question> <answer> <tags> [db]
#   ... wc_cli review <user_id> <item_id> <quality> [db]
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
BUILD="${XDG_CACHE_HOME:-$HOME/.cache}/wordcard-staticpy-cli"
STATICPY_ROOT="${STATICPY_ROOT:-/opt/StaticPy}"
BUILD_COMPILER="$STATICPY_ROOT/staticpy/static_build_comfycli.sh"
FFI="$ROOT/native/staticpy/ffi.static.py"
mkdir -p "$BUILD" /tmp/opencode
[ -f "$BUILD_COMPILER" ] && [ -f "$FFI" ] || { echo "missing StaticPy compiler: $BUILD_COMPILER" >&2; exit 1; }

cat > "$BUILD/wc_cli.c" <<'C'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "wordcard.h"
#include "txt2png/txt2png_bridge.h"

static char g_buf[8192];

static void clean(char *dst, size_t cap, const char *src) {
    size_t j = 0;
    for (size_t i = 0; src && src[i] && j + 1 < cap; i++) {
        char c = src[i];
        if (c == '\t' || c == '\n' || c == '\r') c = ' ';
        dst[j++] = c;
    }
    dst[j] = 0;
}

const char *wc_cli_version(void) { return wc_version_string(); }

const char *wc_cli_stats(const char *db_path) {
    wordcard_db_t *db = wc_load_db(db_path);
    if (!db) { snprintf(g_buf, sizeof(g_buf), "load failed: %s", db_path); return g_buf; }
    size_t n = wc_item_count(db);
    int users = 0;
    for (size_t i = 0; i < n; i++) {
        item_entry_t *it = wc_find_item_by_id(db, wc_item_id_at(db, i));
        (void)it;
    }
    snprintf(g_buf, sizeof(g_buf), "items=%zu version=%s", n, wc_version_string());
    wc_db_free(db);
    return g_buf;
}

int wc_cli_dump(const char *db_path, const char *out_path) {
    wordcard_db_t *db = wc_load_db(db_path);
    if (!db) return -1;
    FILE *f = fopen(out_path, "w");
    if (!f) { wc_db_free(db); return -2; }
    size_t n = wc_item_count(db);
    int rows = 0;
    for (size_t i = 0; i < n; i++) {
        item_entry_t *it = wc_find_item_by_id(db, wc_item_id_at(db, i));
        if (!it) continue;
        char q[512], a[512], t[128];
        clean(q, sizeof(q), it->question);
        clean(a, sizeof(a), it->answer);
        clean(t, sizeof(t), it->tags);
        fprintf(f, "%u\t%s\t%s\t%s\n", it->id, q, a, t);
        rows++;
    }
    fclose(f);
    wc_db_free(db);
    return rows;
}

int wc_cli_add(const char *db_path, const char *q, const char *a, const char *tags) {
    wordcard_db_t *db = wc_load_db(db_path);
    if (!db) db = wc_db_init();
    if (!db) return -1;
    item_entry_t e;
    memset(&e, 0, sizeof(e));
    snprintf(e.question, sizeof(e.question), "%s", q ? q : "");
    snprintf(e.answer, sizeof(e.answer), "%s", a ? a : "");
    snprintf(e.tags, sizeof(e.tags), "%s", tags ? tags : "");
    e.category = CAT_ENGLISH_VOCAB;
    uint32_t id = wc_add_item(db, &e);
    wc_save_db(db, db_path);
    wc_db_free(db);
    return (int)id;
}

int wc_import_book(const char *path, const char *db, const char *tag, int max_words, const char *freq);
int wc_import_wordlist(const char *tsv, const char *db, const char *name, int limit);

int wc_cli_import(const char *path, const char *db_path, const char *name, int max_words) {
    if (!path || !*path) return -1;
    const char *ext = strrchr(path, '.');
    if (ext && strcasecmp(ext, ".tsv") == 0) {
        return wc_import_wordlist(path, db_path, name, max_words);
    }
    char tag[256];
    snprintf(tag, sizeof(tag), "book:%s", name && *name ? name : "imported");
    return wc_import_book(path, db_path, tag, max_words, "src/wordpick/en_freq.tsv");
}

const char *wc_cli_dict(const char *word, const char *dict) {
    static char buf[4096];
    buf[0] = 0;
    FILE *f = fopen(dict, "r");
    if (!f) return buf;
    char line[4096];
    while (fgets(line, sizeof(line), f)) {
        char *t = strchr(line, '\t');
        if (!t) continue;
        *t = 0;
        if (strcasecmp(line, word) != 0) continue;
        size_t n = strlen(t + 1);
        while (n && (t[1+n-1] == '\n' || t[1+n-1] == '\r')) t[1+--n] = 0;
        size_t ln = strlen(line), rn = strlen(t + 1);
        if (ln > 2000) ln = 2000;
        if (rn > 2000) rn = 2000;
        memcpy(buf, line, ln); buf[ln] = '\t';
        memcpy(buf + ln + 1, t + 1, rn); buf[ln + 1 + rn] = 0;
        break;
    }
    fclose(f);
    return buf;
}

int wc_cli_list(const char *db_path, const char *tag, const char *out_path) {
    wordcard_db_t *db = wc_load_db(db_path);
    if (!db) return -1;
    FILE *f = fopen(out_path, "w");
    if (!f) { wc_db_free(db); return -2; }
    size_t n = wc_item_count(db);
    int rows = 0;
    for (size_t i = 0; i < n; i++) {
        item_entry_t *it = wc_find_item_by_id(db, wc_item_id_at(db, i));
        if (!it) continue;
        if (tag && *tag && !strstr(it->tags, tag)) continue;
        fprintf(f, "%u\t%s\t%s\t%s\n", it->id, it->question, it->answer, it->tags);
        rows++;
    }
    fclose(f); wc_db_free(db); return rows;
}

int wc_cli_due(const char *db_path, int user_id, const char *out_path) {
    wordcard_db_t *db = wc_load_db(db_path);
    if (!db) return -1;
    uint32_t ids[500]; uint8_t modes[500];
    size_t n = wc_generate_daily_queue(db, (uint32_t)user_id, wc_now(), ids, modes, 500);
    FILE *f = fopen(out_path, "w");
    if (!f) { wc_db_free(db); return -2; }
    for (size_t i = 0; i < n; i++) fprintf(f, "%u\t%d\n", ids[i], (int)modes[i]);
    fclose(f); wc_db_free(db); return (int)n;
}

int wc_cli_card(const char *db_path, int item_id, const char *out_path) {
    wordcard_db_t *db = wc_load_db(db_path);
    if (!db) return -1;
    item_entry_t *it = wc_find_item_by_id(db, (uint32_t)item_id);
    if (!it) { wc_db_free(db); return -2; }
    char text[4096];
    snprintf(text, sizeof(text), "Word: %s\n\nDefinition: %s\n\nContext: %s",
             it->question, it->answer, it->explanation);
    txt2png_bridge_style_t st;
    memset(&st, 0, sizeof(st));
    st.font_size = 20; st.width = 500; st.height = 0; st.margin = 24;
    st.leading = 1.4; st.tolerance = 200; st.fg_color = 0x1B365D; st.bg_color = 0xF5F4ED;
    int rc = txt2png_bridge_render_file(text, "/opt/WordCard/LXGWWenKai-Regular.ttf", &st, out_path);
    wc_db_free(db);
    return rc;
}

int wc_cli_review_interactive(const char *db_path, int user_id) {
    wordcard_db_t *db = wc_load_db(db_path);
    if (!db) return -1;
    uint32_t ids[200]; uint8_t modes[200];
    size_t n = wc_generate_daily_queue(db, (uint32_t)user_id, wc_now(), ids, modes, 200);
    int done = 0;
    char line[64];
    for (size_t i = 0; i < n; i++) {
        item_entry_t *it = wc_find_item_by_id(db, ids[i]);
        if (!it) continue;
        printf("[%d/%d] %s\n  %s\n  quality (0-5): ", (int)i+1, (int)n, it->question, it->answer);
        fflush(stdout);
        if (!fgets(line, sizeof(line), stdin)) break;
        int q = atoi(line);
        if (q < 0 || q > 5) continue;
        user_item_mastery_t *m = wc_get_or_create_mastery(db, (uint32_t)user_id, ids[i]);
        if (!m) continue;
        wc_sm2_update(m, (uint8_t)q);
        wc_recalc_overall(m);
        done++;
    }
    wc_save_db(db, db_path);
    wc_db_free(db);
    return done;
}

int wc_cli_review(const char *db_path, int user_id, int item_id, int quality) {
    wordcard_db_t *db = wc_load_db(db_path);
    if (!db) return -1;
    user_item_mastery_t *m = wc_get_or_create_mastery(db, (uint32_t)user_id, (uint32_t)item_id);
    if (!m) { wc_db_free(db); return -2; }
    wc_sm2_update(m, (uint8_t)quality);
    wc_recalc_overall(m);
    int days = m->interval_days;
    wc_save_db(db, db_path);
    wc_db_free(db);
    return days;
}
C

cat > "$BUILD/wc_cli.static.py" <<'PY'
extern fn wc_cli_version() -> str from "wc_cli"
extern fn wc_cli_stats(db_path: str) -> str from "wc_cli"
extern fn wc_cli_dump(db_path: str, out_path: str) -> int from "wc_cli"
extern fn wc_cli_add(db_path: str, q: str, a: str, tags: str) -> int from "wc_cli"
extern fn wc_cli_review(db_path: str, user_id: int, item_id: int, quality: int) -> int from "wc_cli"
extern fn wc_cli_card(db_path: str, item_id: int, out_path: str) -> int from "wc_cli"
extern fn wc_cli_dict(word: str, dict: str) -> str from "wc_cli"
extern fn wc_cli_list(db_path: str, tag: str, out_path: str) -> int from "wc_cli"
extern fn wc_cli_due(db_path: str, user_id: int, out_path: str) -> int from "wc_cli"
extern fn wc_cli_import(path: str, db: str, name: str, max_words: int) -> int from "wc_cli"
extern fn wc_cli_review_interactive(db_path: str, user_id: int) -> int from "wc_cli"

def main():
    args = list_to_py_list(argv())
    n: int = py_list_length(args)
    cmd: str = "stats"
    if n > 1:
        cmd = py_list_ref(args, 1)
    db: str = "data/wordcard.db"
    if cmd == "stats":
        print(wc_cli_version())
        print(wc_cli_stats(db))
    elif cmd == "dump":
        if n > 2:
            db = py_list_ref(args, 2)
        out: str = "/tmp/opencode/wc_cli_dump.tsv"
        if n > 3:
            out = py_list_ref(args, 3)
        print(wc_cli_dump(db, out))
    elif cmd == "add":
        if n < 5:
            print("usage: wc_cli add <question> <answer> <tags> [db]")
            exit_program(1)
        if n > 5:
            db = py_list_ref(args, 5)
        print(wc_cli_add(db, py_list_ref(args, 2), py_list_ref(args, 3), py_list_ref(args, 4)))
    elif cmd == "import":
        if n < 5:
            print("usage: wc_cli import <path> <db> <name> [max_words]")
            exit_program(1)
        mx: int = 50
        if n > 5: mx = string_to_int(py_list_ref(args, 5))
        print(wc_cli_import(py_list_ref(args, 2), py_list_ref(args, 3),
                            py_list_ref(args, 4), mx))
    elif cmd == "dict":
        if n < 3:
            print("usage: wc_cli dict <word> [dict.tsv]")
            exit_program(1)
        dict: str = "data/wordlists/cet4.tsv"
        if n > 3: dict = py_list_ref(args, 3)
        print(wc_cli_dict(py_list_ref(args, 2), dict))
    elif cmd == "list":
        if n < 3:
            print("usage: wc_cli list <tag> [db] [out.tsv]")
            exit_program(1)
        if n > 3: db = py_list_ref(args, 3)
        out: str = "/tmp/opencode/wc_cli_list.tsv"
        if n > 4: out = py_list_ref(args, 4)
        print(wc_cli_list(db, py_list_ref(args, 2), out))
    elif cmd == "due":
        if n < 3:
            print("usage: wc_cli due <user> [db] [out.tsv]")
            exit_program(1)
        if n > 3: db = py_list_ref(args, 3)
        out: str = "/tmp/opencode/wc_cli_due.tsv"
        if n > 4: out = py_list_ref(args, 4)
        print(wc_cli_due(db, string_to_int(py_list_ref(args, 2)), out))
    elif cmd == "review-interactive":
        if n < 3:
            print("usage: wc_cli review-interactive <user> [db]")
            exit_program(1)
        if n > 3: db = py_list_ref(args, 3)
        print(wc_cli_review_interactive(db, string_to_int(py_list_ref(args, 2))))
    elif cmd == "card":
        if n < 3:
            print("usage: wc_cli card <item_id> [db] [out.png]")
            exit_program(1)
        if n > 3: db = py_list_ref(args, 3)
        out: str = "/tmp/opencode/wc_cli_card.png"
        if n > 4: out = py_list_ref(args, 4)
        print(wc_cli_card(db, string_to_int(py_list_ref(args, 2)), out))
    elif cmd == "review":
        if n < 5:
            print("usage: wc_cli review <user> <item> <quality> [db]")
            exit_program(1)
        if n > 5:
            db = py_list_ref(args, 5)
        print(wc_cli_review(db, string_to_int(py_list_ref(args, 2)),
                            string_to_int(py_list_ref(args, 3)),
                            string_to_int(py_list_ref(args, 4))))
    else:
        print("usage: wc_cli stats|dump|add|review ...")
        exit_program(2)
PY

CC="${CC:-gcc}"
$CC -O2 -fPIC -shared -I"$ROOT/src" "$BUILD/wc_cli.c" \
  -L"$ROOT/src" -lwordcard -ltxt2png \
  -L"$HERE/../import_book" -lwc_import_book -L"$HERE/../import_wordlist" -lwc_import_wordlist \
  -L"$ROOT/importer/libs" -lmobiparse -lpdfparse -lepubparse -lwordpick \
  -Wl,-rpath,'$ORIGIN/../../../src:$ORIGIN/../import_book:$ORIGIN/../import_wordlist:$ORIGIN/../../../importer/libs' \
  -o "$HERE/libwc_cli.so"

sed '/^extern fn /d' "$BUILD/wc_cli.static.py" > "$BUILD/wc_cli.body.py"
grep -E '^extern fn wc_cli_' "$FFI" > "$BUILD/wc_cli.ffi.py"
cat "$BUILD/wc_cli.ffi.py" "$BUILD/wc_cli.body.py" > "$BUILD/wc_cli.combined.py"
bash "$BUILD_COMPILER" \
  "$BUILD/wc_cli.combined.py" wc_cli >/tmp/opencode/wc_cli_build.log 2>&1
mv -f "$STATICPY_ROOT/wc_cli" "$HERE/wc_cli"
mv -f "$STATICPY_ROOT/wc_cli.so" "$HERE/wc_cli.so"

echo "built: $HERE/wc_cli"
