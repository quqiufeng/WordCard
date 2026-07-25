"""TTS (Text-to-Speech) and ASR (Speech-to-Text) via subprocess + ctypes."""

import subprocess, os, tempfile, json

SENSEVOICE_BIN = '/opt/SenseVoice.cpp/build/bin/sense-voice-main'
SENSEVOICE_MODEL = '/data/models/sense-voice-small-q4_k.gguf'

# ── ASR: SenseVoice ─────────────────────────────────────────

def asr_available():
    return os.path.exists(SENSEVOICE_BIN) and os.path.exists(SENSEVOICE_MODEL)

def transcribe(wav_path, lang='auto', n_threads=8):
    """Transcribe WAV file to text using SenseVoice."""
    if not asr_available():
        raise RuntimeError('SenseVoice not available')
    cmd = [SENSEVOICE_BIN, '-m', SENSEVOICE_MODEL, wav_path,
           '-t', str(n_threads), '--use-itn']
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    if r.returncode != 0:
        raise RuntimeError(f'SenseVoice failed: {r.stderr[:200]}')
    text = r.stdout.strip()
    return text

# ── TTS: Piper ──────────────────────────────────────────────

PIPER_BIN = '/opt/piper/build/piper' if os.path.exists('/opt/piper/build/piper') else None
PIPER_MODEL = '/data/models/zh_CN-huayan-medium.onnx'
PIPER_CONFIG = '/data/models/zh_CN-huayan-medium.onnx.json'

def tts_available():
    return PIPER_BIN and os.path.exists(PIPER_BIN) and os.path.exists(PIPER_MODEL)

def synthesize(text, output_path=None, speaker_id=-1):
    """Synthesize text to WAV using Piper."""
    if not tts_available():
        raise RuntimeError('Piper TTS not available')
    if output_path is None:
        output_path = tempfile.mktemp(suffix='.wav')
    cmd = [PIPER_BIN, '--model', PIPER_MODEL, '--output-file', output_path]
    if os.path.exists(PIPER_CONFIG):
        cmd += ['--config', PIPER_CONFIG]
    if speaker_id >= 0:
        cmd += ['--speaker', str(speaker_id)]
    r = subprocess.run(cmd, input=text, capture_output=True, text=True, timeout=60)
    if r.returncode != 0:
        raise RuntimeError(f'Piper TTS failed: {r.stderr[:200]}')
    return output_path

# ── TTS: Edge TTS (fallback, no local model) ────────────────

def tts_edge_available():
    try:
        import edge_tts
        return True
    except ImportError:
        return False

async def synthesize_edge(text, voice='zh-CN-XiaoxiaoNeural', output_path=None):
    """Synthesize text to speech using Edge TTS (free, no local model)."""
    import edge_tts
    if output_path is None:
        output_path = tempfile.mktemp(suffix='.mp3')
    communicate = edge_tts.Communicate(text, voice)
    await communicate.save(output_path)
    return output_path
