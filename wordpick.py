"""wordpick — C++ 智能词汇选择（libwordpick.so）

从电子书正文中挑选"最值得学习"的英文单词：
  · 通用词频 (zipf) 决定难度，学习价值在适中难度处最高
  · 书内词频与分布 → 越相关越靠前
  · 构词能产性 + 长度惩罚
"""

import ctypes, os
from ctypes import c_char_p, c_float, c_int, c_void_p, Structure

_LIB = None
_FREQ = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'src', 'wordpick', 'en_freq.tsv')

class WPWord(Structure):
    _fields_ = [
        ('word', ctypes.c_char * 48),
        ('context', ctypes.c_char * 256),
        ('score', c_float),
        ('zipf', c_float),
        ('count', c_int),
    ]

def _load():
    global _LIB
    if _LIB is not None:
        return _LIB
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'src', 'libwordpick.so')
    if not os.path.exists(path):
        return None
    _LIB = ctypes.CDLL(path)
    _LIB.wp_create.argtypes = [c_char_p]
    _LIB.wp_create.restype = c_void_p
    _LIB.wp_select.argtypes = [c_void_p, c_char_p, c_int, c_float, c_int,
                               ctypes.POINTER(WPWord), c_int]
    _LIB.wp_select.restype = c_int
    _LIB.wp_destroy.argtypes = [c_void_p]
    _LIB.wp_destroy.restype = None
    return _LIB

def available():
    return _load() is not None and os.path.exists(_FREQ)

def select(text, max_words=50, target_zipf=3.8, min_len=5):
    """返回 [(word, context, score, zipf, count), ...]"""
    lib = _load()
    if not lib:
        raise RuntimeError('libwordpick.so not found; build: cd src && make wordpick')
    handle = lib.wp_create(_FREQ.encode('utf-8'))
    if not handle:
        raise RuntimeError(f'cannot load frequency table: {_FREQ}')
    try:
        out = (WPWord * max_words)()
        n = lib.wp_select(handle, text.encode('utf-8'), max_words,
                          float(target_zipf), min_len, out, max_words)
        return [(out[i].word.decode('utf-8'),
                 out[i].context.decode('utf-8'),
                 out[i].score, out[i].zipf, out[i].count) for i in range(n)]
    finally:
        lib.wp_destroy(handle)
