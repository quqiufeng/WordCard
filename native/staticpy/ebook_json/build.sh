#!/bin/bash
# build.sh — 电子书解析为 App 可直接消费的 JSON（StaticPy）
# 用法: wc_ebook_json <book> <out.json> [max_words] [dict.tsv] [freq.tsv]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
BUILD="${XDG_CACHE_HOME:-$HOME/.cache}/wordcard-staticpy-ebook-json"
STATICPY_ROOT="${STATICPY_ROOT:-/opt/StaticPy}"
BUILD_COMPILER="$STATICPY_ROOT/staticpy/static_build_comfycli.sh"
FFI="$ROOT/native/staticpy/ffi.static.py"
mkdir -p "$BUILD" /tmp/opencode
[ -f "$BUILD_COMPILER" ] && [ -f "$FFI" ] || { echo "missing StaticPy compiler/ffi" >&2; exit 1; }

cat > "$BUILD/wc_ebook_json.c" <<'C'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include "cjson/cJSON.h"
#include "wordpick.h"

void *mobi_open(const char *);
int mobi_extract_text(void *, char **, size_t *);
int mobi_get_metadata(void *, char *, size_t, char *, size_t);
void mobi_close(void *);
void *pdf_open(const char *);
int pdf_extract_text(void *, char **, size_t *);
void pdf_close(void *);
void *epub_open(const char *);
int epub_extract_text(void *, char **, size_t *);
int epub_get_metadata(void *, char *, size_t, char *, size_t);
void epub_close(void *);

static void base_name(const char *path, char *out, size_t cap) {
    const char *b = strrchr(path, '/');
    b = b ? b + 1 : path;
    snprintf(out, cap, "%s", b);
    char *dot = strrchr(out, '.');
    if (dot) *dot = 0;
}

static char *read_text(const char *path, char *title, size_t tcap,
                       char *author, size_t acap) {
    const char *ext = strrchr(path, '.');
    char *p = NULL, *text = NULL;
    size_t n = 0;
    void *h = NULL;
    void (*closefn)(void *) = NULL;
    title[0] = 0;
    author[0] = 0;
    if (ext && (strcasecmp(ext, ".mobi") == 0 || strcasecmp(ext, ".azw3") == 0)) {
        h = mobi_open(path);
        if (!h) return NULL;
        mobi_get_metadata(h, title, tcap, author, acap);
        mobi_extract_text(h, &p, &n);
        closefn = mobi_close;
    } else if (ext && strcasecmp(ext, ".epub") == 0) {
        h = epub_open(path);
        if (!h) return NULL;
        epub_get_metadata(h, title, tcap, author, acap);
        epub_extract_text(h, &p, &n);
        closefn = epub_close;
    } else if (ext && strcasecmp(ext, ".pdf") == 0) {
        h = pdf_open(path);
        if (!h) return NULL;
        pdf_extract_text(h, &p, &n);
        closefn = pdf_close;
    } else {
        FILE *f = fopen(path, "rb");
        if (!f) return NULL;
        fseek(f, 0, SEEK_END);
        long sz = ftell(f);
        fseek(f, 0, SEEK_SET);
        if (sz < 0 || sz > 32 * 1024 * 1024) { fclose(f); return NULL; }
        p = (char *)malloc((size_t)sz + 1);
        if (!p) { fclose(f); return NULL; }
        n = fread(p, 1, (size_t)sz, f);
        p[n] = 0;
        fclose(f);
    }
    if (p) {
        text = (char *)malloc(n + 1);
        if (text) { memcpy(text, p, n); text[n] = 0; }
    }
    if (closefn) closefn(h);
    return text;
}

static int lookup_def(const char *dict, const char *word,
                      char *ph, size_t pcap, char *def, size_t dcap) {
    ph[0] = 0;
    def[0] = 0;
    if (!dict || !*dict) return 0;
    FILE *f = fopen(dict, "r");
    if (!f) return 0;
    char line[4096];
    while (fgets(line, sizeof(line), f)) {
        char *field[6];
        int nf = 0;
        char *p = line;
        while (nf < 6) {
            field[nf++] = p;
            char *tab = strchr(p, '\t');
            if (!tab) break;
            *tab = 0;
            p = tab + 1;
        }
        if (!nf) continue;
        size_t last = strlen(field[nf - 1]);
        while (last && (field[nf - 1][last - 1] == '\n' ||
                        field[nf - 1][last - 1] == '\r'))
            field[nf - 1][--last] = 0;
        if (strcasecmp(field[0], word) != 0) continue;
        if (nf > 1) snprintf(ph, pcap, "%s", field[1]);
        if (nf > 3) snprintf(def, dcap, "%s", field[3]);
        fclose(f);
        return 1;
    }
    fclose(f);
    return 0;
}

