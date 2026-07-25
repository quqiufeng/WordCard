"""SM-2 引擎 ctypes 绑定 — libwordcard.so"""

import ctypes, os
from ctypes import (c_char, c_uint8, c_uint16, c_uint32, c_uint64,
                    c_int, c_float, c_size_t, c_char_p, c_void_p,
                    POINTER, Structure, byref, memmove)

_lib = None
_lib_paths = [
    'src/libwordcard.so',
    'src/libwordcard_full.so',
]

def _load():
    global _lib
    if _lib: return _lib
    d = os.path.dirname(os.path.abspath(__file__))
    for p in _lib_paths:
        fp = os.path.join(d, p)
        if os.path.exists(fp):
            _lib = ctypes.CDLL(fp)
            return _lib
    raise RuntimeError(f'libwordcard.so not found in {_lib_paths}')

# ── C 结构体 ──────────────────────────────────────────────────

class ItemEntry(Structure):
    _fields_ = [
        ('id',           c_uint32),
        ('question',     c_char * 512),
        ('answer',       c_char * 512),
        ('explanation',  c_char * 1024),
        ('hint',         c_char * 256),
        ('difficulty',   c_uint8),
        ('source_id',    c_uint32),
        ('category',     c_uint32),
        ('tags',         c_char * 128),
        ('frequency',    c_uint32),
    ]

class ContentSource(Structure):
    _fields_ = [
        ('id',          c_uint32),
        ('type',        c_uint32),
        ('name',        c_char * 128),
        ('file_path',   c_char * 256),
        ('item_start',  c_uint32),
        ('item_count',  c_uint32),
        ('created_at',  c_uint32),
    ]

class User(Structure):
    _fields_ = [
        ('id',               c_uint32),
        ('dingtalk_uid',     c_char * 64),
        ('name',             c_char * 64),
        ('role',             c_uint8),
        ('daily_new_limit',  c_uint16),
        ('daily_review_limit', c_uint16),
        ('created_at',       c_uint32),
        ('last_active',      c_uint32),
    ]

class Mastery(Structure):
    _fields_ = [
        ('user_id',             c_uint32),
        ('item_id',             c_uint32),
        ('sm2_status',          c_uint8),
        ('interval_days',       c_uint16),
        ('repetitions',         c_uint16),
        ('ease_factor',         c_float),
        ('next_review',         c_uint32),
        ('last_review',         c_uint32),
        ('recognition',         c_uint8),
        ('recall',              c_uint8),
        ('spelling',            c_uint8),
        ('listening',           c_uint8),
        ('pronunciation',       c_uint8),
        ('usage',               c_uint8),
        ('overall',             c_uint8),
        ('total_reviews',       c_uint16),
        ('correct_count',       c_uint16),
        ('wrong_count',         c_uint16),
        ('streak_days',         c_uint8),
        ('first_seen',          c_uint32),
        ('last_wrong',          c_uint32),
        ('forget_count',        c_uint8),
        ('is_difficult',        c_uint8),
        ('is_favorite',         c_uint8),
        ('is_banned',           c_uint8),
    ]

class DailyStat(Structure):
    _fields_ = [
        ('user_id',        c_uint32),
        ('date',           c_uint32),
        ('new_items',      c_uint16),
        ('reviewed_items', c_uint16),
        ('mastered_items', c_uint16),
        ('wrong_items',    c_uint16),
        ('study_time_sec', c_uint32),
    ]

# ── 数据库 ────────────────────────────────────────────────────

