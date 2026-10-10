"""store — 基于 my_db KV Cache (mmap 零拷贝) 的记忆存储（libwordcard.so）"""
import ctypes, os
from ctypes import (c_uint8, c_uint16, c_uint32, c_float, c_char,
                    c_char_p, c_int, c_size_t, c_void_p, Structure, POINTER)

_ROOT = os.path.dirname(os.path.abspath(__file__))

class Item(Structure):
    _fields_ = [
        ('id', c_uint32),
        ('question', c_char * 512),
        ('answer', c_char * 512),
        ('explanation', c_char * 1024),
        ('hint', c_char * 256),
        ('tags', c_char * 128),
        ('difficulty', c_uint8),
    ]

class Mem(Structure):
    _fields_ = [
        ('user_id', c_uint32),
        ('item_id', c_uint32),
        ('status', c_uint8),
        ('interval_days', c_uint16),
        ('repetitions', c_uint16),
        ('ef', c_float),
        ('next_review', c_uint32),
        ('last_review', c_uint32),
        ('recognition', c_uint8),
        ('recall', c_uint8),
        ('spelling', c_uint8),
        ('listening', c_uint8),
        ('pronunciation', c_uint8),
        ('usage', c_uint8),
        ('overall', c_uint8),
        ('total_reviews', c_uint16),
        ('correct_count', c_uint16),
        ('wrong_count', c_uint16),
        ('streak_days', c_uint8),
        ('forget_count', c_uint8),
    ]

_lib = None

def _load():
    global _lib
    if _lib is not None:
        return _lib
    for p in ('src/libwordcard.so', 'libwordcard.so'):
        path = os.path.join(_ROOT, p)
        if os.path.exists(path):
            _lib = ctypes.CDLL(path); break
    if _lib is None:
        _lib = ctypes.CDLL('libwordcard.so')
    L = _lib
    L.wc_store_open.argtypes = [c_char_p, c_size_t]; L.wc_store_open.restype = c_void_p
    L.wc_store_close.argtypes = [c_void_p]
    L.wc_store_sync.argtypes = [c_void_p]
    L.wc_store_add_item.argtypes = [c_void_p, POINTER(Item)]; L.wc_store_add_item.restype = c_uint32
    L.wc_store_get_item.argtypes = [c_void_p, c_uint32, POINTER(Item)]; L.wc_store_get_item.restype = c_int
    L.wc_store_find_by_word.argtypes = [c_void_p, c_char_p]; L.wc_store_find_by_word.restype = c_uint32
    L.wc_store_mem_get.argtypes = [c_void_p, c_uint32, c_uint32, POINTER(Mem)]; L.wc_store_mem_get.restype = c_int
    L.wc_store_sm2.argtypes = [c_void_p, c_uint32, c_uint32, c_uint8, POINTER(Mem)]; L.wc_store_sm2.restype = c_int
    L.wc_store_due.argtypes = [c_void_p, c_uint32, c_uint32, POINTER(c_uint32), c_size_t]; L.wc_store_due.restype = c_size_t
    return _lib

class Store:
    def __init__(self, dir_path, max_memory=256 * 1024 * 1024):
        L = _load()
        self._h = L.wc_store_open(dir_path.encode('utf-8'), max_memory)
        if not self._h:
            raise RuntimeError(f'wc_store_open failed: {dir_path}')
    def add_item(self, question, answer='', explanation='', hint='', tags='', difficulty=1):
        it = Item()
        it.question = question.encode('utf-8')[:511]
        it.answer = answer.encode('utf-8')[:511]
        it.explanation = explanation.encode('utf-8')[:1023]
        it.hint = hint.encode('utf-8')[:255]
        it.tags = tags.encode('utf-8')[:127]
        it.difficulty = difficulty
        return _load().wc_store_add_item(self._h, ctypes.byref(it))
    def get_item(self, item_id):
        it = Item()
        if _load().wc_store_get_item(self._h, item_id, ctypes.byref(it)) != 0: return None
        return it
    def find_by_word(self, word):
        return _load().wc_store_find_by_word(self._h, word.encode('utf-8'))
    def mem(self, uid, item_id):
        m = Mem(); _load().wc_store_mem_get(self._h, uid, item_id, ctypes.byref(m)); return m
    def sm2(self, uid, item_id, quality):
        m = Mem(); _load().wc_store_sm2(self._h, uid, item_id, quality, ctypes.byref(m)); return m
    def due(self, uid, now, max_count=200):
        buf = (c_uint32 * max_count)()
        n = _load().wc_store_due(self._h, uid, now, buf, max_count)
        return list(buf[:n])
    def sync(self): return _load().wc_store_sync(self._h)
    def close(self):
        if getattr(self, '_h', None):
            _load().wc_store_close(self._h); self._h = None

if __name__ == '__main__':
    import time
    s = Store('/tmp/opencode/pystore')
    sid = s.add_item('abandon', 'vt. 放弃', 'He abandoned ship.', "ә'bændәn", 'dict:cet4')
    print('id', sid, 'find', s.find_by_word('Abandon'))
    m = s.sm2(1, sid, 5)
    print('sm2 q5 reps', m.repetitions, 'iv', m.interval_days, 'ef', round(m.ef, 2))
    print('due now', s.due(1, int(time.time())))
    print('due+100d', s.due(1, int(time.time()) + 100 * 86400))
    s.close()