int wc_ebook_json(const char *path, const char *out, int max_words,
                  const char *dict, const char *freq) {
    char title[256], author[256];
    char *text = read_text(path, title, sizeof(title), author, sizeof(author));
    if (!text) return -1;
    if (!title[0]) base_name(path, title, sizeof(title));
    if (max_words <= 0) max_words = 200;
    if (max_words > 500) max_words = 500;

    void *wp = wp_create(freq);
    if (!wp) { free(text); return -2; }
    wp_config_t cfg;
    memset(&cfg, 0, sizeof(cfg));
    cfg.max_words = max_words;
    cfg.target_zipf = 3.8f;
    cfg.min_len = 5;
    cfg.mode = 0;
    cfg.level = 0;
    cfg.known_zipf = 5.0f;
    cfg.coverage_weight = 0.5f;
    wp_word_t words[512];
    int n = wp_select_ex(wp, text, &cfg, words, max_words);
    wp_destroy(wp);
    free(text);
    if (n < 0) return -3;

    cJSON *root = cJSON_CreateObject();
    if (!root) return -4;
    cJSON_AddStringToObject(root, "title", title);
    cJSON_AddStringToObject(root, "author", author);
    cJSON_AddNumberToObject(root, "count", n);
    cJSON *arr = cJSON_AddArrayToObject(root, "words");
    for (int i = 0; i < n; i++) {
        char ph[256], def[2048];
        lookup_def(dict, words[i].word, ph, sizeof(ph), def, sizeof(def));
        cJSON *o = cJSON_CreateObject();
        cJSON_AddStringToObject(o, "w", words[i].word);
        cJSON_AddNumberToObject(o, "rank", i + 1);
        cJSON_AddStringToObject(o, "ph", ph);
        cJSON_AddStringToObject(o, "p", "");
        cJSON_AddStringToObject(o, "d", def);
        cJSON_AddStringToObject(o, "e", "");
        cJSON_AddStringToObject(o, "para", words[i].context);
        cJSON_AddArrayToObject(o, "sents");
        cJSON_AddStringToObject(o, "para_zh", "");
        cJSON_AddArrayToObject(o, "sents_zh");
        cJSON_AddItemToArray(arr, o);
    }
    char *json = cJSON_PrintUnformatted(root);
    cJSON_Delete(root);
    if (!json) return -5;
    FILE *f = fopen(out, "w");
    if (!f) { free(json); return -6; }
    fputs(json, f);
    fclose(f);
    free(json);
    return n;
}
C

cat > "$BUILD/wc_ebook_json.static.py" <<'PY'
extern fn wc_ebook_json(path: str, out: str, max_words: int, dict: str, freq: str) -> int from "wc_ebook_json"

def main():
    args = list_to_py_list(argv())
    n: int = py_list_length(args)
    if n < 3:
        print("usage: wc_ebook_json <book> <out.json> [max_words] [dict.tsv] [freq.tsv]")
        exit_program(1)
    max_words: int = 200
    if n > 3: max_words = string_to_int(py_list_ref(args, 3))
    dict: str = "data/wordlists/cet4.tsv"
    if n > 4: dict = py_list_ref(args, 4)
    freq: str = "src/wordpick/en_freq.tsv"
    if n > 5: freq = py_list_ref(args, 5)
    print(wc_ebook_json(py_list_ref(args, 1), py_list_ref(args, 2),
                        max_words, dict, freq))
PY

CC="${CC:-gcc}"
$CC -O2 -fPIC -shared -I"$ROOT/src" -I"$ROOT/src/wordpick" \
  "$BUILD/wc_ebook_json.c" \
  -L"$ROOT/importer/libs" -lmobiparse -lpdfparse -lepubparse \
  -L"$ROOT/src" -lwordpick -lcjson \
  -Wl,-rpath,'$ORIGIN/../../../importer/libs:$ORIGIN/../../../src' \
  -o "$HERE/libwc_ebook_json.so"

sed '/^extern fn /d' "$BUILD/wc_ebook_json.static.py" > "$BUILD/wc_ebook_json.body.py"
grep -E '^extern fn wc_ebook_json' "$FFI" > "$BUILD/wc_ebook_json.ffi.py"
cat "$BUILD/wc_ebook_json.ffi.py" "$BUILD/wc_ebook_json.body.py" > "$BUILD/wc_ebook_json.combined.py"
bash "$BUILD_COMPILER" "$BUILD/wc_ebook_json.combined.py" wc_ebook_json >/tmp/opencode/wc_ebook_json_build.log 2>&1
mv -f "$STATICPY_ROOT/wc_ebook_json" "$HERE/wc_ebook_json"
mv -f "$STATICPY_ROOT/wc_ebook_json.so" "$HERE/wc_ebook_json.so"
echo "built: $HERE/wc_ebook_json"
