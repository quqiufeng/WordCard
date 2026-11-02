#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

void *mobi_open(const char *);
int mobi_extract_text(void *, char **, size_t *);
void mobi_free_text(char *);
void mobi_close(void *);

void *pdf_open(const char *);
int pdf_extract_text(void *, char **, size_t *);
void pdf_free_text(char *);
void pdf_close(void *);

void *epub_open(const char *);
int epub_extract_text(void *, char **, size_t *);
void epub_close(void *);

static int write_text(const char *text, size_t n, const char *out) {
    FILE *f = fopen(out, "wb");
    if (!f) return -1;
    size_t w = fwrite(text, 1, n, f);
    fclose(f);
    return w == n ? 0 : -2;
}

static int read_plain(const char *path, const char *out) {
    FILE *f = fopen(path, "rb");
    if (!f) return -1;
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (n < 0 || n > 64 * 1024 * 1024) { fclose(f); return -2; }
    char *text = (char *)malloc((size_t)n + 1);
    if (!text) { fclose(f); return -3; }
    size_t r = fread(text, 1, (size_t)n, f);
    fclose(f);
    int rc = write_text(text, r, out);
    free(text);
    return rc;
}

int main(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr, "usage: wc_ebook_text <book> <out.txt>\n");
        return 1;
    }
    const char *path = argv[1];
    const char *out = argv[2];
    const char *ext = strrchr(path, '.');
    char *text = NULL;
    size_t n = 0;
    int rc = -1;

    if (ext && strcasecmp(ext, ".txt") == 0) {
        return read_plain(path, out) == 0 ? 0 : 2;
    }
    if (ext && (strcasecmp(ext, ".mobi") == 0 ||
                strcasecmp(ext, ".azw3") == 0)) {
        void *h = mobi_open(path);
        if (h && mobi_extract_text(h, &text, &n) == 0) {
            rc = write_text(text, n, out);
            mobi_free_text(text);
        }
        if (h) mobi_close(h);
        return rc == 0 ? 0 : 2;
    }
    if (ext && strcasecmp(ext, ".pdf") == 0) {
        void *h = pdf_open(path);
        if (h && pdf_extract_text(h, &text, &n) == 0) {
            rc = write_text(text, n, out);
            pdf_free_text(text);
        }
        if (h) pdf_close(h);
        return rc == 0 ? 0 : 2;
    }
    if (ext && strcasecmp(ext, ".epub") == 0) {
        void *h = epub_open(path);
        if (h && epub_extract_text(h, &text, &n) == 0) {
            rc = write_text(text, n, out);
        }
        if (h) epub_close(h);
        return rc == 0 ? 0 : 2;
    }
    return read_plain(path, out) == 0 ? 0 : 2;
}
