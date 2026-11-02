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
