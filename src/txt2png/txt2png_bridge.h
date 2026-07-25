#ifndef TXT2PNG_BRIDGE_H
#define TXT2PNG_BRIDGE_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

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

#ifdef __cplusplus
}
#endif

#endif
