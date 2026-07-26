"""ASR / TTS — 从 /opt/friday 集成的语音能力

ASR (Speech-to-Text):
  Qwen3-ASR  — /opt/friday/agent/qwen3_asr_engine.cpp — ONNX + llama.cpp 本地引擎
  SenseVoice — /opt/friday/shell/shell.cpp subprocess 模式 — ggml 轻量引擎

TTS (Text-to-Speech):
  Piper       — WordCard/voice/wrappers/piper_wrapper.cpp — 需自行编译
  Edge TTS   — 在线 fallback（pip install edge-tts）
"""

import ctypes, os, subprocess, tempfile

_LIB = None
_LIB_PATH = os.path.join(os.path.dirname(__file__), 'voice', 'libs', 'libqwen3_asr.so')
_LLAMA_PATH = '/opt/llama.cpp/build/bin'
_ONNX_PATH = '/data/venv/onnxruntime-linux-x64-gpu-1.26.0/lib'
_QWEN_MODEL_DIR = '/data/models'

# ── ASR: Qwen3-ASR (本地 C++ 引擎，最准) ────────────────────────────

def _load_qwen3():
    global _LIB
    if _LIB is not None:
        return _LIB
    if not os.path.exists(_LIB_PATH):
        return None
    # Set library path so it finds libllama.so.0 + libonnxruntime.so.1
    env = os.environ.copy()
    lp = env.get('LD_LIBRARY_PATH', '')
    for p in [_ONNX_PATH, _LLAMA_PATH]:
        if p not in lp:
            lp = f'{p}:{lp}' if lp else p
    env['LD_LIBRARY_PATH'] = lp
    # Can't change LD_LIBRARY_PATH after process start; use RTLD_GLOBAL
    old_cwd = os.getcwd()
    try:
        _LIB = ctypes.CDLL(_LIB_PATH, mode=ctypes.RTLD_GLOBAL)
    except OSError:
        return None
    _LIB.qwen3_asr_create.argtypes = [ctypes.c_char_p]
    _LIB.qwen3_asr_create.restype = ctypes.c_void_p
    _LIB.qwen3_asr_destroy.argtypes = [ctypes.c_void_p]
    _LIB.qwen3_asr_destroy.restype = None
    _LIB.qwen3_asr_transcribe_file.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_char_p]
    _LIB.qwen3_asr_transcribe_file.restype = ctypes.c_char_p
    _LIB.qwen3_asr_free_text.argtypes = [ctypes.c_char_p]
    _LIB.qwen3_asr_free_text.restype = None
    return _LIB

def qwen3_asr_available():
    """Qwen3-ASR 引擎是否可用（需要 ONNX Runtime + llama.cpp 库）"""
    return _load_qwen3() is not None

def qwen3_asr_transcribe(wav_path, lang=''):
    """使用 Qwen3-ASR 转写音频文件，返回文字"""
    lib = _load_qwen3()
    if not lib:
        raise RuntimeError('libqwen3_asr.so not loaded; try: cd voice && make')
    engine = lib.qwen3_asr_create(_QWEN_MODEL_DIR.encode())
    if not engine:
        raise RuntimeError('Qwen3-ASR engine creation failed')
    try:
        text_p = lib.qwen3_asr_transcribe_file(engine, wav_path.encode(), lang.encode() if lang else None)
        result = text_p.decode('utf-8') if text_p else ''
        if text_p:
            lib.qwen3_asr_free_text(text_p)
        return result
    finally:
        lib.qwen3_asr_destroy(engine)

# ── ASR: SenseVoice (subprocess，轻量) ──────────────────────────────

_SENSE_BIN = '/opt/SenseVoice.cpp/build/bin/sense-voice-main'
_SENSE_MODEL = '/data/models/sense-voice-small-q4_k.gguf'

def sensevoice_available():
    return os.path.exists(_SENSE_BIN) and os.path.exists(_SENSE_MODEL)

def transcribe(wav_path, lang='auto', n_threads=8):
    """SenseVoice 转写（备用，Qwen3-ASR 不可用时用这个）"""
    if not sensevoice_available():
        raise RuntimeError('SenseVoice not available')
    cmd = [_SENSE_BIN, '-m', _SENSE_MODEL, wav_path, '-t', str(n_threads), '--use-itn']
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    if r.returncode != 0:
        raise RuntimeError(f'SenseVoice failed: {r.stderr[:200]}')
    return r.stdout.strip()

# ── TTS: Piper（WordCard voice/wrappers/piper_wrapper.cpp，需编译）───

_PIPER_BIN = '/opt/piper/build/piper' if os.path.exists('/opt/piper/build/piper') else None
_PIPER_MODEL = '/data/models/zh_CN-huayan-medium.onnx'
_PIPER_CONFIG = '/data/models/zh_CN-huayan-medium.onnx.json'

def piper_available():
    return _PIPER_BIN and os.path.exists(_PIPER_BIN) and os.path.exists(_PIPER_MODEL)

def synthesize(text, output_path=None):
    """Piper TTS 文字转语音（需先编译 piper_wrapper.cpp）"""
    if not piper_available():
        raise RuntimeError('Piper TTS not available; need to build piper_wrapper.cpp')
    if output_path is None:
        output_path = tempfile.mktemp(suffix='.wav')
    cmd = [_PIPER_BIN, '--model', _PIPER_MODEL, '--output-file', output_path]
    if os.path.exists(_PIPER_CONFIG):
        cmd += ['--config', _PIPER_CONFIG]
    subprocess.run(cmd, input=text, capture_output=True, text=True, timeout=60, check=True)
    return output_path
