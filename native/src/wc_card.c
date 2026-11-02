// txt2png Canvas → StaticPy 友好接口
#include "txt2png/txt2png_bridge.h"

void *wc_canvas_create(int w, int h, int bg) {
    return txt2png_canvas_create(w, h, (uint32_t)bg);
}
int wc_canvas_destroy(void *c) { txt2png_canvas_destroy(c); return 0; }
int wc_canvas_text(void *c, const char *font, int fs, const char *text,
                   int x, int y, int color) {
    return txt2png_canvas_draw_text(c, font, (double)fs, text, x, y, (uint32_t)color);
}
int wc_canvas_measure(void *c, const char *font, int fs, const char *text) {
    return txt2png_canvas_measure(c, font, (double)fs, text);
}
int wc_canvas_save(void *c, const char *path) {
    return txt2png_canvas_save(c, path);
}
int wc_canvas_line(void *c, int x1, int y1, int x2, int y2,
                   int color, int width) {
    txt2png_canvas_line(c, (double)x1, (double)y1, (double)x2, (double)y2, (uint32_t)color, (double)width);
    return 0;
}
int wc_canvas_rect(void *c, int x, int y, int w, int h,
                   int color, int filled) {
    txt2png_canvas_rect(c, (double)x, (double)y, (double)w, (double)h, (uint32_t)color, filled, 0.0, 1.0);
    return 0;
}
