#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <errno.h>
#include <sys/stat.h>
#include <curl/curl.h>
#include "cjson/cJSON.h"

#define MAX_FIELDS 32
#define FIELD_CAP 16384
#define URL "https://raw.githubusercontent.com/skywind3000/ECDICT/master/ecdict.csv"

typedef struct {
    const char *name;
    const char *title;
    const char *tag;
    int bit;
    FILE *out;
    int count;
} wl_t;

static wl_t LISTS[] = {
    {"cet4", "CET-4 四级", "cet4", 1 << 0, NULL, 0},
    {"cet6", "CET-6 六级", "cet6", 1 << 1, NULL, 0},
    {"ky", "考研", "ky", 1 << 2, NULL, 0},
    {"toefl", "托福 TOEFL", "toefl", 1 << 3, NULL, 0},
    {"ielts", "雅思 IELTS", "ielts", 1 << 4, NULL, 0},
    {"gre", "GRE", "gre", 1 << 5, NULL, 0},
    {"gk", "高考", "gk", 1 << 6, NULL, 0},
};

static void mkdirp(const char *path) {
    if (!path || !*path) return;
    char tmp[1024];
    snprintf(tmp, sizeof(tmp), "%s", path);
    for (char *p = tmp + 1; *p; p++) {
        if (*p != '/') continue;
        *p = 0;
        mkdir(tmp, 0775);
        *p = '/';
    }
    mkdir(tmp, 0775);
}

static int download(const char *cache) {
    char tmp[1200];
    snprintf(tmp, sizeof(tmp), "%s.part", cache);
    CURL *c = curl_easy_init();
    if (!c) return -1;
    FILE *f = fopen(tmp, "wb");
    if (!f) { curl_easy_cleanup(c); return -2; }
    curl_easy_setopt(c, CURLOPT_URL, URL);
    curl_easy_setopt(c, CURLOPT_FOLLOWLOCATION, 1L);
    curl_easy_setopt(c, CURLOPT_FAILONERROR, 1L);
    curl_easy_setopt(c, CURLOPT_WRITEDATA, f);
    curl_easy_setopt(c, CURLOPT_TIMEOUT, 300L);
    CURLcode rc = curl_easy_perform(c);
    fclose(f);
    curl_easy_cleanup(c);
    if (rc != CURLE_OK) { remove(tmp); return -3; }
    if (rename(tmp, cache) != 0) { remove(tmp); return -4; }
    return 0;
}

static char *trim(char *s) {
    while (*s && isspace((unsigned char)*s)) s++;
    size_t n = strlen(s);
    while (n && isspace((unsigned char)s[n - 1])) s[--n] = 0;
    return s;
}

static void unescape(const char *src, char *dst, size_t cap) {
    size_t j = 0;
    int space = 0;
    for (size_t i = 0; src && src[i] && j + 1 < cap; i++) {
        if (src[i] == '\\' && (src[i + 1] == 'n' || src[i + 1] == 'r')) {
            space = 1;
            i++;
            continue;
        }
        if (isspace((unsigned char)src[i])) {
            space = 1;
            continue;
        }
        if (space && j > 0 && j + 1 < cap) dst[j++] = ' ';
        space = 0;
        dst[j++] = src[i];
    }
    dst[j] = 0;
}

static const char *field(char fields[][FIELD_CAP], int nf, int idx) {
    if (idx < 0 || idx >= nf) return "";
    return fields[idx];
}

static int known_tag(const char *tag) {
    for (size_t i = 0; i < sizeof(LISTS) / sizeof(LISTS[0]); i++)
        if (strcmp(tag, LISTS[i].tag) == 0) return (int)i;
    return -1;
}

