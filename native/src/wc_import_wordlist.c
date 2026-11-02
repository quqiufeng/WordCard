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
