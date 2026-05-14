#!/usr/bin/env python3
"""
WordCard 语音系统集成模块
基于现有 SenseVoice (ASR) 和 Piper (TTS) 共享库
"""
import os
import sys
import ctypes
import tempfile
import subprocess
import re
from pathlib import Path

# ========================================================================
# 配置路径（从现有系统复用）
# ========================================================================

# SenseVoice 配置（优先环境变量，其次默认值）
SENSEVOICE_SO = os.environ.get("SENSEVOICE_SO", os.path.expanduser("~/my-agent/libs/libsensevoice.so"))
SENSEVOICE_MODEL = os.environ.get("SENSEVOICE_MODEL", "/opt/sensevoice-model/sensevoice-small-encoder-int8-llm-f16.gguf")
SENSEVOICE_GGML_PATH = os.environ.get("SENSEVOICE_GGML_PATH", "/opt/sensevoice-model")

# Piper TTS 配置（优先环境变量，其次默认值）
PIPER_LIB = os.environ.get("PIPER_LIB", "/opt/piper-src/build/libpiper_tts.so")
PIPER_MODEL_PATH = os.environ.get("PIPER_MODEL_PATH", "/opt/piper-voices/en_US-lessac-medium.onnx")
PIPER_MODEL_CONFIG = os.environ.get("PIPER_MODEL_CONFIG", "/opt/piper-voices/en_US-lessac-medium.onnx.json")
PIPER_ESPEAK_DATA = os.environ.get("PIPER_ESPEAK_DATA", "/usr/share/espeak-ng-data")

# ========================================================================
# ASR (自动语音识别) - SenseVoice
# ========================================================================

