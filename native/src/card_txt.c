#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/wait.h>
#include "txt2png/txt2png_bridge.h"

static const char *font_path(void) {
    const char *p = getenv("WORDCARD_FONT");
    return (p && *p) ? p : "/opt/WordCard/LXGWWenKai-Regular.ttf";
}
#define FONT font_path()
#define BG 0xF5F4ED
#define INK 0x1B365D
#define BODY 0x2B2A26
#define MUTED 0x6B665C
#define LINE 0xE4DFD3

static char title[256], orig[65536], en[65536], vocab[32768], sent[32768];
static int drawing = 1;

static char *read_all(const char *path) {
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
    if (n < 0 || n > 4 * 1024 * 1024) { fclose(f); return NULL; }
    char *b = (char *)malloc((size_t)n + 1);
    if (!b) { fclose(f); return NULL; }
    size_t r = fread(b, 1, (size_t)n, f); b[r] = 0; fclose(f);
    return b;
}

static void extract(const char *buf, const char *marker, char *out, size_t cap) {
    out[0] = 0;
    const char *p = strstr(buf, marker);
    if (!p) return;
    p += strlen(marker);
    while (*p == '\r' || *p == '\n') p++;
    if (!strncmp(p, "---", 3)) return;
    const char *e = strstr(p, "\n---");
    size_t n = e ? (size_t)(e - p) : strlen(p);
    if (n >= cap) n = cap - 1;
    memcpy(out, p, n); out[n] = 0;
}

static int cjk(const char *p) { return ((unsigned char)p[0]) >= 0xE0; }

static void draw_wrapped(txt2png_canvas_t c, const char *text, int x, int *y,
                         int maxw, int fs, int color, int lh, int maxlines) {
    char line[2048]; size_t ll = 0; int lines = 0; line[0] = 0;
    const char *p = text;
    while (*p && lines < maxlines) {
        if (*p == '\n') {
            if (ll) { if (drawing) txt2png_canvas_draw_text(c, FONT, fs, line, x, *y, color); *y += lh; lines++; }
            ll = 0; line[0] = 0; p++; continue;
        }
        while (*p == ' ' || *p == '\t') p++;
        if (!*p) break;
        const char *t = p; int n = 1;
        unsigned char b = (unsigned char)*p;
        if (b >= 0xF0) n = 4;
        else if (b >= 0xE0) n = 3;
        else if (b >= 0xC0) n = 2;
        else {
            while (*p && *p != ' ' && *p != '\t' && *p != '\n' && (unsigned char)*p < 0x80) p++;
            n = (int)(p - t);
            if (n == 0) { p++; continue; }
        }
        char cand[2048];
        int add_space = (ll > 0 && line[ll - 1] != ' ' && (unsigned char)t[0] < 0x80);
        snprintf(cand, sizeof(cand), "%s%s%.*s", line, add_space ? " " : "", n, t);
        if (txt2png_canvas_measure(c, FONT, fs, cand) > maxw && ll > 0) {
            if (drawing) txt2png_canvas_draw_text(c, FONT, fs, line, x, *y, color);
            *y += lh; lines++;
            if (lines >= maxlines) break;
            memcpy(line, t, (size_t)n); ll = (size_t)n; line[ll] = 0;
        } else {
            snprintf(line, sizeof(line), "%s", cand); ll = strlen(line);
        }
        p = t + n;
    }
    if (ll && lines < maxlines) { if (drawing) txt2png_canvas_draw_text(c, FONT, fs, line, x, *y, color); *y += lh; }
}

static void draw_para(txt2png_canvas_t c, const char *text, int x, int *y,
                      int maxw, int fs, int color, int lh, int maxlines) {
    const char *p = text;
    while (*p && maxlines > 0) {
        const char *e = strchr(p, '\n');
        size_t n = e ? (size_t)(e - p) : strlen(p);
        char tmp[4096]; if (n >= sizeof(tmp)) n = sizeof(tmp) - 1;
        memcpy(tmp, p, n); tmp[n] = 0;
        if (tmp[0]) { draw_wrapped(c, tmp, x, y, maxw, fs, color, lh, maxlines); maxlines--; }
        if (!e) break;
        p = e + 1;
    }
}

static void draw_section(txt2png_canvas_t c, const char *label, int x, int *y) {
    if (drawing) {
        txt2png_canvas_draw_text(c, FONT, 20, label, x, *y, INK);
        *y += 30;
        txt2png_canvas_line(c, (double)x, (double)(*y - 8), 740.0, (double)(*y - 8), LINE, 1.0);
    } else {
        *y += 30;
    }
    *y += 10;
}

