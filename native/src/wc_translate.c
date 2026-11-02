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
