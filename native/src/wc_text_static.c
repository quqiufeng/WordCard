// wordpick + txt2png → StaticPy 友好接口
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "wordpick.h"
#include "txt2png/txt2png_bridge.h"

int wc_wordpick_tsv(const char *freq, const char *text, const char *out, int max_words) {
    if (max_words <= 0) max_words = 10;
    if (max_words > 128) max_words = 128;
    void *h = wp_create(freq);
    if (!h) return -1;
    wp_config_t cfg;
    memset(&cfg, 0, sizeof(cfg));
    cfg.max_words = max_words;
    cfg.target_zipf = 3.8f;
    cfg.min_len = 5;
    cfg.mode = 0;
    cfg.level = 0;
    cfg.known_zipf = 5.0f;
    cfg.coverage_weight = 0.5f;
    wp_word_t words[128];
    int n = wp_select_ex(h, text ? text : "", &cfg, words, max_words);
    wp_destroy(h);
    if (n < 0) return -2;
    FILE *f = fopen(out, "w");
    if (!f) return -3;
    for (int i = 0; i < n; i++) {
        fprintf(f, "%s\t%.4f\t%.2f\t%d\t%d\t%s\n",
                words[i].word, words[i].score, words[i].zipf,
                words[i].count, words[i].level, words[i].context);
    }
    fclose(f);
    return n;
}

int wc_wordpick_tsv_file(const char *freq, const char *text_path,
                         const char *out, int max_words) {
    FILE *f = fopen(text_path, "rb");
    if (!f) return -4;
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (n < 0 || n > 4 * 1024 * 1024) { fclose(f); return -5; }
    char *text = (char *)malloc((size_t)n + 1);
    if (!text) { fclose(f); return -6; }
    size_t r = fread(text, 1, (size_t)n, f);
    text[r] = 0;
    fclose(f);
    int rc = wc_wordpick_tsv(freq, text, out, max_words);
    free(text);
    return rc;
}

int wc_render_png(const char *text, const char *font, const char *out) {
    txt2png_bridge_style_t st;
    memset(&st, 0, sizeof(st));
    st.font_size = 32.0;
    st.width = 800;
    st.height = 0;
    st.margin = 32;
    st.leading = 1.4;
    st.tolerance = 200;
    st.fg_color = 0x1B365D;
    st.bg_color = 0xF5F4ED;
    st.nohyphen = 0;
    st.hyphen_dict_path = NULL;
    return txt2png_bridge_render_file(text ? text : "", font ? font : "", &st, out);
}
