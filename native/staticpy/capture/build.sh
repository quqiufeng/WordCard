#!/bin/bash
# build.sh — WordCard 录音 capture StaticPy 原生 POC（自包含）
# 用法: wc_capture <out.wav> [seconds] [device]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
BUILD="${XDG_CACHE_HOME:-$HOME/.cache}/wordcard-staticpy-capture"
STATICPY_ROOT="${STATICPY_ROOT:-/opt/StaticPy}"
BUILD_COMPILER="$STATICPY_ROOT/staticpy/static_build_comfycli.sh"
FFI="$ROOT/native/staticpy/ffi.static.py"
mkdir -p "$BUILD" /tmp/opencode
[ -f "$BUILD_COMPILER" ] && [ -f "$FFI" ] || { echo "missing StaticPy compiler/ffi" >&2; exit 1; }

cat > "$BUILD/wc_capture.c" <<'C'
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
C

cat > "$BUILD/wc_capture.static.py" <<'PY'
extern fn wc_capture(out: str, seconds: int, device: str) -> int from "wc_capture"

def main():
    args = list_to_py_list(argv())
    n: int = py_list_length(args)
    if n < 2:
        print("usage: wc_capture <out.wav> [seconds] [device]")
        exit_program(1)
    seconds: int = 2
    if n > 2: seconds = string_to_int(py_list_ref(args, 2))
    device: str = "plughw:CARD=Webcams,0"
    if n > 3: device = py_list_ref(args, 3)
    print(wc_capture(py_list_ref(args, 1), seconds, device))
PY

CC="${CC:-gcc}"
$CC -O2 -fPIC -shared -I"$ROOT/voice/wrappers" "$BUILD/wc_capture.c" \
  -L"$ROOT/voice/libs" -lvoice_engine -Wl,-rpath,'$ORIGIN/../../../voice/libs' \
  -o "$HERE/libwc_capture.so"

sed '/^extern fn /d' "$BUILD/wc_capture.static.py" > "$BUILD/wc_capture.body.py"
grep -E '^extern fn wc_capture' "$FFI" > "$BUILD/wc_capture.ffi.py"
cat "$BUILD/wc_capture.ffi.py" "$BUILD/wc_capture.body.py" > "$BUILD/wc_capture.combined.py"
bash "$BUILD_COMPILER" "$BUILD/wc_capture.combined.py" wc_capture >/tmp/opencode/wc_capture_build.log 2>&1
mv -f "$STATICPY_ROOT/wc_capture" "$HERE/wc_capture"
mv -f "$STATICPY_ROOT/wc_capture.so" "$HERE/wc_capture.so"
echo "built: $HERE/wc_capture"
