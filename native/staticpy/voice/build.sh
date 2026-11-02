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
$CC -O2 -fPIC -shared -I"$ROOT/voice/wrappers" "$ROOT/native/src/voice_static.c" \
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
