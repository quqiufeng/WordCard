#!/bin/bash
# build.sh — WordCard 翻译 StaticPy 原生 POC（自包含）
# 默认 POST 到 OpenAI 兼容接口（本地 llama / DeepSeek）
# 用法: wc_translate "text" /tmp/out.txt [url] [model]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
BUILD="${XDG_CACHE_HOME:-$HOME/.cache}/wordcard-staticpy-translate"
STATICPY_ROOT="${STATICPY_ROOT:-/opt/StaticPy}"
BUILD_COMPILER="$STATICPY_ROOT/staticpy/static_build_comfycli.sh"
FFI="$ROOT/native/staticpy/ffi.static.py"
mkdir -p "$BUILD" /tmp/opencode
[ -f "$BUILD_COMPILER" ] && [ -f "$FFI" ] || { echo "missing StaticPy compiler/ffi" >&2; exit 1; }

cat > "$BUILD/wc_translate.c" <<'C'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <curl/curl.h>
#include "cjson/cJSON.h"

typedef struct { char *p; size_t n; } Buf;
static size_t on_data(char *ptr, size_t size, size_t nmemb, void *ud) {
    Buf *b = (Buf *)ud; size_t add = size * nmemb;
    char *np = realloc(b->p, b->n + add + 1);
    if (!np) return 0;
    b->p = np; memcpy(b->p + b->n, ptr, add); b->n += add; b->p[b->n] = 0;
    return add;
}

int wc_translate(const char *text, const char *out_path, const char *url, const char *model) {
    const char *key = getenv("DEEPSEEK_API_KEY");
    if (!url || !*url) url = getenv("WC_LLM_URL");
    if (!url || !*url) url = "http://127.0.0.1:8081/v1/chat/completions";
    if (!model || !*model) model = getenv("DEEPSEEK_MODEL");
    if (!model || !*model) model = "deepseek-flash";

    cJSON *root = cJSON_CreateObject();
    cJSON_AddStringToObject(root, "model", model);
    cJSON *msgs = cJSON_AddArrayToObject(root, "messages");
    cJSON *sys = cJSON_CreateObject();
    cJSON_AddStringToObject(sys, "role", "system");
    cJSON_AddStringToObject(sys, "content", "Translate to Chinese. Return only the translation.");
    cJSON_AddItemToArray(msgs, sys);
    cJSON *usr = cJSON_CreateObject();
    cJSON_AddStringToObject(usr, "role", "user");
    cJSON_AddStringToObject(usr, "content", text ? text : "");
    cJSON_AddItemToArray(msgs, usr);
    char *body = cJSON_PrintUnformatted(root);
    cJSON_Delete(root);
    if (!body) return -1;

    CURL *c = curl_easy_init();
    if (!c) { free(body); return -2; }
    Buf resp = {0};
    struct curl_slist *hdrs = NULL;
    hdrs = curl_slist_append(hdrs, "Content-Type: application/json");
    if (key && *key) {
        char auth[1024]; snprintf(auth, sizeof(auth), "Authorization: Bearer %s", key);
        hdrs = curl_slist_append(hdrs, auth);
    }
    curl_easy_setopt(c, CURLOPT_URL, url);
    curl_easy_setopt(c, CURLOPT_POST, 1L);
    curl_easy_setopt(c, CURLOPT_POSTFIELDS, body);
    curl_easy_setopt(c, CURLOPT_HTTPHEADER, hdrs);
    curl_easy_setopt(c, CURLOPT_WRITEFUNCTION, on_data);
    curl_easy_setopt(c, CURLOPT_WRITEDATA, &resp);
    curl_easy_setopt(c, CURLOPT_TIMEOUT, 120L);
    CURLcode rc = curl_easy_perform(c);
    curl_slist_free_all(hdrs);
    curl_easy_cleanup(c);
    free(body);
    if (rc != CURLE_OK) { free(resp.p); return -3; }

    cJSON *doc = cJSON_Parse(resp.p ? resp.p : "");
    free(resp.p);
    if (!doc) return -4;
    cJSON *choices = cJSON_GetObjectItem(doc, "choices");
    cJSON *first = cJSON_IsArray(choices) ? cJSON_GetArrayItem(choices, 0) : NULL;
    cJSON *msg = first ? cJSON_GetObjectItem(first, "message") : NULL;
    cJSON *content = msg ? cJSON_GetObjectItem(msg, "content") : NULL;
    if (!cJSON_IsString(content)) { cJSON_Delete(doc); return -5; }
    FILE *f = fopen(out_path, "w");
    if (!f) { cJSON_Delete(doc); return -6; }
    fputs(content->valuestring, f); fputc('\n', f); fclose(f);
    cJSON_Delete(doc);
    return 0;
}
C

cat > "$BUILD/wc_translate.static.py" <<'PY'
extern fn wc_translate(text: str, out_path: str, url: str, model: str) -> int from "wc_translate"

def main():
    args = list_to_py_list(argv())
    n: int = py_list_length(args)
    if n < 3:
        print("usage: wc_translate <text> <out.txt> [url] [model]")
        exit_program(1)
    url: str = ""
    if n > 3: url = py_list_ref(args, 3)
    model: str = ""
    if n > 4: model = py_list_ref(args, 4)
    print(wc_translate(py_list_ref(args, 1), py_list_ref(args, 2), url, model))
PY

CC="${CC:-gcc}"
$CC -O2 -fPIC -shared "$BUILD/wc_translate.c" -lcurl -lcjson \
  -o "$HERE/libwc_translate.so"

sed '/^extern fn /d' "$BUILD/wc_translate.static.py" > "$BUILD/wc_translate.body.py"
grep -E '^extern fn wc_translate' "$FFI" > "$BUILD/wc_translate.ffi.py"
cat "$BUILD/wc_translate.ffi.py" "$BUILD/wc_translate.body.py" > "$BUILD/wc_translate.combined.py"
bash "$BUILD_COMPILER" "$BUILD/wc_translate.combined.py" wc_translate >/tmp/opencode/wc_translate_build.log 2>&1
mv -f "$STATICPY_ROOT/wc_translate" "$HERE/wc_translate"
mv -f "$STATICPY_ROOT/wc_translate.so" "$HERE/wc_translate.so"
echo "built: $HERE/wc_translate"
