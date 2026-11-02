#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "txt2png/txt2png_bridge.h"

static const char *font_path(void) {
    const char *p = getenv("WORDCARD_FONT");
    return (p && *p) ? p : "/opt/WordCard/LXGWWenKai-Regular.ttf";
}
#define FONT font_path()
#define WIDTH 780
#define MARGIN 40
#define BG 0xF5F4ED
#define INK 0x1B365D
#define BODY 0x2B2A26
#define MUTED 0x6B665C
#define LINE 0xE4DFD3

static int drawing = 1;

static char *read_all(const char *path) {
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (n < 0 || n > 4 * 1024 * 1024) { fclose(f); return NULL; }
    char *b = (char *)malloc((size_t)n + 1);
    if (!b) { fclose(f); return NULL; }
    size_t r = fread(b, 1, (size_t)n, f);
    b[r] = 0;
    fclose(f);
    return b;
}

static void draw_wrapped(txt2png_canvas_t c, const char *text, int x, int *y,
                         int maxw, int fs, int color, int lh) {
    char line[4096];
    size_t ll = 0;
    line[0] = 0;
    const char *p = text;
    while (*p) {
        if (*p == '\n') {
            if (ll) {
                if (drawing) txt2png_canvas_draw_text(c, FONT, fs, line, x, *y, color);
                *y += lh;
                ll = 0;
                line[0] = 0;
            }
            p++;
            continue;
        }
        while (*p == ' ' || *p == '\t') p++;
        if (!*p) break;
        const char *t = p;
        int n = 1;
        unsigned char b = (unsigned char)*p;
        if (b >= 0xF0) n = 4;
        else if (b >= 0xE0) n = 3;
        else if (b >= 0xC0) n = 2;
        else {
            while (*p && *p != ' ' && *p != '\t' && *p != '\n' &&
                   (unsigned char)*p < 0x80) p++;
            n = (int)(p - t);
            if (n == 0) { p++; continue; }
        }
        char cand[4096];
        int space = (ll > 0 && line[ll - 1] != ' ' &&
                     (unsigned char)t[0] < 0x80);
        snprintf(cand, sizeof(cand), "%s%s%.*s", line, space ? " " : "", n, t);
        if (txt2png_canvas_measure(c, FONT, fs, cand) > maxw && ll > 0) {
            if (drawing) txt2png_canvas_draw_text(c, FONT, fs, line, x, *y, color);
            *y += lh;
            memcpy(line, t, (size_t)n);
            ll = (size_t)n;
            line[ll] = 0;
        } else {
            snprintf(line, sizeof(line), "%s", cand);
            ll = strlen(line);
        }
        p = t + n;
    }
    if (ll) {
        if (drawing) txt2png_canvas_draw_text(c, FONT, fs, line, x, *y, color);
        *y += lh;
    }
}

static void draw_content(txt2png_canvas_t c, const char *text, int x, int *y,
                         int maxw) {
    const char *p = text;
    while (*p) {
        const char *e = strchr(p, '\n');
        size_t n = e ? (size_t)(e - p) : strlen(p);
        char tmp[8192];
        if (n >= sizeof(tmp)) n = sizeof(tmp) - 1;
        memcpy(tmp, p, n);
        tmp[n] = 0;
        if (tmp[0]) {
            draw_wrapped(c, tmp, x, y, maxw, 18, BODY, 30);
        } else {
            *y += 10;
        }
        if (!e) break;
        p = e + 1;
    }
}

static int layout_card(txt2png_canvas_t c, const char *title,
                       const char *content) {
    int y = 40;
    if (drawing) txt2png_canvas_draw_text(c, FONT, 18, "WordCard", 40, y, MUTED);
    y += 30;
    draw_wrapped(c, title, 40, &y, WIDTH - 2 * MARGIN, 27, INK, 38);
    y += 14;
    if (drawing) txt2png_canvas_line(c, 40.0, (double)y, 740.0, (double)y, LINE, 1.0);
    y += 26;
    draw_content(c, content, 40, &y, WIDTH - 2 * MARGIN);
    return y;
}

int wc_card_cn(const char *title, const char *content_path, const char *png,
               int height) {
    char *content = read_all(content_path);
    if (!content) return -1;
    int need = height;
    if (need <= 0) {
        drawing = 0;
        txt2png_canvas_t m = txt2png_canvas_create(WIDTH, 1, BG);
        if (!m) { free(content); return -2; }
        need = layout_card(m, title ? title : "", content) + 60;
        txt2png_canvas_destroy(m);
    }
    if (need < 400) need = 400;
    if (need > 20000) need = 20000;

    drawing = 1;
    txt2png_canvas_t c = txt2png_canvas_create(WIDTH, need, BG);
    if (!c) { free(content); return -3; }
    layout_card(c, title ? title : "", content);
    int ok = txt2png_canvas_save(c, png);
    txt2png_canvas_destroy(c);
    free(content);
    return ok;
}

int wc_card_cn_measure(const char *title, const char *content_path) {
    char *content = read_all(content_path);
    if (!content) return -1;
    drawing = 0;
    txt2png_canvas_t m = txt2png_canvas_create(WIDTH, 1, BG);
    if (!m) { free(content); return -2; }
    int need = layout_card(m, title ? title : "", content);
    txt2png_canvas_destroy(m);
    free(content);
    return need;
}
