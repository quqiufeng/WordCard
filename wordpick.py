"""wordpick — C++ 智能词汇选择（libwordpick.so）

从电子书正文中挑选"最值得学习"的英文单词。
  · 偏态难度曲线（简单侧陡衰减）
  · 书内词频 + 散布度
  · 构词能产性分级
  · 词形还原合并
  · CEFR 分级预设 + 覆盖率模式
"""

import ctypes, os
from ctypes import c_char_p, c_float, c_int, c_void_p, Structure

_ROOT = os.path.dirname(os.path.abspath(__file__))
_FREQ = os.path.join(_ROOT, 'src', 'wordpick', 'en_freq.tsv')
_LIB = None

class WPWord(Structure):
    _fields_ = [
        ('word', ctypes.c_char * 48),
        ('context', ctypes.c_char * 256),
        ('score', c_float),
        ('zipf', c_float),
        ('count', c_int),
        ('level', c_int),
    ]

class WPConfig(Structure):
    _fields_ = [
        ('max_words', c_int),
        ('target_zipf', c_float),
        ('min_len', c_int),
        ('mode', c_int),
        ('level', c_int),
        ('known_zipf', c_float),
        ('coverage_weight', c_float),
    ]

def _load():
    global _LIB
    if _LIB is not None:
        return _LIB
    path = os.path.join(_ROOT, 'src', 'libwordpick.so')
    if not os.path.exists(path):
        return None
    _LIB = ctypes.CDLL(path)
    _LIB.wp_create.argtypes = [c_char_p]
    _LIB.wp_create.restype = c_void_p
    _LIB.wp_select.argtypes = [c_void_p, c_char_p, c_int, c_float, c_int,
                               ctypes.POINTER(WPWord), c_int]
    _LIB.wp_select.restype = c_int
    _LIB.wp_select_ex.argtypes = [c_void_p, c_char_p, ctypes.POINTER(WPConfig),
                                  ctypes.POINTER(WPWord), c_int]
    _LIB.wp_select_ex.restype = c_int
    _LIB.wp_destroy.argtypes = [c_void_p]
    _LIB.wp_destroy.restype = None
    return _LIB

def available():
    return _load() is not None and os.path.exists(_FREQ)

# CEFR 名称
CEFR_NAMES = {1: 'A1', 2: 'A2', 3: 'B1', 4: 'B2', 5: 'C1', 6: 'C2'}

def select(text, max_words=50, target_zipf=3.8, min_len=5,
           mode=0, level=0, known_zipf=5.0, coverage_weight=0.5):
    """返回 [(word, context, score, zipf, count, level), ...]

    mode: 用 coverage_weight 控制（兼容保留）
    level: CEFR 1..6 (A1..C2)，非 0 时覆盖 target_zipf
    known_zipf: 学习者已知词阈值（高于此视为已会，剔除）
    coverage_weight: α∈[0,1] 覆盖率权重（0=学习价值, 1=覆盖率, 默认0.5）
    """
    lib = _load()
    if not lib:
        raise RuntimeError('libwordpick.so not found; build: cd src && make wordpick')
    handle = lib.wp_create(_FREQ.encode('utf-8'))
    if not handle:
        raise RuntimeError(f'cannot load frequency table: {_FREQ}')
    try:
        cfg = WPConfig(max_words, float(target_zipf), min_len, mode, level,
                       float(known_zipf), float(coverage_weight))
        out = (WPWord * max_words)()
        n = lib.wp_select_ex(handle, text.encode('utf-8'), ctypes.byref(cfg), out, max_words)
        return [(out[i].word.decode('utf-8'), out[i].context.decode('utf-8'),
                 out[i].score, out[i].zipf, out[i].count, out[i].level)
                for i in range(n)]
    finally:
        lib.wp_destroy(handle)
