#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include "wordpick.h"
#include "txt2png/txt2png_bridge.h"

void *mobi_open(const char *); int mobi_extract_text(void *, char **, size_t *); void mobi_close(void *);
void *pdf_open(const char *); int pdf_extract_text(void *, char **, size_t *); void pdf_close(void *);
void *epub_open(const char *); int epub_extract_text(void *, char **, size_t *); void epub_close(void *);

static char *read_text(const char *path) {
    const char *ext = strrchr(path, '.');
    char *p = NULL; size_t n = 0; void *h = NULL; void (*closefn)(void *) = NULL;
    if (ext && (strcasecmp(ext, ".mobi") == 0 || strcasecmp(ext, ".azw3") == 0)) {
        h = mobi_open(path); if (!h) return NULL; mobi_extract_text(h, &p, &n); closefn = mobi_close;
    } else if (ext && strcasecmp(ext, ".epub") == 0) {
        h = epub_open(path); if (!h) return NULL; epub_extract_text(h, &p, &n); closefn = epub_close;
    } else if (ext && strcasecmp(ext, ".pdf") == 0) {
        h = pdf_open(path); if (!h) return NULL; pdf_extract_text(h, &p, &n); closefn = pdf_close;
    } else {
        FILE *f = fopen(path, "rb"); if (!f) return NULL;
        fseek(f, 0, SEEK_END); long sz = ftell(f); fseek(f, 0, SEEK_SET);
        if (sz < 0 || sz > 32 * 1024 * 1024) { fclose(f); return NULL; }
        p = (char *)malloc((size_t)sz + 1); if (!p) { fclose(f); return NULL; }
        size_t got = fread(p, 1, (size_t)sz, f); p[got] = 0; fclose(f); n = got;
    }
    char *out = NULL;
    if (p) { out = (char *)malloc(n + 1); if (out) { memcpy(out, p, n); out[n] = 0; } }
    if (closefn) closefn(h);
    return out;
}

static void lookup(const char *dict, const char *word, char *out, size_t cap) {
    out[0] = 0;
    FILE *f = fopen(dict, "r"); if (!f) return;
    char line[4096];
    while (fgets(line, sizeof(line), f)) {
        char *t = strchr(line, '\t'); if (!t) continue;
        *t = 0;
        if (strcasecmp(line, word) != 0) continue;
        char *ph = t + 1; char *p1 = strchr(ph, '\t'); if (!p1) break;
        *p1 = 0; char *pos = p1 + 1; char *p2 = strchr(pos, '\t'); if (!p2) break;
        *p2 = 0; char *tr = p2 + 1; char *p3 = strchr(tr, '\t'); if (p3) *p3 = 0;
        size_t n = strlen(tr); while (n && (tr[n-1]=='\n'||tr[n-1]=='\r')) tr[--n]=0;
        snprintf(out, cap, "[%s] %s", pos[0]?pos:"word", tr);
        break;
    }
    fclose(f);
}

int wc_vocab_card(const char *book, const char *outdir, int max_words, const char *dict) {
    char *text = read_text(book); if (!text) return -1;
    if (max_words <= 0) max_words = 10;
    if (max_words > 100) max_words = 100;
    void *wp = wp_create("/opt/WordCard/src/wordpick/en_freq.tsv"); if (!wp) { free(text); return -2; }
    wp_config_t cfg; memset(&cfg, 0, sizeof(cfg));
    cfg.max_words = max_words; cfg.target_zipf = 3.8f; cfg.min_len = 5;
    cfg.mode = 0; cfg.level = 0; cfg.known_zipf = 5.0f; cfg.coverage_weight = 0.5f;
    wp_word_t words[128];
    int n = wp_select_ex(wp, text, &cfg, words, max_words);
    wp_destroy(wp); free(text);
    if (n <= 0) return -3;
    mkdir(outdir, 0755);
    char mdpath[1024]; snprintf(mdpath, sizeof(mdpath), "%s/vocab_cards.md", outdir);
    FILE *md = fopen(mdpath, "w");
    if (md) fprintf(md, "# Vocabulary Cards\n\n");
    for (int i = 0; i < n; i++) {
        char def[512]; lookup(dict, words[i].word, def, sizeof(def));
        if (!def[0]) snprintf(def, sizeof(def), "(no definition)");
        char wb[64], cb[512];
        snprintf(wb, sizeof(wb), "%.63s", words[i].word);
        snprintf(cb, sizeof(cb), "%.511s", words[i].context);
        char body[2048];
        snprintf(body, sizeof(body), "Word: %s\n\nDefinition: %s\n\nContext: %s", wb, def, cb);
        char path[1024]; snprintf(path, sizeof(path), "%s/%02d_%s.png", outdir, i+1, wb);
        txt2png_bridge_style_t st; memset(&st, 0, sizeof(st));
        st.font_size = 20; st.width = 800; st.height = 0; st.margin = 32;
        st.leading = 1.4; st.tolerance = 200; st.fg_color = 0x1B365D; st.bg_color = 0xF5F4ED;
        txt2png_bridge_render_file(body, "/opt/WordCard/LXGWWenKai-Regular.ttf", &st, path);
        if (md) fprintf(md, "## %s\n\n%s\n\n![%s](%02d_%s.png)\n\n", wb, body, wb, i+1, wb);
    }
    if (md) fclose(md);
    return n;
}