class ASR:
    """语音识别：音频 → 文本"""
    
    def __init__(self):
        self._lib = None
        self._ctx = None
        self._loaded = False
    
    def _load_library(self):
        """加载 SenseVoice 共享库"""
        if self._lib is not None:
            return self._lib
        
        if not os.path.exists(SENSEVOICE_SO):
            print(f"Warning: SenseVoice library not found at {SENSEVOICE_SO}")
            print("ASR functionality disabled.")
            return None
        
        # 设置库搜索路径
        os.environ.setdefault("LD_LIBRARY_PATH", "")
        if SENSEVOICE_GGML_PATH not in os.environ["LD_LIBRARY_PATH"]:
            os.environ["LD_LIBRARY_PATH"] = f"{SENSEVOICE_GGML_PATH}:{os.environ['LD_LIBRARY_PATH']}".rstrip(":")
        
        try:
            self._lib = ctypes.CDLL(SENSEVOICE_SO)
            
            # 定义函数签名
            self._lib.sensevoice_load_model.argtypes = [ctypes.c_char_p, ctypes.c_int]
            self._lib.sensevoice_load_model.restype = ctypes.c_void_p
            
            self._lib.sensevoice_recognize.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_int]
            self._lib.sensevoice_recognize.restype = ctypes.c_char_p
            
            self._lib.sensevoice_free_text.argtypes = [ctypes.c_char_p]
            self._lib.sensevoice_free_text.restype = None
            
            self._lib.sensevoice_free_model.argtypes = [ctypes.c_void_p]
            self._lib.sensevoice_free_model.restype = None
            
            return self._lib
        except Exception as e:
            print(f"Error loading SenseVoice library: {e}")
            return None
    
    def _load_model(self):
        """加载模型（常驻内存）"""
        if self._ctx is not None:
            return self._ctx
        
        if not os.path.exists(SENSEVOICE_MODEL):
            print(f"Warning: SenseVoice model not found at {SENSEVOICE_MODEL}")
            return None
        
        lib = self._load_library()
        if not lib:
            return None
        
        try:
            print(f"[SenseVoice] Loading model...")
            self._ctx = lib.sensevoice_load_model(SENSEVOICE_MODEL.encode("utf-8"), 4)
            if not self._ctx:
                print("Model loading failed")
                return None
            print("[SenseVoice] Model loaded successfully")
            self._loaded = True
            return self._ctx
        except Exception as e:
            print(f"Error loading model: {e}")
            return None
    
    @staticmethod
    def _convert_to_wav(input_path: str, output_path: str) -> bool:
        """将音频文件转换为 16kHz 单声道 WAV 格式"""
        try:
            cmd = [
                "ffmpeg", "-y", "-i", input_path,
                "-ar", "16000", "-ac", "1",
                "-c:a", "pcm_s16le",
                output_path
            ]
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
            return result.returncode == 0
        except Exception as e:
            print(f"ffmpeg conversion error: {e}")
            return False
    
    @staticmethod
    def _parse_output(output: str) -> str:
        """解析 SenseVoice 输出，移除标签"""
        text = re.sub(r"<\|[a-z_]+\|>", "", output)
        return text.strip()
    
    def recognize(self, audio_path: str) -> str:
        """
        识别音频文件，返回文本
        
        Args:
            audio_path: 音频文件路径（支持 amr/wav/mp3 等）
        
        Returns:
            识别出的文本，失败返回空字符串
        """
        if not os.path.exists(audio_path):
            print(f"Audio file not found: {audio_path}")
            return ""
        
        ctx = self._load_model()
        if not ctx:
            return ""
        
        # 检查是否已经是 16kHz WAV
        is_wav = audio_path.lower().endswith(".wav")
        wav_path = audio_path
        temp_wav = None
        
        if not is_wav:
            temp_wav = tempfile.mktemp(suffix=".wav")
            if not self._convert_to_wav(audio_path, temp_wav):
                return ""
            wav_path = temp_wav
        
        try:
            text_ptr = self._lib.sensevoice_recognize(ctx, wav_path.encode("utf-8"), 4)
            if not text_ptr:
                return ""
            
            text = ctypes.string_at(text_ptr).decode("utf-8", errors="ignore")
            self._lib.sensevoice_free_text(text_ptr)
            
            return self._parse_output(text)
        except Exception as e:
            print(f"Recognition error: {e}")
            return ""
        finally:
            if temp_wav and os.path.exists(temp_wav):
                try:
                    os.unlink(temp_wav)
                except Exception:
                    pass
    
    def recognize_from_url(self, download_url: str, temp_dir: str = "/tmp/wordcard_voice") -> str:
        """从 URL 下载音频并识别"""
        import requests
        
        os.makedirs(temp_dir, exist_ok=True)
        
        try:
            resp = requests.get(download_url, timeout=60)
            if resp.status_code != 200:
                return ""
            
            temp_path = os.path.join(temp_dir, f"voice_{os.getpid()}.amr")
            with open(temp_path, "wb") as f:
                f.write(resp.content)
            
            text = self.recognize(temp_path)
            
            try:
                os.unlink(temp_path)
            except Exception:
                pass
            
            return text
        except Exception as e:
            print(f"Download error: {e}")
            return ""
    
    def cleanup(self):
        """释放模型资源"""
        if self._ctx is not None and self._lib is not None:
            self._lib.sensevoice_free_model(self._ctx)
            self._ctx = None


# ========================================================================
# TTS (文本转语音) - Piper
# ========================================================================

