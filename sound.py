"""Audio recording, playback and conversion utilities."""

import subprocess, os, tempfile, wave

def play_wav(path):
    """Play a WAV file using aplay."""
    subprocess.run(['aplay', path], check=False)

def record_wav(path, duration=3, rate=16000):
    """Record audio to WAV using ffmpeg."""
    subprocess.run([
        'ffmpeg', '-y', '-f', 'alsa', '-i', 'default',
        '-ar', str(rate), '-ac', '1', '-c:a', 'pcm_s16le',
        '-t', str(duration), path
    ], check=False, capture_output=True)

def convert_to_wav(input_path, output_path=None, rate=16000):
    """Convert any audio to WAV (16kHz mono 16-bit PCM)."""
    if output_path is None:
        output_path = os.path.splitext(input_path)[0] + '.wav'
    subprocess.run([
        'ffmpeg', '-y', '-i', input_path,
        '-ar', str(rate), '-ac', '1', '-c:a', 'pcm_s16le',
        output_path
    ], check=False, capture_output=True)
    return output_path

def get_wav_info(path):
    """Return (sample_rate, channels, frames, duration_sec)."""
    with wave.open(path, 'rb') as w:
        sr = w.getframerate()
        ch = w.getnchannels()
        nf = w.getnframes()
        return sr, ch, nf, nf / sr

def read_wav(path):
    """Read WAV as (sample_rate, samples_float32)."""
    import numpy as np
    with wave.open(path, 'rb') as w:
        sr = w.getframerate()
        frames = w.readframes(w.getnframes())
        dtype = 'int16' if w.getsampwidth() == 2 else 'int32'
        data = np.frombuffer(frames, dtype=dtype).astype(np.float32) / 32768.0
        return sr, data
