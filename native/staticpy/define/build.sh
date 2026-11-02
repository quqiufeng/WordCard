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

const char *wc_define_word(const char *word, const char *dict) {
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
    g_buf[0] = 0;
    return g_buf;
}
C

cat > "$BUILD/wc_define.static.py" <<'PY'
extern fn wc_define_word(word: str, dict: str) -> str from "wc_define"

def main():
    args = list_to_py_list(argv())
    n: int = py_list_length(args)
    if n < 2:
        print("usage: wc_define <word> [word...] [--dict path]")
        exit_program(1)
    dict: str = "data/wordlists/cet4.tsv"
    end: int = n
    i: int = 1
    while i < n:
        if py_list_ref(args, i) == "--dict" and i + 1 < n:
            dict = py_list_ref(args, i + 1)
            end = i
            break
        i += 1
    i = 1
    while i < end:
        print(wc_define_word(py_list_ref(args, i), dict))
        i += 1
PY

CC="${CC:-gcc}"
$CC -O2 -fPIC -shared "$BUILD/wc_define.c" -o "$HERE/libwc_define.so"

sed '/^extern fn /d' "$BUILD/wc_define.static.py" > "$BUILD/wc_define.body.py"
grep -E '^extern fn wc_define_' "$FFI" > "$BUILD/wc_define.ffi.py"
cat "$BUILD/wc_define.ffi.py" "$BUILD/wc_define.body.py" > "$BUILD/wc_define.combined.py"
bash "$BUILD_COMPILER" "$BUILD/wc_define.combined.py" wc_define >/tmp/opencode/wc_define_build.log 2>&1
mv -f "$STATICPY_ROOT/wc_define" "$HERE/wc_define"
mv -f "$STATICPY_ROOT/wc_define.so" "$HERE/wc_define.so"
echo "built: $HERE/wc_define"
