#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <libgen.h>
#include "wordcard.h"
#include "wordpick.h"

void *mobi_open(const char *);
int mobi_extract_text(void *, char **, size_t *);
int mobi_get_metadata(void *, char *, size_t, char *, size_t);
void mobi_close(void *);
void *pdf_open(const char *);
int pdf_extract_text(void *, char **, size_t *);
void pdf_close(void *);
void *epub_open(const char *);
int epub_extract_text(void *, char **, size_t *);
int epub_get_metadata(void *, char *, size_t, char *, size_t);
void epub_close(void *);

static char *base_title(const char *path) {
    char tmp[1024]; snprintf(tmp, sizeof(tmp), "%s", path);
    char *b = basename(tmp); char *dot = strrchr(b, '.');
    if (dot) *dot = 0;
    return strdup(b);
}

static char *extract_text(const char *path, char *title, size_t tcap) {
    const char *ext = strrchr(path, '.');
    char *p = NULL, *text = NULL; size_t n = 0;
    void *h = NULL;
    void (*closefn)(void *) = NULL;
    if (ext && (strcasecmp(ext, ".mobi") == 0 || strcasecmp(ext, ".azw3") == 0)) {
        h = mobi_open(path); if (!h) return NULL;
        char author[256]; mobi_get_metadata(h, title, tcap, author, sizeof(author));
        mobi_extract_text(h, &p, &n); closefn = mobi_close;
    } else if (ext && strcasecmp(ext, ".epub") == 0) {
        h = epub_open(path); if (!h) return NULL;
        char author[256]; epub_get_metadata(h, title, tcap, author, sizeof(author));
        epub_extract_text(h, &p, &n); closefn = epub_close;
    } else if (ext && strcasecmp(ext, ".pdf") == 0) {
        h = pdf_open(path); if (!h) return NULL;
        pdf_extract_text(h, &p, &n); closefn = pdf_close;
    } else {
        FILE *f = fopen(path, "rb"); if (!f) return NULL;
        fseek(f, 0, SEEK_END); long sz = ftell(f); fseek(f, 0, SEEK_SET);
        if (sz < 0 || sz > 32 * 1024 * 1024) { fclose(f); return NULL; }
        p = (char *)malloc((size_t)sz + 1); if (!p) { fclose(f); return NULL; }
        size_t got = fread(p, 1, (size_t)sz, f); p[got] = 0; fclose(f); n = got;
    }
    if (p) {
        text = (char *)malloc(n + 1);
        if (text) { memcpy(text, p, n); text[n] = 0; }
    }
    if (closefn) closefn(h);
    return text;
}

int wc_import_book(const char *path, const char *db_path, const char *tag,
                   int max_words, const char *freq) {
    char title[256] = {0};
    char *text = extract_text(path, title, sizeof(title));
    if (!text) return -1;
    if (!title[0]) { char *b = base_title(path); snprintf(title, sizeof(title), "%s", b); free(b); }
    if (max_words <= 0) max_words = 50;
    if (max_words > 500) max_words = 500;

    void *wp = wp_create(freq); if (!wp) { free(text); return -2; }
    wp_config_t cfg; memset(&cfg, 0, sizeof(cfg));
    cfg.max_words = max_words; cfg.target_zipf = 3.8f; cfg.min_len = 5;
    cfg.mode = 0; cfg.level = 0; cfg.known_zipf = 5.0f; cfg.coverage_weight = 0.5f;
    wp_word_t words[512];
    int n = wp_select_ex(wp, text, &cfg, words, max_words);
    wp_destroy(wp); free(text);
    if (n < 0) return -3;

    wordcard_db_t *db = wc_load_db(db_path);
    if (!db) db = wc_db_init();
    if (!db) return -4;
    int added = 0;
    for (int i = 0; i < n; i++) {
        if (wc_find_item_by_question(db, words[i].word)) continue;
        item_entry_t e; memset(&e, 0, sizeof(e));
        size_t qn = strnlen(words[i].word, sizeof(words[i].word));
        if (qn >= sizeof(e.question)) qn = sizeof(e.question) - 1;
        memcpy(e.question, words[i].word, qn); e.question[qn] = 0;
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
