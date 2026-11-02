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
    const char *root = getenv("WORDCARD_ROOT");
    if (!root || !*root) root = "/opt/WordCard";
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
