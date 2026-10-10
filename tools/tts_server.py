#!/usr/bin/env python3
"""tts_server.py — 常驻 TTS 服务。

从 stdin 逐行读取文本，合成语音并播放；TTS 模型只加载一次，
因此 App 点击单词时朗读很快（合成结果按文本缓存到 data/tts_cache/）。

用法（通常由 App 自动拉起）:
    python3 tools/tts_server.py
环境变量: WC_TTS_SID（音色，默认 0）、WC_APLAY（播放器，默认 aplay）
"""

import array
import hashlib
import os
import subprocess
import sys
import wave

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

import voice  # noqa: E402

CACHE = os.path.join(ROOT, 'data', 'tts_cache')
GAIN = float(os.environ.get('WC_TTS_VOLUME', '2.5'))


def _player():
    """选可用的播放器：paplay / pw-play / aplay。"""
    env = os.environ.get('WC_APLAY')
    if env:
        return env
    for c in ('paplay', 'pw-play', 'aplay'):
        if subprocess.run(['which', c], capture_output=True).returncode == 0:
            return c
    return 'aplay'


PLAY = _player()


def _cache_path(text):
    h = hashlib.md5(text.encode('utf-8')).hexdigest()[:16]
    return os.path.join(CACHE, h + '.wav')


def _amplify(path, gain):
    """16-bit PCM 音量放大（带限幅），原地覆盖。"""
    if gain <= 1.0:
        return
    try:
        with wave.open(path, 'rb') as w:
            params = w.getparams()
            if params.sampwidth != 2:
                return
            a = array.array('h')
            a.frombytes(w.readframes(w.getnframes()))
        for i in range(len(a)):
            x = int(a[i] * gain)
            a[i] = 32767 if x > 32767 else (-32768 if x < -32768 else x)
        with wave.open(path, 'wb') as w:
            w.setparams(params)
            w.writeframes(a.tobytes())
    except Exception:  # noqa: BLE001
        pass


def main():
    try:
        tts = voice.Tts(sid=int(os.environ.get('WC_TTS_SID', '0')))
    except Exception as e:  # noqa: BLE001
        print(f'ERR init: {e}', file=sys.stderr, flush=True)
        return
    os.makedirs(CACHE, exist_ok=True)
    print('READY', flush=True)

    for line in sys.stdin:
        text = line.strip()
        if not text:
            continue
        try:
            path = _cache_path(text)
            if not os.path.exists(path):
                tts.synthesize(text, path)
                _amplify(path, GAIN)
            subprocess.run([PLAY, path], check=False)
            print(f'OK {text}', flush=True)
        except Exception as e:  # noqa: BLE001
            print(f'ERR {e}', file=sys.stderr, flush=True)


if __name__ == '__main__':
    main()
