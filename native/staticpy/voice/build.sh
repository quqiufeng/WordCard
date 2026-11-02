#!/bin/bash
# build.sh — WordCard 语音 StaticPy 原生版（自包含）
# 源码在构建时生成到 ~/.cache；本地只保留本脚本。
#
# 用法:
#   bash native/staticpy/voice/build.sh          # -> native/staticpy/voice/wc_voice
#   bash native/staticpy/voice/build.sh --run    # 编译并跑 TTS + ASR
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
BUILD="${XDG_CACHE_HOME:-$HOME/.cache}/wordcard-staticpy-voice"
STATICPY_ROOT="${STATICPY_ROOT:-/opt/StaticPy}"
BUILD_COMPILER="$STATICPY_ROOT/staticpy/static_build_comfycli.sh"
FFI="$ROOT/native/staticpy/ffi.static.py"
mkdir -p "$BUILD" /tmp/opencode
[ -f "$BUILD_COMPILER" ] && [ -f "$FFI" ] || { echo "missing StaticPy compiler: $BUILD_COMPILER" >&2; exit 1; }

cat > "$BUILD/voice_static.c" <<'C'
// libvoice_engine → StaticPy 友好接口（TTS/ASR/播放/转码）
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/wait.h>
#include <stdint.h>
#include "voice_engine.h"

static char g_asr[8192];

int voice_static_tts(const char *text, const char *out_path, const char *sid) {
    void *e = voice_tts_create(NULL);
    if (!e) return -1;
    if (voice_tts_load(e, NULL, NULL, 4, 0) != 0) {
        voice_tts_destroy(e);
        return -2;
    }
    if (sid && *sid) voice_tts_set_sid(e, atoi(sid));
    char *p = voice_tts_synthesize(e, text ? text : "", out_path ? out_path : NULL);
    int ok = p ? 0 : -3;
    if (p) voice_tts_free_text(p);
    voice_tts_destroy(e);
    return ok;
}

const char *voice_static_asr(const char *wav, const char *lang) {
    void *e = voice_asr_create(NULL);
    if (!e) return "asr create failed";
    if (voice_asr_load(e, NULL, NULL, NULL, 4, 0) != 0) {
        voice_asr_destroy(e);
        return "asr load failed";
    }
    char *p = voice_asr_transcribe_file(e, wav ? wav : "", lang ? lang : "auto");
    if (p) {
        snprintf(g_asr, sizeof(g_asr), "%s", p);
        voice_asr_free_text(p);
    } else {
        g_asr[0] = 0;
    }
    voice_asr_destroy(e);
    return g_asr;
}

int voice_static_play(const char *wav) { return voice_play_wav(wav, NULL); }

int voice_static_say(const char *text, const char *sid) {
    const char *out = "/tmp/opencode/wc_tts.wav";
    int rc = voice_static_tts(text, out, sid);
    if (rc != 0) return rc;
    return voice_static_play(out);
}

int voice_static_record(const char *out, int seconds, int rate, const char *device) {
    if (!out || !*out) return -1;
    char sr[16], st[16];
    snprintf(sr, sizeof(sr), "%d", rate > 0 ? rate : 16000);
    snprintf(st, sizeof(st), "%d", seconds > 0 ? seconds : 3);
    pid_t pid = fork();
    if (pid < 0) return -2;
    if (pid == 0) {
        execlp("ffmpeg", "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
               "-f", "alsa", "-i", (device && *device) ? device : "default",
               "-ar", sr, "-ac", "1", "-c:a", "pcm_s16le", "-t", st, out, (char *)NULL);
        _exit(127);
    }
    int stt = 0;
    waitpid(pid, &stt, 0);
    return WIFEXITED(stt) ? WEXITSTATUS(stt) : -3;
}

