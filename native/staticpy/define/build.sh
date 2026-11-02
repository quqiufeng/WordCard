#!/bin/bash
# build.sh — WordCard 查词 StaticPy 原生 POC（自包含）
# 用法: bash native/staticpy/define/build.sh
#       wc_define abandon orbit --dict data/wordlists/cet4.tsv
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
BUILD="${XDG_CACHE_HOME:-$HOME/.cache}/wordcard-staticpy-define"
STATICPY_ROOT="${STATICPY_ROOT:-/opt/StaticPy}"
BUILD_COMPILER="$STATICPY_ROOT/staticpy/static_build_comfycli.sh"
FFI="$ROOT/native/staticpy/ffi.static.py"
mkdir -p "$BUILD" /tmp/opencode
[ -f "$BUILD_COMPILER" ] && [ -f "$FFI" ] || { echo "missing StaticPy compiler/ffi" >&2; exit 1; }

cat > "$BUILD/wc_define.c" <<'C'
#include <stdio.h>
#include <string.h>
#include <strings.h>

static char g_buf[8192];

int wc_translate(const char *text, const char *out_path, const char *url, const char *model);

const char *wc_define_word(const char *word, const char *dict, const char *url, const char *model) {
    if (!word || !dict) return "";
    FILE *f = fopen(dict, "r");
    if (!f) return "";
    char line[4096];
    while (fgets(line, sizeof(line), f)) {
        char *tab = strchr(line, '\t');
        if (!tab) continue;
        *tab = 0;
        if (strcasecmp(line, word) == 0) {
            char *p = tab + 1;
            size_t n = strlen(p);
            while (n && (p[n-1] == '\n' || p[n-1] == '\r')) p[--n] = 0;
            snprintf(g_buf, sizeof(g_buf), "%s\t%s", line, p);
            fclose(f);
            return g_buf;
        }
    }
    fclose(f);
    if (url && *url) {
        char prompt[2048], tmp[256] = "/tmp/opencode/wc_define.txt";
        snprintf(prompt, sizeof(prompt),
                 "Give a concise Chinese dictionary definition for the English word: %s. Only output the definition.", word);
        if (wc_translate(prompt, tmp, url, model) == 0) {
            FILE *tf = fopen(tmp, "r");
            if (tf) {
                size_t r = fread(g_buf, 1, sizeof(g_buf)-1, tf); fclose(tf); g_buf[r] = 0;
                while (r && (g_buf[r-1]=='\n'||g_buf[r-1]=='\r'||g_buf[r-1]==' ')) g_buf[--r] = 0;
            }
        }
    }
    return g_buf;
}
C

cat > "$BUILD/wc_define.static.py" <<'PY'
extern fn wc_define_word(word: str, dict: str, url: str, model: str) -> str from "wc_define"

def main():
    args = list_to_py_list(argv())
    n: int = py_list_length(args)
    if n < 2:
        print("usage: wc_define <word> [word...] [--dict path] [--url url] [--model name]")
        exit_program(1)
    dict: str = "data/wordlists/cet4.tsv"
    url: str = ""
    model: str = ""
    words = py_list()
    i: int = 1
    while i < n:
        a: str = py_list_ref(args, i)
        if a == "--dict" and i + 1 < n:
            dict = py_list_ref(args, i + 1); i += 2
        elif a == "--url" and i + 1 < n:
            url = py_list_ref(args, i + 1); i += 2
        elif a == "--model" and i + 1 < n:
            model = py_list_ref(args, i + 1); i += 2
        else:
            words = py_list_append(words, a); i += 1
    i = 0
    while i < py_list_length(words):
        print(wc_define_word(py_list_ref(words, i), dict, url, model))
        i += 1
PY

CC="${CC:-gcc}"
$CC -O2 -fPIC -shared "$BUILD/wc_define.c" \
  -L"$ROOT/native/staticpy/translate" -lwc_translate -lcurl -lcjson \
  -Wl,-rpath,'$ORIGIN/../translate' -o "$HERE/libwc_define.so"

sed '/^extern fn /d' "$BUILD/wc_define.static.py" > "$BUILD/wc_define.body.py"
grep -E '^extern fn wc_define_' "$FFI" > "$BUILD/wc_define.ffi.py"
cat "$BUILD/wc_define.ffi.py" "$BUILD/wc_define.body.py" > "$BUILD/wc_define.combined.py"
bash "$BUILD_COMPILER" "$BUILD/wc_define.combined.py" wc_define >/tmp/opencode/wc_define_build.log 2>&1
mv -f "$STATICPY_ROOT/wc_define" "$HERE/wc_define"
mv -f "$STATICPY_ROOT/wc_define.so" "$HERE/wc_define.so"
echo "built: $HERE/wc_define"