class WordCardDB:
    def __init__(self):
        self._lib = _load()
        self._lib.wc_db_init.restype = c_void_p
        self._handle = self._lib.wc_db_init()
        if not self._handle:
            raise RuntimeError('wc_db_init failed')

    @classmethod
    def open(cls, path):
        lib = _load()
        lib.wc_load_db.restype = c_void_p
        h = lib.wc_load_db(path.encode('utf-8'))
        if not h:
            db = cls.__new__(cls)
            db._lib = lib
            db._handle = None
            return db.open_new(path)
        db = cls.__new__(cls)
        db._lib = lib
        db._handle = h
        db._dirty = True
        return db

    def open_new(self, path):
        # Already called wc_db_init via cls()
        self._lib.wc_load_db.restype = c_void_p
        h = self._lib.wc_load_db(path.encode('utf-8'))
        if h:
            self._lib.wc_db_free(self._handle)
            self._handle = h
        return self

    def save(self, path=None):
        self._lib.wc_save_db.argtypes = [c_void_p, c_char_p]
        self._lib.wc_save_db.restype = c_int
        return self._lib.wc_save_db(self._handle,
                                     path.encode('utf-8') if path else None)

    def close(self):
        if self._handle:
            self._lib.wc_db_free(self._handle)
            self._handle = None

    def __del__(self):
        self.close()

    # ── 学习项 ────────────────────────────────────────────────

    def add_item(self, question, answer, explanation='', hint='',
                 difficulty=1, category=1, source_id=0, tags=''):
        item = ItemEntry()
        item.question = question.encode('utf-8')[:511]
        item.answer = answer.encode('utf-8')[:511]
        item.explanation = explanation.encode('utf-8')[:1023]
        item.hint = hint.encode('utf-8')[:255]
        item.difficulty = difficulty
        item.category = category
        item.source_id = source_id
        item.tags = tags.encode('utf-8')[:127]
        item.frequency = 0
        self._lib.wc_add_item.argtypes = [c_void_p, POINTER(ItemEntry)]
        self._lib.wc_add_item.restype = c_uint32
        return self._lib.wc_add_item(self._handle, byref(item))

    def find_item(self, question=None, item_id=None):
        if question:
            self._lib.wc_find_item_by_question.argtypes = [c_void_p, c_char_p]
            self._lib.wc_find_item_by_question.restype = POINTER(ItemEntry)
            p = self._lib.wc_find_item_by_question(self._handle,
                                                    question.encode('utf-8'))
            return p.contents if p else None
        if item_id is not None:
            self._lib.wc_find_item_by_id.argtypes = [c_void_p, c_uint32]
            self._lib.wc_find_item_by_id.restype = POINTER(ItemEntry)
            p = self._lib.wc_find_item_by_id(self._handle, item_id)
            return p.contents if p else None
        return None

    # ── 用户 ──────────────────────────────────────────────────

    def create_user(self, dingtalk_uid, name=''):
        self._lib.wc_create_user.argtypes = [c_void_p, c_char_p, c_char_p]
        self._lib.wc_create_user.restype = c_uint32
        return self._lib.wc_create_user(self._handle,
                                         dingtalk_uid.encode('utf-8'),
                                         name.encode('utf-8'))

    def find_user(self, dingtalk_uid=None, user_id=None):
        if dingtalk_uid:
            self._lib.wc_find_user.argtypes = [c_void_p, c_char_p]
            self._lib.wc_find_user.restype = POINTER(User)
            p = self._lib.wc_find_user(self._handle,
                                        dingtalk_uid.encode('utf-8'))
            return p.contents if p else None
        if user_id is not None:
            self._lib.wc_find_user_by_id.argtypes = [c_void_p, c_uint32]
            self._lib.wc_find_user_by_id.restype = POINTER(User)
            p = self._lib.wc_find_user_by_id(self._handle, user_id)
            return p.contents if p else None
        return None

    # ── 掌握度 ────────────────────────────────────────────────

    def get_mastery(self, user_id, item_id):
        self._lib.wc_find_mastery.argtypes = [c_void_p, c_uint32, c_uint32]
        self._lib.wc_find_mastery.restype = POINTER(Mastery)
        p = self._lib.wc_find_mastery(self._handle, user_id, item_id)
        return p.contents if p else None

    def get_or_create_mastery(self, user_id, item_id):
        self._lib.wc_get_or_create_mastery.argtypes = [c_void_p, c_uint32, c_uint32]
        self._lib.wc_get_or_create_mastery.restype = POINTER(Mastery)
        p = self._lib.wc_get_or_create_mastery(self._handle, user_id, item_id)
        return p.contents if p else None

    def sm2_update(self, mastery, quality):
        self._lib.wc_sm2_update.argtypes = [POINTER(Mastery), c_uint8]
        self._lib.wc_sm2_update(mastery, quality)

    def update_dimension(self, mastery, dimension, correct, score=0):
        self._lib.wc_update_mastery_dimension.argtypes = [
            c_void_p, POINTER(Mastery), c_char, c_int, c_uint8]
        self._lib.wc_update_mastery_dimension(
            self._handle, mastery, dimension.encode('utf-8'),
            1 if correct else 0, score)

    # ── 队列 ──────────────────────────────────────────────────

    def get_due_items(self, user_id, now=None, max_count=50):
        if now is None:
            now = int(__import__('time').time())
        ids = (c_uint32 * max_count)()
        self._lib.wc_get_due_items.argtypes = [
            c_void_p, c_uint32, c_uint32, POINTER(c_uint32), c_size_t]
        self._lib.wc_get_due_items.restype = c_size_t
        n = self._lib.wc_get_due_items(self._handle, user_id, now, ids, max_count)
        return list(ids[:n])

    def get_new_items(self, user_id, source_id=0, max_count=20):
        ids = (c_uint32 * max_count)()
        self._lib.wc_get_new_items.argtypes = [
            c_void_p, c_uint32, c_uint32, POINTER(c_uint32), c_size_t]
        self._lib.wc_get_new_items.restype = c_size_t
        n = self._lib.wc_get_new_items(self._handle, user_id, source_id, ids, max_count)
        return list(ids[:n])

    def daily_queue(self, user_id, now=None, max_count=50):
        if now is None:
            now = int(__import__('time').time())
        ids = (c_uint32 * max_count)()
        modes = (c_uint8 * max_count)()
        self._lib.wc_generate_daily_queue.argtypes = [
            c_void_p, c_uint32, c_uint32,
            POINTER(c_uint32), POINTER(c_uint8), c_size_t]
        self._lib.wc_generate_daily_queue.restype = c_size_t
        n = self._lib.wc_generate_daily_queue(self._handle, user_id, now,
                                               ids, modes, max_count)
        return [(ids[i], modes[i]) for i in range(n)]

    # ── 统计 ──────────────────────────────────────────────────

    def record_activity(self, user_id, is_new, is_correct, time_spent=0):
        self._lib.wc_record_activity.argtypes = [c_void_p, c_uint32, c_int, c_int, c_uint32]
        self._lib.wc_record_activity(self._handle, user_id,
                                     1 if is_new else 0,
                                     1 if is_correct else 0,
                                     time_spent)

    # ── 当前时间 ──────────────────────────────────────────────

    @staticmethod
    def now():
        return int(__import__('time').time())

    @staticmethod
    def today():
        import time
        t = time.localtime()
        return t.tm_year * 10000 + t.tm_mon * 100 + t.tm_mday
