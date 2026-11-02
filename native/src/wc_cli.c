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