static int process_row(char fields[][FIELD_CAP], int nf, int mask,
                       int *col_word, int *col_ph, int *col_pos,
                       int *col_tr, int *col_def, int *col_tag) {
    char *word = trim(fields[*col_word]);
    if (!word[0] || strchr(word, ' ') || strchr(word, '-') ||
        strchr(word, '\'')) return 0;
    char *phonetic = trim(fields[*col_ph]);
    char *pos = trim(fields[*col_pos]);
    char translation[FIELD_CAP], definition[FIELD_CAP];
    unescape(field(fields, nf, *col_tr), translation, sizeof(translation));
    unescape(field(fields, nf, *col_def), definition, sizeof(definition));
    if (!translation[0] && !definition[0]) return 0;

    int hits[8], nh = 0;
    char tags[8][32], tagbuf[FIELD_CAP];
    snprintf(tagbuf, sizeof(tagbuf), "%s", field(fields, nf, *col_tag));
    char *save = NULL;
    for (char *t = strtok_r(tagbuf, " \t", &save); t;
         t = strtok_r(NULL, " \t", &save)) {
        int li = known_tag(t);
        if (li < 0 || !(mask & LISTS[li].bit)) continue;
        int dup = 0;
        for (int k = 0; k < nh; k++) if (hits[k] == li) dup = 1;
        if (!dup && nh < 8) {
            hits[nh++] = li;
            snprintf(tags[nh - 1], sizeof(tags[0]), "%s", t);
        }
    }
    if (!nh) return 0;
    for (int i = 0; i < nh; i++)
        for (int j = i + 1; j < nh; j++)
            if (strcmp(tags[i], tags[j]) > 0) {
                char tmp[32];
                snprintf(tmp, sizeof(tmp), "%s", tags[i]);
                snprintf(tags[i], sizeof(tags[i]), "%s", tags[j]);
                snprintf(tags[j], sizeof(tags[j]), "%s", tmp);
            }
    char tagout[256] = {0};
    for (int i = 0; i < nh; i++) {
        if (i) strncat(tagout, " ", sizeof(tagout) - strlen(tagout) - 1);
        strncat(tagout, tags[i], sizeof(tagout) - strlen(tagout) - 1);
    }
    char ph[FIELD_CAP], po[FIELD_CAP];
    unescape(phonetic, ph, sizeof(ph));
    unescape(pos, po, sizeof(po));
    for (int i = 0; i < nh; i++) {
        FILE *f = LISTS[hits[i]].out;
        if (!f) continue;
        fprintf(f, "%s\t%s\t%s\t%s\t%s\n", word, ph, po, translation, tagout);
        LISTS[hits[i]].count++;
    }
    return 1;
}

