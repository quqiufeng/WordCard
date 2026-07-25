#include "txt2png/txt2png_bridge.h"
#include <cstdio>
#include <cstring>

int main() {
    const char *font = "../LXGWWenKai-Regular.ttf";
    const char *font2 = "../JetBrainsMono-Bold.ttf";
    int pass = 0, fail = 0;

    txt2png_bridge_style_t s;
    s.font_size = 28;
    s.width = 600;
    s.height = 0;
    s.margin = 20;
    s.leading = 1.4;
    s.tolerance = 200;
    s.fg_color = 0x000000;
    s.bg_color = 0xFFFFFF;
    s.nohyphen = 0;
    s.hyphen_dict_path = nullptr;

    const char *t1 = "Hello, World!\nThis is HarfBuzz + Knuth-Plass.\n中日文混排测试。";
    int r = txt2png_bridge_render_file(t1, font, &s, "test_txt2png.png");
    if (r == 0) { std::printf("  [file] test_txt2png.png ... OK\n"); pass++; }
    else { std::printf("  [file] FAIL (ret=%d)\n", r); fail++; }

    s.font_size = 24;
    size_t sz = 0;
    unsigned char *buf = txt2png_bridge_render_mem("Memory output test", font2, &s, &sz);
    if (buf && sz > 0) { std::printf("  [mem] %zu bytes ... OK\n", sz); txt2png_bridge_free(buf); pass++; }
    else { std::printf("  [mem] FAIL\n"); fail++; }

    std::printf("\n%d passed, %d failed\n", pass, fail);
    return fail > 0 ? 1 : 0;
}
