#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <unistd.h>
#include "voice_engine.h"

static int16_t *g_pcm; static size_t g_cap, g_len; static volatile int g_done;
static void cb(const int16_t *pcm, int frames, void *ud) {
    (void)ud;
    if (!g_pcm || frames <= 0 || g_done) return;
    size_t n = (size_t)frames;
    if (g_len + n > g_cap) { n = g_cap - g_len; g_done = 1; }
    memcpy(g_pcm + g_len, pcm, n * sizeof(int16_t)); g_len += n;
    if (g_len >= g_cap) g_done = 1;
}
static void wav_header(FILE *f, int rate, size_t samples) {
    uint32_t data = (uint32_t)(samples * 2);
    uint32_t riff = data + 36;
    fwrite("RIFF", 1, 4, f); fwrite(&riff, 4, 1, f); fwrite("WAVE", 1, 4, f);
    fwrite("fmt ", 1, 4, f); uint32_t sz = 16; fwrite(&sz, 4, 1, f);
    uint16_t pcm = 1, ch = 1; uint32_t br = (uint32_t)(rate * 2), ba = 2;
    uint16_t bits = 16;
    fwrite(&pcm, 2, 1, f); fwrite(&ch, 2, 1, f); fwrite(&rate, 4, 1, f);
    fwrite(&br, 4, 1, f); fwrite(&ba, 2, 1, f); fwrite(&bits, 2, 1, f);
    fwrite("data", 1, 4, f); fwrite(&data, 4, 1, f);
}
int wc_capture(const char *out, int seconds, const char *device) {
    if (seconds <= 0) seconds = 2;
    if (seconds > 30) seconds = 30;
    g_cap = (size_t)seconds * 16000; g_len = 0; g_done = 0;
    g_pcm = (int16_t *)malloc(g_cap * sizeof(int16_t));
    if (!g_pcm) return -1;
    void *h = voice_capture_create(device && *device ? device : "default",
                                    16000, 100, 600, 100, seconds * 1000, cb, NULL);
    if (!h) { free(g_pcm); return -2; }
    voice_capture_start(h);
    for (int i = 0; i < seconds * 20 && !g_done; i++) usleep(50000);
    voice_capture_stop(h);
    voice_capture_destroy(h);
    FILE *f = fopen(out, "wb");
    if (!f) { free(g_pcm); return -3; }
    wav_header(f, 16000, g_len); fwrite(g_pcm, sizeof(int16_t), g_len, f); fclose(f);
    free(g_pcm); g_pcm = NULL;
    return (int)g_len;
}
