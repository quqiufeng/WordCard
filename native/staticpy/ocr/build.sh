#!/bin/bash
# build.sh — WordCard OCR StaticPy 原生 POC（自包含）
# 用法: bash native/staticpy/ocr/build.sh
#       wc_ocr <image> <out.txt>
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
BUILD="${XDG_CACHE_HOME:-$HOME/.cache}/wordcard-staticpy-ocr"
STATICPY_ROOT="${STATICPY_ROOT:-/opt/StaticPy}"
BUILD_COMPILER="$STATICPY_ROOT/staticpy/static_build_comfycli.sh"
FFI="$ROOT/native/staticpy/ffi.static.py"
mkdir -p "$BUILD" /tmp/opencode
[ -f "$BUILD_COMPILER" ] && [ -f "$FFI" ] || { echo "missing StaticPy compiler/ffi" >&2; exit 1; }

cat > "$BUILD/wc_ocr.c" <<'C'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "cjson/cJSON.h"

typedef struct ocr_simple_t ocr_simple_t;
ocr_simple_t *ocr_simple_create(const char *det, const char *rec, const char *dict);
char *ocr_simple_run(ocr_simple_t *h, const char *image);
void ocr_simple_free(char *s);
void ocr_simple_destroy(ocr_simple_t *h);

typedef struct { double x, y; char *text; } Box;

static int cmp_box(const void *a, const void *b) {
    const Box *x = (const Box *)a, *y = (const Box *)b;
    if (x->y < y->y - 12) return -1;
    if (x->y > y->y + 12) return 1;
    return x->x < y->x ? -1 : (x->x > y->x ? 1 : 0);
}

int wc_ocr(const char *image, const char *out_path) {
    const char *root = "/opt/WordCard";
    char det[512], rec[512], dict[512];
    snprintf(det, sizeof(det), "%s/models/ocr/ch_PP-OCRv4_det_infer.onnx", root);
    snprintf(rec, sizeof(rec), "%s/models/ocr/ch_PP-OCRv4_rec_infer.onnx", root);
    snprintf(dict, sizeof(dict), "%s/models/ocr/ppocr_keys_v1.txt", root);
    ocr_simple_t *h = ocr_simple_create(det, rec, dict);
    if (!h) return -1;
    char *raw = ocr_simple_run(h, image);
    if (!raw) { ocr_simple_destroy(h); return -2; }
    cJSON *arr = cJSON_Parse(raw);
    ocr_simple_free(raw);
    ocr_simple_destroy(h);
    if (!arr || !cJSON_IsArray(arr)) { cJSON_Delete(arr); return -3; }
    int n = cJSON_GetArraySize(arr);
    Box *boxes = (Box *)calloc((size_t)n, sizeof(Box));
    if (!boxes) { cJSON_Delete(arr); return -4; }
    for (int i = 0; i < n; i++) {
        cJSON *it = cJSON_GetArrayItem(arr, i);
        cJSON *x = cJSON_GetObjectItem(it, "x");
        cJSON *y = cJSON_GetObjectItem(it, "y");
        cJSON *t = cJSON_GetObjectItem(it, "text");
        if (cJSON_IsNumber(x)) boxes[i].x = x->valuedouble;
        if (cJSON_IsNumber(y)) boxes[i].y = y->valuedouble;
        if (cJSON_IsString(t)) boxes[i].text = strdup(t->valuestring);
    }
    cJSON_Delete(arr);
    qsort(boxes, (size_t)n, sizeof(Box), cmp_box);
    FILE *f = fopen(out_path, "w");
    if (!f) { for (int i = 0; i < n; i++) free(boxes[i].text); free(boxes); return -5; }
    double cy = -1e9;
    for (int i = 0; i < n; i++) {
        if (!boxes[i].text) continue;
        if (cy > -1e8 && boxes[i].y > cy + 12) fputc('\n', f);
        else if (cy > -1e8) fputc(' ', f);
        fputs(boxes[i].text, f);
        cy = boxes[i].y;
    }
    fputc('\n', f);
    fclose(f);
    for (int i = 0; i < n; i++) free(boxes[i].text);
    free(boxes);
    return 0;
}
C

cat > "$BUILD/wc_ocr.static.py" <<'PY'
extern fn wc_ocr(image: str, out_path: str) -> int from "wc_ocr"

def main():
    args = list_to_py_list(argv())
    if py_list_length(args) < 3:
        print("usage: wc_ocr <image> <out.txt>")
        exit_program(1)
    print(wc_ocr(py_list_ref(args, 1), py_list_ref(args, 2)))
PY

CC="${CC:-gcc}"
$CC -O2 -fPIC -shared -I/usr/include "$BUILD/wc_ocr.c" \
  -L"$ROOT/voice/libs" -locr_simple -lcjson -Wl,-rpath,'$ORIGIN/../../../voice/libs' \
  -o "$HERE/libwc_ocr.so"

sed '/^extern fn /d' "$BUILD/wc_ocr.static.py" > "$BUILD/wc_ocr.body.py"
grep -E '^extern fn wc_ocr' "$FFI" > "$BUILD/wc_ocr.ffi.py"
cat "$BUILD/wc_ocr.ffi.py" "$BUILD/wc_ocr.body.py" > "$BUILD/wc_ocr.combined.py"
bash "$BUILD_COMPILER" "$BUILD/wc_ocr.combined.py" wc_ocr >/tmp/opencode/wc_ocr_build.log 2>&1
mv -f "$STATICPY_ROOT/wc_ocr" "$HERE/wc_ocr"
mv -f "$STATICPY_ROOT/wc_ocr.so" "$HERE/wc_ocr.so"
echo "built: $HERE/wc_ocr"
