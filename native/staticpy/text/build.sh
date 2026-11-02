#!/bin/bash
# build.sh — WordCard 选词 + 卡片渲染 StaticPy 原生版（自包含）
# 本地只保留本脚本；C/StaticPy 源码在构建时生成到 ~/.cache。
#
# 用法:
#   bash native/staticpy/text/build.sh          # -> native/staticpy/text/wc_text
#   bash native/staticpy/text/build.sh --run    # 编译并跑选词 + 渲染
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
BUILD="${XDG_CACHE_HOME:-$HOME/.cache}/wordcard-staticpy-text"
STATICPY_ROOT="${STATICPY_ROOT:-/opt/StaticPy}"
BUILD_COMPILER="$STATICPY_ROOT/staticpy/static_build_comfycli.sh"
FFI="$ROOT/native/staticpy/ffi.static.py"
mkdir -p "$BUILD" /tmp/opencode
[ -f "$BUILD_COMPILER" ] && [ -f "$FFI" ] || { echo "missing StaticPy compiler: $BUILD_COMPILER" >&2; exit 1; }

cat > "$BUILD/wc_text_static.c" <<'C'
// wordpick + txt2png → StaticPy 友好接口
#include <stdio.h>
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
C

cat > "$BUILD/wc_text.static.py" <<'PY'
extern fn wc_wordpick_tsv(freq: str, text: str, out: str, max_words: int) -> int from "wc_text_static"
extern fn wc_render_png(text: str, font: str, out: str) -> int from "wc_text_static"

def main():
    text = "The quick brown fox jumps over the lazy dog. Vocabulary learning should be deliberate and consistent. Reading original books builds durable knowledge."
    print(wc_wordpick_tsv("src/wordpick/en_freq.tsv", text, "/tmp/opencode/wc_words.tsv", 10))
    print(wc_render_png("WordCard StaticPy\n选词 + 卡片渲染", "LXGWWenKai-Regular.ttf", "/tmp/opencode/wc_text.png"))
PY

CC="${CC:-gcc}"
$CC -O2 -fPIC -shared -I"$ROOT/src" -I"$ROOT/src/wordpick" -I"$ROOT/src/txt2png" "$BUILD/wc_text_static.c" \
  -L"$ROOT/src" -lwordpick -ltxt2png -Wl,-rpath,'$ORIGIN/../../../src' \
  -o "$HERE/libwc_text_static.so"

sed '/^extern fn /d' "$BUILD/wc_text.static.py" > "$BUILD/wc_text.body.py"
grep -E '^extern fn (wc_wordpick_tsv|wc_render_png)' "$FFI" > "$BUILD/wc_text.ffi.py"
cat "$BUILD/wc_text.ffi.py" "$BUILD/wc_text.body.py" > "$BUILD/wc_text.combined.py"
bash "$BUILD_COMPILER" \
  "$BUILD/wc_text.combined.py" wc_text >/tmp/opencode/wc_text_build.log 2>&1
mv -f "$STATICPY_ROOT/wc_text" "$HERE/wc_text"
mv -f "$STATICPY_ROOT/wc_text.so" "$HERE/wc_text.so"

echo "built: $HERE/wc_text"
if [ "${1:-}" = "--run" ]; then
  cd "$ROOT"
  LD_LIBRARY_PATH="$HERE:$ROOT/src" "$HERE/wc_text"
fi