class TTS:
    """语音合成：文本 → 音频"""
    
    def __init__(self):
        self._lib = None
        self._voice = None
        self._loaded = False
    
    def _load_library(self):
        """加载 Piper TTS 共享库"""
        if self._lib is not None:
            return self._lib
        
        if not os.path.exists(PIPER_LIB):
            print(f"Warning: Piper library not found at {PIPER_LIB}")
            print("TTS functionality disabled.")
            return None
        
        try:
            self._lib = ctypes.CDLL(PIPER_LIB)
            
            self._lib.piper_initialize.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
            self._lib.piper_initialize.restype = ctypes.c_int
            
            self._lib.piper_load_voice.argtypes = [
                ctypes.c_char_p, ctypes.c_char_p, ctypes.c_int64, ctypes.c_int
            ]
            self._lib.piper_load_voice.restype = ctypes.c_void_p
            
            self._lib.piper_synthesize_to_file.argtypes = [
                ctypes.c_void_p, ctypes.c_char_p, ctypes.c_char_p
            ]
            self._lib.piper_synthesize_to_file.restype = ctypes.c_int
            
            self._lib.piper_free_voice.argtypes = [ctypes.c_void_p]
            self._lib.piper_free_voice.restype = None
            
            self._lib.piper_terminate.argtypes = []
            self._lib.piper_terminate.restype = None
            
            return self._lib
        except Exception as e:
            print(f"Error loading Piper library: {e}")
            return None
    
    def _initialize(self):
        """初始化 Piper TTS 引擎"""
        if self._voice is not None:
            return True
        
        lib = self._load_library()
        if not lib:
            return False
        
        try:
            # 初始化引擎
            espeak_path = PIPER_ESPEAK_DATA.encode("utf-8")
            result = lib.piper_initialize(espeak_path, None)
            if result != 0:
                print("Piper initialization failed")
                return False
            
            # 加载语音模型
            if not os.path.exists(PIPER_MODEL_PATH):
                print(f"Model not found: {PIPER_MODEL_PATH}")
                return False
            
            self._voice = lib.piper_load_voice(
                PIPER_MODEL_PATH.encode("utf-8"),
                PIPER_MODEL_CONFIG.encode("utf-8"),
                -1,  # 默认说话人
                0,   # 不使用 CUDA
            )
            if not self._voice:
                print("Voice model loading failed")
                return False
            
            self._loaded = True
            return True
        except Exception as e:
            print(f"TTS initialization error: {e}")
            return False
    
    def synthesize(self, text: str, output_path: str = None) -> str:
        """
        将文本转为语音
        
        Args:
            text: 要转换的文本
            output_path: 输出文件路径，默认 /tmp/wordcard_tts_<timestamp>.wav
        
        Returns:
            生成的音频文件路径，失败返回空字符串
        """
        if not text or not text.strip():
            return ""
        
        if not self._initialize():
            return ""
        
        if output_path is None:
            import time
            output_path = f"/tmp/wordcard_tts_{int(time.time())}.wav"
        
        try:
            result = self._lib.piper_synthesize_to_file(
                self._voice,
                text.strip().encode("utf-8"),
                output_path.encode("utf-8"),
            )
            
            if result == 0 and os.path.exists(output_path):
                return output_path
            return ""
        except Exception as e:
            print(f"Synthesis error: {e}")
            return ""
    
    def cleanup(self):
        """释放资源"""
        if self._voice is not None and self._lib is not None:
            self._lib.piper_free_voice(self._voice)
            self._voice = None
        if self._lib is not None:
            self._lib.piper_terminate()


# ========================================================================
# 发音评分
# ========================================================================

def pronunciation_score(user_text: str, standard_text: str) -> int:
    """
    简单发音评分：对比用户识别结果和标准文本的相似度
    
    Returns:
        0-100 的分数
    """
    if not user_text or not standard_text:
        return 0
    
    user_words = set(user_text.lower().split())
    standard_words = set(standard_text.lower().split())
    
    if not standard_words:
        return 0
    
    intersection = user_words & standard_words
    score = int(len(intersection) / len(standard_words) * 100)
    
    return min(100, score)


# ========================================================================
# 全局实例
# ========================================================================

_asr = None
_tts = None

def get_asr() -> ASR:
    global _asr
    if _asr is None:
        _asr = ASR()
    return _asr

def get_tts() -> TTS:
    global _tts
    if _tts is None:
        _tts = TTS()
    return _tts


# ========================================================================
# 测试
# ========================================================================

if __name__ == "__main__":
    print("=== WordCard Voice System Test ===\n")
    
    # 测试 ASR
    print("1. ASR (Speech Recognition)")
    asr = get_asr()
    print(f"   Library: {SENSEVOICE_SO}")
    print(f"   Model: {SENSEVOICE_MODEL}")
    print(f"   Loaded: {asr._loaded}")
    
    # 测试 TTS
    print("\n2. TTS (Text to Speech)")
    tts = get_tts()
    print(f"   Library: {PIPER_LIB}")
    print(f"   Model: {PIPER_MODEL_PATH}")
    print(f"   Loaded: {tts._loaded}")
    
    # 测试发音评分
    print("\n3. Pronunciation Scoring")
    score = pronunciation_score("hello world", "hello world")
    print(f"   'hello world' vs 'hello world' = {score}")
    score = pronunciation_score("hello", "hello world")
    print(f"   'hello' vs 'hello world' = {score}")
    
    print("\n=== Test Complete ===")