const char *voice_static_wav_info(const char *path) {
    static char buf[256];
    FILE *f = fopen(path, "rb");
    if (!f) return "wav open failed";
    unsigned char h[12];
    if (fread(h, 1, 12, f) != 12 || memcmp(h, "RIFF", 4) != 0 || memcmp(h + 8, "WAVE", 4) != 0) {
        fclose(f); return "not wav";
    }
    int ch = 0, sr = 0, bits = 0;
    uint32_t data = 0;
    for (;;) {
        unsigned char c[8];
        if (fread(c, 1, 8, f) != 8) break;
        uint32_t sz = c[4] | (c[5] << 8) | (c[6] << 16) | ((uint32_t)c[7] << 24);
        if (memcmp(c, "fmt ", 4) == 0) {
            unsigned char fmt[16];
            if (fread(fmt, 1, 16, f) != 16) break;
            ch = fmt[2] | (fmt[3] << 8);
            sr = fmt[4] | (fmt[5] << 8) | (fmt[6] << 16) | ((uint32_t)fmt[7] << 24);
            bits = fmt[14] | (fmt[15] << 8);
            if (sz > 16) fseek(f, sz - 16, SEEK_CUR);
        } else if (memcmp(c, "data", 4) == 0) {
            data = sz; break;
        } else {
            fseek(f, sz, SEEK_CUR);
        }
        if (sz & 1) fseek(f, 1, SEEK_CUR);
    }
    fclose(f);
    int bytes = ch > 0 ? ch * (bits / 8) : 2;
    long frames = bytes > 0 ? (long)(data / bytes) : 0;
    long ms = sr > 0 ? frames * 1000 / sr : 0;
    snprintf(buf, sizeof(buf), "sr=%d ch=%d bits=%d frames=%ld duration_ms=%ld", sr, ch, bits, frames, ms);
    return buf;
}
int voice_static_convert(const char *in, const char *out, int rate) {
    return voice_convert_to_wav(in, out, rate);
}
C

cat > "$BUILD/wc_voice.static.py" <<'PY'
extern fn voice_static_tts(text: str, out_path: str, sid: str) -> int from "voice_static"
extern fn voice_static_asr(wav: str, lang: str) -> str from "voice_static"
extern fn voice_static_record(out: str, seconds: int, rate: int, device: str) -> int from "voice_static"
extern fn voice_static_wav_info(wav: str) -> str from "voice_static"
extern fn voice_static_play(wav: str) -> int from "voice_static"
extern fn voice_static_say(text: str, sid: str) -> int from "voice_static"

def main():
    args = list_to_py_list(argv())
    n: int = py_list_length(args)
    cmd: str = ""
    if n > 1: cmd = py_list_ref(args, 1)
    if cmd == "say" and n > 2:
        sid: str = "3"
        if n > 3: sid = py_list_ref(args, 3)
        print(voice_static_say(py_list_ref(args, 2), sid))
    elif cmd == "tts" and n > 3:
        sid: str = "3"
        if n > 4: sid = py_list_ref(args, 4)
        print(voice_static_tts(py_list_ref(args, 2), py_list_ref(args, 3), sid))
    elif cmd == "play" and n > 2:
        print(voice_static_play(py_list_ref(args, 2)))
    elif cmd == "asr" and n > 2:
        lang: str = "auto"
        if n > 3: lang = py_list_ref(args, 3)
        print(voice_static_asr(py_list_ref(args, 2), lang))
    elif cmd == "record" and n > 2:
        seconds: int = 3
        if n > 3: seconds = string_to_int(py_list_ref(args, 3))
        rate: int = 16000
        if n > 4: rate = string_to_int(py_list_ref(args, 4))
        device: str = "default"
        if n > 5: device = py_list_ref(args, 5)
        print(voice_static_record(py_list_ref(args, 2), seconds, rate, device))
    elif cmd == "wavinfo" and n > 2:
        print(voice_static_wav_info(py_list_ref(args, 2)))
    else:
        print("usage: wc_voice say|tts|play|asr|record|wavinfo ...")
PY

CC="${CC:-gcc}"
$CC -O2 -fPIC -shared -I"$ROOT/voice/wrappers" "$BUILD/voice_static.c" \
  -L"$ROOT/voice/libs" -lvoice_engine -Wl,-rpath,'$ORIGIN/../../../voice/libs' \
  -o "$HERE/libvoice_static.so"

sed '/^extern fn /d' "$BUILD/wc_voice.static.py" > "$BUILD/wc_voice.body.py"
grep -E '^extern fn voice_static_' "$FFI" > "$BUILD/wc_voice.ffi.py"
cat "$BUILD/wc_voice.ffi.py" "$BUILD/wc_voice.body.py" > "$BUILD/wc_voice.combined.py"
bash "$BUILD_COMPILER" \
  "$BUILD/wc_voice.combined.py" wc_voice >/tmp/opencode/wc_voice_build.log 2>&1
mv -f "$STATICPY_ROOT/wc_voice" "$HERE/wc_voice"
mv -f "$STATICPY_ROOT/wc_voice.so" "$HERE/wc_voice.so"

echo "built: $HERE/wc_voice"
if [ "${1:-}" = "--run" ]; then
  cd "$ROOT"
  LD_LIBRARY_PATH="$HERE:$ROOT/voice/libs" "$HERE/wc_voice"
fi
