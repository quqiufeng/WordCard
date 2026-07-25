#ifndef TXT2PNG_BRIDGE_H
#define TXT2PNG_BRIDGE_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// ── 段落渲染（原 API）──────────────────────────────────────────

typedef struct {
    double font_size;
    int width;
    int height;
    int margin;
    double leading;
    double tolerance;
    uint32_t fg_color;
    uint32_t bg_color;
    int nohyphen;
    const char *hyphen_dict_path;
} txt2png_bridge_style_t;

int txt2png_bridge_render_file(const char *text, const char *font_path,
                                const txt2png_bridge_style_t *style,
                                const char *output_path);

unsigned char* txt2png_bridge_render_mem(const char *text, const char *font_path,
                                          const txt2png_bridge_style_t *style,
                                          size_t *out_size);

void txt2png_bridge_free(unsigned char *data);

// ── 画布 API（布局层渲染）─────────────────────────────────────

typedef void* txt2png_canvas_t;

// 创建画布，bg_color = 0xRRGGBB
txt2png_canvas_t txt2png_canvas_create(int width, int height, uint32_t bg_color);

// 销毁画布
void txt2png_canvas_destroy(txt2png_canvas_t canvas);

// 在 (x, baseline_y) 处绘制文字，返回实际绘制的宽度（像素）
int txt2png_canvas_draw_text(txt2png_canvas_t canvas, const char *font_path,
                              double font_size, const char *text,
                              int x, int baseline_y, uint32_t color);

// 测量文本宽度（像素）
int txt2png_canvas_measure(txt2png_canvas_t canvas, const char *font_path,
                            double font_size, const char *text);

// 将画布保存为 PNG 文件，0=成功
int txt2png_canvas_save(txt2png_canvas_t canvas, const char *output_path);

// 获取画布高度
int txt2png_canvas_height(txt2png_canvas_t canvas);

// 获取上行高度（ascent），用于基线定位
int txt2png_canvas_ascent(txt2png_canvas_t canvas, const char *font_path,
                           double font_size);

#ifdef __cplusplus
}
#endif

#endif
