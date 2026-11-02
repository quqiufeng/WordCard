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
