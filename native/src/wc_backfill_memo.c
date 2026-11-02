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
