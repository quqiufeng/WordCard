"""ASR / TTS — C++ voice engine via libvoice_engine.so

ASR (Speech-to-Text):
  SenseVoice — /opt/SenseVoice.cpp subprocess (via C++ engine)

TTS (Text-to-Speech):
  Piper — /opt/piper/build/piper subprocess (via C++ engine)

Audio Capture:
  ALSA + VAD — C++ capture thread with callback
"""

import ctypes, os, tempfile

_LIB_PATH = os.path.join(os.path.dirname(__file__), 'voice', 'libs', 'libvoice_engine.so')

_lib = None

def _load():
    global _lib
    if _lib is not None:
        return _lib
    if not os.path.exists(_LIB_PATH):
        return None
    _lib = ctypes.CDLL(_LIB_PATH)
    _lib.voice_asr_create.argtypes = [ctypes.c_char_p]
    _lib.voice_asr_create.restype = ctypes.c_void_p
    _lib.voice_asr_load.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_char_p,
                                     ctypes.c_char_p, ctypes.c_int, ctypes.c_int]
    _lib.voice_asr_load.restype = ctypes.c_int
    _lib.voice_asr_transcribe_file.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_char_p]
    _lib.voice_asr_transcribe_file.restype = ctypes.POINTER(ctypes.c_char)
    _lib.voice_asr_free_text.argtypes = [ctypes.POINTER(ctypes.c_char)]
    _lib.voice_asr_free_text.restype = None
    _lib.voice_asr_destroy.argtypes = [ctypes.c_void_p]
    _lib.voice_asr_destroy.restype = None
    _lib.voice_tts_create.argtypes = [ctypes.c_char_p]
    _lib.voice_tts_create.restype = ctypes.c_void_p
    _lib.voice_tts_load.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_char_p,
                                     ctypes.c_int, ctypes.c_int]
    _lib.voice_tts_load.restype = ctypes.c_int
    _lib.voice_tts_set_sid.argtypes = [ctypes.c_void_p, ctypes.c_int]
    _lib.voice_tts_set_sid.restype = None
    _lib.voice_tts_synthesize.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_char_p]
    _lib.voice_tts_synthesize.restype = ctypes.POINTER(ctypes.c_char)
    _lib.voice_tts_free_text.argtypes = [ctypes.POINTER(ctypes.c_char)]
    _lib.voice_tts_free_text.restype = None
    _lib.voice_tts_destroy.argtypes = [ctypes.c_void_p]
    _lib.voice_tts_destroy.restype = None
    _lib.voice_capture_create.argtypes = [ctypes.c_char_p, ctypes.c_int, ctypes.c_int,
                                           ctypes.c_int, ctypes.c_int, ctypes.c_int,
                                           ctypes.c_void_p, ctypes.c_void_p]
    _lib.voice_capture_create.restype = ctypes.c_void_p
    _lib.voice_capture_start.argtypes = [ctypes.c_void_p]
    _lib.voice_capture_start.restype = ctypes.c_int
    _lib.voice_capture_stop.argtypes = [ctypes.c_void_p]
    _lib.voice_capture_stop.restype = None
    _lib.voice_capture_destroy.argtypes = [ctypes.c_void_p]
    _lib.voice_capture_destroy.restype = None
    _lib.voice_play_wav.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
    _lib.voice_play_wav.restype = ctypes.c_int
    _lib.voice_convert_to_wav.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_int]
    _lib.voice_convert_to_wav.restype = ctypes.c_int
    return _lib

# ── ASR ───────────────────────────────────────────────────────────

def asr_available():
    lib = _load()
    return lib is not None and os.path.exists('/opt/SenseVoice.cpp/build/bin/sense-voice-main')

def transcribe(wav_path, lang='auto', n_threads=4):
    lib = _load()
    if not lib:
        raise RuntimeError('libvoice_engine.so not loaded')
    engine = lib.voice_asr_create(None)
    if not engine:
        raise RuntimeError('ASR engine creation failed')
    try:
        lib.voice_asr_load(engine, None, None, None, n_threads, 0)
        text_p = lib.voice_asr_transcribe_file(engine, wav_path.encode(), lang.encode())
        result = ctypes.cast(text_p, ctypes.c_char_p).value.decode('utf-8') if text_p else ''
        if text_p:
            lib.voice_asr_free_text(text_p)
        return result
    finally:
        lib.voice_asr_destroy(engine)

# ── TTS ───────────────────────────────────────────────────────────

def tts_available():
    lib = _load()
    return lib is not None and os.path.exists('/opt/sherpa-onnx/bin/sherpa-onnx-offline-tts')

def synthesize(text, output_path=None, sid=None):
    lib = _load()
    if not lib:
        raise RuntimeError('libvoice_engine.so not loaded')
    engine = lib.voice_tts_create(None)
    if not engine:
        raise RuntimeError('TTS engine creation failed')
    try:
        lib.voice_tts_load(engine, None, None, 4, 0)
        if sid is not None:
            lib.voice_tts_set_sid(engine, int(sid))
        out = output_path.encode() if output_path else None
        text_p = lib.voice_tts_synthesize(engine, text.encode(), out)
        result = ctypes.cast(text_p, ctypes.c_char_p).value.decode('utf-8') if text_p else ''
        if text_p:
            lib.voice_tts_free_text(text_p)
        return result
    finally:
        lib.voice_tts_destroy(engine)

# ── Audio Capture ─────────────────────────────────────────────────

def capture_start(device='default', sample_rate=16000, frame_ms=100,
                  silence_ms=1200, min_speech_ms=300, max_seg_ms=6000,
                  callback=None):
    lib = _load()
    if not lib:
        raise RuntimeError('libvoice_engine.so not loaded')
    cb = ctypes.CFUNCTYPE(None, ctypes.POINTER(ctypes.c_int16), ctypes.c_int, ctypes.c_void_p)(callback) if callback else None
    handle = lib.voice_capture_create(device.encode(), sample_rate, frame_ms,
                                       silence_ms, min_speech_ms, max_seg_ms, cb, None)
    if not handle:
        raise RuntimeError('Capture creation failed')
    lib.voice_capture_start(handle)
    return handle

def capture_stop(handle):
    lib = _load()
    if lib and handle:
        lib.voice_capture_stop(handle)
        lib.voice_capture_destroy(handle)

# ── Playback ──────────────────────────────────────────────────────

def play_wav(path, device=None):
    lib = _load()
    if not lib:
        raise RuntimeError('libvoice_engine.so not loaded')
    return lib.voice_play_wav(path.encode(), device.encode() if device else None)

# ── Utility ───────────────────────────────────────────────────────

def convert_to_wav(input_path, output_path=None, sample_rate=16000):
    lib = _load()
    if not lib:
        raise RuntimeError('libvoice_engine.so not loaded')
    if output_path is None:
        output_path = os.path.splitext(input_path)[0] + '.wav'
    lib.voice_convert_to_wav(input_path.encode(), output_path.encode(), sample_rate)
    return output_path