int wc_build_wordlists(const char *cache_arg, const char *out_arg,
                       int mask, int refresh) {
    if (mask == 0) mask = 127;
    char cache[1024], out[1024];
    const char *home = getenv("HOME");
    if (cache_arg && *cache_arg) snprintf(cache, sizeof(cache), "%s", cache_arg);
    else snprintf(cache, sizeof(cache), "%s/.cache/wordcard/ecdict.csv",
                  home && *home ? home : "/tmp");
    if (out_arg && *out_arg) snprintf(out, sizeof(out), "%s", out_arg);
    else snprintf(out, sizeof(out), "data/wordlists");

    struct stat st;
    if (refresh || stat(cache, &st) != 0) {
        char dir[1024];
        snprintf(dir, sizeof(dir), "%s", cache);
        char *slash = strrchr(dir, '/');
        if (slash) { *slash = 0; mkdirp(dir); }
        printf("下载 ECDICT -> %s\n", cache);
        fflush(stdout);
        if (download(cache) != 0) return -1;
    }
    if (stat(cache, &st) != 0) return -1;
    printf("ECDICT: %s (%.1f MB)\n", cache, (double)st.st_size / 1e6);
    mkdirp(out);

    for (size_t i = 0; i < sizeof(LISTS) / sizeof(LISTS[0]); i++) {
        if (!(mask & LISTS[i].bit)) continue;
        char path[1200];
        snprintf(path, sizeof(path), "%s/%s.tsv", out, LISTS[i].name);
        LISTS[i].out = fopen(path, "w");
        if (!LISTS[i].out) return -2;
        LISTS[i].count = 0;
    }

    FILE *f = fopen(cache, "rb");
    if (!f) return -3;
    fseek(f, 0, SEEK_END);
    long sz = ftell(f);
    fseek(f, 0, SEEK_SET);
    char *data = (char *)malloc((size_t)sz + 1);
    if (!data) { fclose(f); return -4; }
    size_t got = fread(data, 1, (size_t)sz, f);
    data[got] = 0;
    fclose(f);

    int col_word = -1, col_ph = -1, col_pos = -1;
    int col_tr = -1, col_def = -1, col_tag = -1;
    int header = 1;
    char fields[MAX_FIELDS][FIELD_CAP];
    int nf = 0, len = 0, quoted = 0;
    for (char *p = data; ; p++) {
        char c = *p;
        if (quoted) {
            if (c == '"') {
                if (p[1] == '"') {
                    if (len < FIELD_CAP - 1) fields[nf][len++] = '"';
                    p++;
                } else {
                    quoted = 0;
                }
                continue;
            }
            if (c) {
                if (len < FIELD_CAP - 1) fields[nf][len++] = c;
                continue;
            }
            quoted = 0;
        }
        if (c == '"') { quoted = 1; continue; }
        if (c == ',' || c == '\n' || c == '\r' || !c) {
            if (nf < MAX_FIELDS) { fields[nf][len] = 0; nf++; }
            len = 0;
            if (c == '\r' && p[1] == '\n') p++;
            if (c == '\n' || c == '\r' || !c) {
                if (nf > 0) {
                    if (header) {
                        if (nf > 0 && !strncmp(fields[0], "\xEF\xBB\xBF", 3)) {
                            size_t n = strlen(fields[0]);
                            if (n >= 3)
                                memmove(fields[0], fields[0] + 3, n - 2);
                        }
                        for (int i = 0; i < nf; i++) {
                            char *h = trim(fields[i]);
                            if (!strcmp(h, "word")) col_word = i;
                            else if (!strcmp(h, "phonetic")) col_ph = i;
                            else if (!strcmp(h, "pos")) col_pos = i;
                            else if (!strcmp(h, "translation")) col_tr = i;
                            else if (!strcmp(h, "definition")) col_def = i;
                            else if (!strcmp(h, "tag")) col_tag = i;
                        }
                        header = 0;
                    } else if (col_word >= 0 && col_tag >= 0) {
                        process_row(fields, nf, mask, &col_word, &col_ph,
                                    &col_pos, &col_tr, &col_def, &col_tag);
                    }
                }
                nf = 0;
                if (!c) break;
            }
            continue;
        }
        if (len < FIELD_CAP - 1) fields[nf][len++] = c;
    }
    free(data);

    for (size_t i = 0; i < sizeof(LISTS) / sizeof(LISTS[0]); i++) {
        if (LISTS[i].out) { fclose(LISTS[i].out); LISTS[i].out = NULL; }
    }

    cJSON *root = cJSON_CreateObject();
    for (size_t i = 0; i < sizeof(LISTS) / sizeof(LISTS[0]); i++) {
        if (!(mask & LISTS[i].bit)) continue;
        cJSON *o = cJSON_AddObjectToObject(root, LISTS[i].name);
        cJSON_AddStringToObject(o, "title", LISTS[i].title);
        cJSON_AddStringToObject(o, "tag", LISTS[i].tag);
        cJSON_AddNumberToObject(o, "count", LISTS[i].count);
        char file[64];
        snprintf(file, sizeof(file), "%s.tsv", LISTS[i].name);
        cJSON_AddStringToObject(o, "file", file);
        cJSON_AddStringToObject(o, "source", "ECDICT (skywind3000)");
        printf("  %-6s %-12s %5d 词\n", LISTS[i].name, LISTS[i].title, LISTS[i].count);
    }
    char *js = cJSON_Print(root);
    cJSON_Delete(root);
    if (!js) return -5;
    char mpath[1200];
    snprintf(mpath, sizeof(mpath), "%s/manifest.json", out);
    FILE *mf = fopen(mpath, "w");
    if (!mf) { free(js); return -6; }
    fputs(js, mf);
    fclose(mf);
    free(js);
    printf("完成 -> %s\n", out);
    return 0;
}
