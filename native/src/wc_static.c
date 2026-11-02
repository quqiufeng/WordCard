// WordCard C ABI → StaticPy 友好接口：struct/指针细节收在这里。
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "wordcard.h"

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

const char *wc_static_version(void) { return wc_version_string(); }

const char *wc_static_summary(const char *db_path) {
    wordcard_db_t *db = wc_load_db(db_path);
    if (!db) {
        snprintf(g_buf, sizeof(g_buf), "load failed: %s", db_path ? db_path : "");
        return g_buf;
    }
    size_t n = wc_item_count(db);
    char tags[64][128];
    int nt = 0;
    for (size_t i = 0; i < n; i++) {
        item_entry_t *it = wc_find_item_by_id(db, wc_item_id_at(db, i));
        if (!it || it->tags[0] == 0) continue;
        int seen = 0;
        for (int k = 0; k < nt; k++) if (strcmp(tags[k], it->tags) == 0) { seen = 1; break; }
        if (!seen && nt < 64) snprintf(tags[nt++], sizeof(tags[0]), "%s", it->tags);
    }
    snprintf(g_buf, sizeof(g_buf), "items=%zu tasks=%d version=%s", n, nt, wc_version_string());
    wc_db_free(db);
    return g_buf;
}

int wc_static_dump(const char *db_path, const char *out_path) {
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

int wc_static_add_item(const char *db_path, const char *q, const char *a, const char *tags) {
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

int wc_static_review(const char *db_path, int user_id, int item_id, int quality) {
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