static int layout_card(txt2png_canvas_t c) {
    int y = 40;
    if (drawing) txt2png_canvas_draw_text(c, FONT, 18, "WordCard", 40, y, MUTED);
    y += 28;
    if (drawing) txt2png_canvas_draw_text(c, FONT, 30, title, 40, y, INK);
    y += 44;
    if (drawing) txt2png_canvas_line(c, 40.0, (double)y, 740.0, (double)y, LINE, 1.0);
    y += 30;

    if (orig[0]) {
        draw_section(c, "原文", 40, &y);
        draw_para(c, orig, 40, &y, 700, 18, BODY, 28, 2000);
        y += 16;
    }

    if (en[0]) {
        draw_section(c, "中英对照", 40, &y);
        const char *p = en; int lines = 0;
        while (*p && lines < 2000) {
            const char *e = strchr(p, '\n');
            size_t n = e ? (size_t)(e - p) : strlen(p);
            char tmp[2048]; if (n >= sizeof(tmp)) n = sizeof(tmp) - 1;
            memcpy(tmp, p, n); tmp[n] = 0;
            if (tmp[0]) {
                draw_wrapped(c, tmp, 40, &y, 700, 17,
                             cjk(tmp) ? MUTED : BODY, 26, 6);
                lines++;
            }
            if (!e) break;
            p = e + 1;
        }
        y += 16;
    }

    if (vocab[0]) {
        draw_section(c, "词汇表", 40, &y);
        const char *p = vocab; int rows = 0;
        while (*p && rows < 2000) {
            const char *e = strchr(p, '\n');
            size_t n = e ? (size_t)(e - p) : strlen(p);
            char tmp[512]; if (n >= sizeof(tmp)) n = sizeof(tmp) - 1;
            memcpy(tmp, p, n); tmp[n] = 0;
            char *bar = strchr(tmp, '|');
            if (bar) {
                *bar = 0;
                char *w = tmp;
                while (*w == ' ' || (*w >= '0' && *w <= '9') || *w == '.') w++;
                if (drawing) {
                    txt2png_canvas_draw_text(c, FONT, 17, w, 56, y, INK);
                    txt2png_canvas_draw_text(c, FONT, 17, bar + 1, 230, y, MUTED);
                }
                y += 28; rows++;
            }
            if (!e) break;
            p = e + 1;
        }
        y += 16;
    }

    if (sent[0]) {
        draw_section(c, "精彩句子", 40, &y);
        draw_para(c, sent, 40, &y, 700, 18, BODY, 28, 600);
    }
    return y;
}

int wc_card_txt(const char *input, const char *png, const char *md, const char *pdf) {
    char *buf = read_all(input);
    if (!buf) return -1;
    extract(buf, "TITLE:", title, sizeof(title));
    extract(buf, "\nORIGINAL:\n", orig, sizeof(orig));
    extract(buf, "\nEN-CH:\n", en, sizeof(en));
    extract(buf, "\nVOCABULARY:\n", vocab, sizeof(vocab));
    extract(buf, "\nSENTENCES:\n", sent, sizeof(sent));

    drawing = 0;
    txt2png_canvas_t m = txt2png_canvas_create(780, 1, BG);
    if (!m) { free(buf); return -2; }
    int need = layout_card(m) + 60;
    txt2png_canvas_destroy(m);
    if (need < 400) need = 400;
    if (need > 20000) need = 20000;

    drawing = 1;
    txt2png_canvas_t c = txt2png_canvas_create(780, need, BG);
    if (!c) { free(buf); return -3; }
    layout_card(c);
    int ok = txt2png_canvas_save(c, png);
    txt2png_canvas_destroy(c);
    if (ok == 0 && pdf && *pdf) {
        pid_t pid = fork();
        if (pid == 0) {
            execlp("convert", "convert", png, pdf, (char *)NULL);
            _exit(127);
        }
        int st = 0;
        waitpid(pid, &st, 0);
        if (!WIFEXITED(st) || WEXITSTATUS(st) != 0) ok = -4;
    }

    FILE *f = fopen(md, "w");
    if (f) {
        fprintf(f, "# %s\n\n## 原文\n\n%s\n\n## 中英双语\n\n%s\n\n## 词汇表\n\n%s\n\n## 精彩句子\n\n%s\n",
                title, orig, en, vocab, sent);
        fclose(f);
    }
    free(buf);
    return ok;
}
