import ctypes
from ctypes import Structure, c_uint32, c_uint16, c_uint8, c_float, c_char, c_char_p, c_size_t, c_int, POINTER, CDLL
from pathlib import Path
import os
import threading
import time
import atexit

# ========================================================================
# C 结构体定义 (ctypes)
# ========================================================================

class ItemEntry(Structure):
    _fields_ = [
        ("id", c_uint32),
        ("question", c_char * 512),
        ("answer", c_char * 512),
        ("explanation", c_char * 1024),
        ("hint", c_char * 256),
        ("difficulty", c_uint8),
        ("source_id", c_uint32),
        ("category", c_uint32),
        ("tags", c_char * 128),
        ("frequency", c_uint32),
    ]

class User(Structure):
    _fields_ = [
        ("id", c_uint32),
        ("dingtalk_uid", c_char * 64),
        ("name", c_char * 64),
        ("role", c_uint8),
        ("daily_new_limit", c_uint16),
        ("daily_review_limit", c_uint16),
        ("created_at", c_uint32),
        ("last_active", c_uint32),
    ]

class UserItemMastery(Structure):
    _fields_ = [
        ("user_id", c_uint32),
        ("item_id", c_uint32),
        ("sm2_status", c_uint8),
        ("interval_days", c_uint16),
        ("repetitions", c_uint16),
        ("ease_factor", c_float),
        ("next_review", c_uint32),
        ("last_review", c_uint32),
        ("recognition", c_uint8),
        ("recall", c_uint8),
        ("spelling", c_uint8),
        ("listening", c_uint8),
        ("pronunciation", c_uint8),
        ("usage", c_uint8),
        ("overall", c_uint8),
        ("total_reviews", c_uint16),
        ("correct_count", c_uint16),
        ("wrong_count", c_uint16),
        ("streak_days", c_uint8),
        ("first_seen", c_uint32),
        ("last_wrong", c_uint32),
        ("forget_count", c_uint8),
        ("is_difficult", c_uint8),
        ("is_favorite", c_uint8),
        ("is_banned", c_uint8),
    ]

class DailyStat(Structure):
    _fields_ = [
        ("user_id", c_uint32),
        ("date", c_uint32),
        ("new_items", c_uint16),
        ("reviewed_items", c_uint16),
        ("mastered_items", c_uint16),
        ("wrong_items", c_uint16),
        ("study_time_sec", c_uint32),
    ]

class ContentSource(Structure):
    _fields_ = [
        ("id", c_uint32),
        ("type", c_uint8),
        ("name", c_char * 128),
        ("file_path", c_char * 256),
        ("item_start", c_uint32),
        ("item_count", c_uint32),
        ("created_at", c_uint32),
    ]

# ========================================================================
# 加载 C 共享库
# ========================================================================

LIB_PATH = Path(__file__).parent / "src" / "libwordcard.so"
_lib = CDLL(str(LIB_PATH))

# 函数签名
_lib.wc_db_init.restype = ctypes.c_void_p
_lib.wc_db_free.argtypes = [ctypes.c_void_p]
_lib.wc_load_db.argtypes = [c_char_p]
_lib.wc_load_db.restype = ctypes.c_void_p
_lib.wc_save_db.argtypes = [ctypes.c_void_p, c_char_p]
_lib.wc_save_db.restype = c_int
_lib.wc_mark_dirty.argtypes = [ctypes.c_void_p]

_lib.wc_add_item.argtypes = [ctypes.c_void_p, POINTER(ItemEntry)]
_lib.wc_add_item.restype = c_uint32
_lib.wc_find_item_by_question.argtypes = [ctypes.c_void_p, c_char_p]
_lib.wc_find_item_by_question.restype = POINTER(ItemEntry)
_lib.wc_find_item_by_id.argtypes = [ctypes.c_void_p, c_uint32]
_lib.wc_find_item_by_id.restype = POINTER(ItemEntry)

_lib.wc_add_source.argtypes = [ctypes.c_void_p, POINTER(ContentSource)]
_lib.wc_add_source.restype = c_uint32
_lib.wc_find_source_by_id.argtypes = [ctypes.c_void_p, c_uint32]
_lib.wc_find_source_by_id.restype = ctypes.c_void_p
_lib.wc_find_source_by_name.argtypes = [ctypes.c_void_p, c_char_p]
_lib.wc_find_source_by_name.restype = ctypes.c_void_p

_lib.wc_create_user.argtypes = [ctypes.c_void_p, c_char_p, c_char_p]
_lib.wc_create_user.restype = c_uint32
_lib.wc_find_user.argtypes = [ctypes.c_void_p, c_char_p]
_lib.wc_find_user.restype = POINTER(User)
_lib.wc_find_user_by_id.argtypes = [ctypes.c_void_p, c_uint32]
_lib.wc_find_user_by_id.restype = POINTER(User)

_lib.wc_get_or_create_mastery.argtypes = [ctypes.c_void_p, c_uint32, c_uint32]
_lib.wc_get_or_create_mastery.restype = POINTER(UserItemMastery)
_lib.wc_find_mastery.argtypes = [ctypes.c_void_p, c_uint32, c_uint32]
_lib.wc_find_mastery.restype = POINTER(UserItemMastery)
_lib.wc_sm2_update.argtypes = [POINTER(UserItemMastery), c_uint8]
_lib.wc_update_mastery_dimension.argtypes = [ctypes.c_void_p, POINTER(UserItemMastery), c_char, c_int, c_uint8]
_lib.wc_recalc_overall.argtypes = [POINTER(UserItemMastery)]

_lib.wc_get_due_items.argtypes = [ctypes.c_void_p, c_uint32, c_uint32, POINTER(c_uint32), c_size_t]
_lib.wc_get_due_items.restype = c_size_t
_lib.wc_get_new_items.argtypes = [ctypes.c_void_p, c_uint32, c_uint32, POINTER(c_uint32), c_size_t]
_lib.wc_get_new_items.restype = c_size_t
_lib.wc_generate_daily_queue.argtypes = [ctypes.c_void_p, c_uint32, c_uint32, POINTER(c_uint32), POINTER(c_uint8), c_size_t]
_lib.wc_generate_daily_queue.restype = c_size_t

_lib.wc_recommend_mode.argtypes = [POINTER(UserItemMastery), c_uint32]
_lib.wc_recommend_mode.restype = c_uint8
_lib.wc_notify_mastery_changed.argtypes = [ctypes.c_void_p]

_lib.wc_get_or_create_daily_stat.argtypes = [ctypes.c_void_p, c_uint32, c_uint32]
_lib.wc_get_or_create_daily_stat.restype = POINTER(DailyStat)
_lib.wc_record_activity.argtypes = [ctypes.c_void_p, c_uint32, c_int, c_int, c_uint32]

_lib.wc_now.restype = c_uint32
_lib.wc_today.restype = c_uint32
_lib.wc_version_string.restype = c_char_p

# ========================================================================
# 数据库管理类
# ========================================================================

class WordCardDB:
    """WordCard 通用学习数据库 Python 封装"""
    
    def __init__(self, db_path: str = "data/wordcard.db"):
        self.db_path = db_path
        self._db = None
        self._save_thread = None
        self._stop_event = threading.Event()
        self._lock = threading.Lock()
        
        # 加载或创建数据库
        if os.path.exists(db_path):
            self._db = _lib.wc_load_db(db_path.encode('utf-8'))
        if not self._db:
            self._db = _lib.wc_db_init()
            os.makedirs(os.path.dirname(db_path), exist_ok=True)
        
        # 启动后台保存线程
        self._start_auto_save()
        atexit.register(self.close)
    
    def _start_auto_save(self):
        def auto_save():
            while not self._stop_event.is_set():
                time.sleep(60)
                if self._db:
                    _lib.wc_save_db(self._db, self.db_path.encode('utf-8'))
        
        self._save_thread = threading.Thread(target=auto_save, daemon=True)
        self._save_thread.start()
    
    def save(self):
        """立即保存到磁盘"""
        with self._lock:
            if self._db:
                return _lib.wc_save_db(self._db, self.db_path.encode('utf-8'))
        return -1
    
    def close(self):
        """关闭数据库，确保保存"""
        if self._db:
            self._stop_event.set()
            if self._save_thread:
                self._save_thread.join(timeout=5)
            _lib.wc_save_db(self._db, self.db_path.encode('utf-8'))
            _lib.wc_db_free(self._db)
            self._db = None
    
    # -------- 学习项操作 --------
    
    def add_item(self, question: str, answer: str, explanation: str = "",
                 hint: str = "", difficulty: int = 1, source_id: int = 0,
                 category: int = 1, tags: str = "") -> int:
        """添加学习项，返回 item_id"""
        entry = ItemEntry()
        entry.question = question.encode('utf-8')[:511]
        entry.answer = answer.encode('utf-8')[:511]
        entry.explanation = explanation.encode('utf-8')[:1023]
        entry.hint = hint.encode('utf-8')[:255]
        entry.difficulty = difficulty
        entry.source_id = source_id
        entry.category = category
        entry.tags = tags.encode('utf-8')[:127]
        
        with self._lock:
            iid = _lib.wc_add_item(self._db, ctypes.byref(entry))
        return iid
    
    def find_item(self, question: str = None, item_id: int = None):
        """查找学习项"""
        if question:
            result = _lib.wc_find_item_by_question(self._db, question.encode('utf-8'))
        elif item_id:
            result = _lib.wc_find_item_by_id(self._db, item_id)
        else:
            return None
        
        if result:
            v = result.contents
            return {
                "id": v.id,
                "question": v.question.decode('utf-8', errors='ignore').strip('\x00'),
                "answer": v.answer.decode('utf-8', errors='ignore').strip('\x00'),
                "explanation": v.explanation.decode('utf-8', errors='ignore').strip('\x00'),
                "hint": v.hint.decode('utf-8', errors='ignore').strip('\x00'),
                "difficulty": v.difficulty,
                "category": v.category,
                "tags": v.tags.decode('utf-8', errors='ignore').strip('\x00'),
            }
        return None
    
    def add_source(self, name: str, source_type: int = 3, file_path: str = "") -> int:
        """添加内容载体，返回 source_id"""
        source = ContentSource()
        source.type = source_type
        source.name = name.encode('utf-8')[:127]
        source.file_path = file_path.encode('utf-8')[:255]
        source.created_at = _lib.wc_now()
        
        with self._lock:
            sid = _lib.wc_add_source(self._db, ctypes.byref(source))
        return sid
    
    # -------- 用户操作 --------
    
    def create_user(self, dingtalk_uid: str, name: str = "") -> int:
        """创建用户，返回 user_id"""
        with self._lock:
            return _lib.wc_create_user(self._db, 
                                        dingtalk_uid.encode('utf-8'),
                                        name.encode('utf-8'))
    
    def find_user(self, dingtalk_uid: str = None, user_id: int = None):
        """查找用户"""
        if dingtalk_uid:
            result = _lib.wc_find_user(self._db, dingtalk_uid.encode('utf-8'))
        elif user_id:
            result = _lib.wc_find_user_by_id(self._db, user_id)
        else:
            return None
        
        if result:
            u = result.contents
            return {
                "id": u.id,
                "dingtalk_uid": u.dingtalk_uid.decode('utf-8', errors='ignore').strip('\x00'),
                "name": u.name.decode('utf-8', errors='ignore').strip('\x00'),
                "daily_new_limit": u.daily_new_limit,
                "daily_review_limit": u.daily_review_limit,
            }
        return None
    
    # -------- 学习操作 --------
    
    def get_mastery(self, user_id: int, item_id: int):
        """获取掌握度"""
        m = _lib.wc_get_or_create_mastery(self._db, user_id, item_id)
        if not m:
            return None
        return self._mastery_to_dict(m.contents)
    
    def review(self, user_id: int, item_id: int, quality: int, 
               dimension: str = None, correct: bool = True, score: int = 0):
        """
        提交复习结果
        quality: 0-5 (SM-2 评级)
        dimension: 'r' recognition, 'c' recall, 's' spelling, 
                   'l' listening, 'p' pronunciation, 'u' usage
        """
        with self._lock:
            m = _lib.wc_get_or_create_mastery(self._db, user_id, item_id)
            if not m:
                return False
            
            # 更新 SM-2
            _lib.wc_sm2_update(m, quality)
            _lib.wc_notify_mastery_changed(self._db)
            
            # 更新维度掌握度
            if dimension:
                _lib.wc_update_mastery_dimension(
                    self._db, m, dimension.encode('utf-8')[0], 
                    1 if correct else 0, score
                )
            
            # 记录活动
            is_new = (m.contents.total_reviews <= 1)
            _lib.wc_record_activity(self._db, user_id, is_new, correct, 10)
            
            return True
    
    def get_daily_queue(self, user_id: int, max_count: int = 50):
        """获取今日学习队列"""
        ids = (c_uint32 * max_count)()
        modes = (c_uint8 * max_count)()
        now = _lib.wc_now()
        
        count = _lib.wc_generate_daily_queue(self._db, user_id, now, ids, modes, max_count)
        
        queue = []
        for i in range(count):
            item = self.find_item(item_id=ids[i])
            if item:
                queue.append({
                    "item_id": ids[i],
                    "question": item["question"],
                    "mode": modes[i],
                    "mode_name": self._mode_name(modes[i]),
                })
        return queue
    
    def recommend_mode(self, user_id: int, item_id: int):
        """推荐学习模式"""
        m = _lib.wc_find_mastery(self._db, user_id, item_id)
        if not m:
            return "flashcard"
        mode = _lib.wc_recommend_mode(m, _lib.wc_now())
        return self._mode_name(mode)
    
    # -------- 内部工具 --------
    
    def _mastery_to_dict(self, m: UserItemMastery):
        return {
            "user_id": m.user_id,
            "item_id": m.item_id,
            "sm2_status": m.sm2_status,
            "interval_days": m.interval_days,
            "repetitions": m.repetitions,
            "ease_factor": m.ease_factor,
            "next_review": m.next_review,
            "recognition": m.recognition,
            "recall": m.recall,
            "spelling": m.spelling,
            "listening": m.listening,
            "pronunciation": m.pronunciation,
            "usage": m.usage,
            "overall": m.overall,
            "total_reviews": m.total_reviews,
            "correct_count": m.correct_count,
            "wrong_count": m.wrong_count,
            "streak_days": m.streak_days,
            "forget_count": m.forget_count,
        }
    
    def _mode_name(self, mode: int) -> str:
        names = {
            1: "flashcard", 2: "choice", 3: "fillblank",
            4: "spelling", 5: "dictation", 6: "pronunciation",
            7: "matching", 8: "speed_review",
        }
        return names.get(mode, "unknown")


# ========================================================================
# 全局数据库实例（单例 + 线程安全）
# ========================================================================

_db_instance = None
_db_lock = threading.Lock()


def get_db(db_path: str = "data/wordcard.db") -> WordCardDB:
    global _db_instance
    with _db_lock:
        if _db_instance is None:
            _db_instance = WordCardDB(db_path)
        return _db_instance

# ========================================================================
# FastAPI HTTP 服务
# ========================================================================

try:
    from fastapi import FastAPI, HTTPException, Query
    from fastapi.responses import JSONResponse
    from pydantic import BaseModel, Field
    from typing import List, Optional
    from enum import Enum
    import uvicorn
    FASTAPI_AVAILABLE = True
except ImportError:
    FASTAPI_AVAILABLE = False
    print("Warning: FastAPI not installed. HTTP API disabled.")
    print("Install with: pip install fastapi uvicorn pydantic")

if FASTAPI_AVAILABLE:
    app = FastAPI(
        title="WordCard Universal API",
        description="基于记忆曲线的通用学习系统（支持英语/司法/雅思/GRE等）",
        version="3.0.0"
    )
    
    # -------- 请求/响应模型 --------
    
    class UserRegister(BaseModel):
        dingtalk_uid: str = Field(..., min_length=1, max_length=63)
        name: Optional[str] = Field("", max_length=63)
    
    class ItemAdd(BaseModel):
        question: str = Field(..., min_length=1, max_length=511)
        answer: str = Field(..., max_length=511)
        explanation: Optional[str] = Field("", max_length=1023)
        hint: Optional[str] = Field("", max_length=255)
        difficulty: Optional[int] = Field(1, ge=1, le=5)
        category: Optional[int] = Field(1, ge=1, le=99)
        tags: Optional[str] = Field("", max_length=127)
    
    class ReviewSubmit(BaseModel):
        user_id: int
        item_id: int
        quality: int = Field(..., ge=0, le=5, description="SM-2 评级: 0=完全忘记, 5=完美回忆")
        dimension: Optional[str] = Field(None, pattern="^[rcslpu]$", description="维度: r=识别 c=回忆 s=复现 l=听辨 p=表达 u=应用")
        correct: Optional[bool] = True
        score: Optional[int] = Field(0, ge=0, le=100)
    
    class ModeResponse(BaseModel):
        item_id: int
        question: str
        mode: int
        mode_name: str
    
    class MasteryResponse(BaseModel):
        user_id: int
        item_id: int
        overall: int
        recognition: int
        recall: int
        spelling: int
        listening: int
        pronunciation: int
        usage: int
        ease_factor: float
        interval_days: int
        repetitions: int
        streak_days: int
        forget_count: int
        total_reviews: int
    
    # -------- 全局数据库实例 --------
    
    _api_db = None
    _api_db_lock = threading.Lock()
    
    def get_api_db():
        global _api_db
        with _api_db_lock:
            if _api_db is None:
                _api_db = get_db("data/wordcard.db")
            return _api_db
    
    # -------- API 端点 --------
    
    @app.get("/")
    async def root():
        return {
            "name": "WordCard Universal API",
            "version": "3.0.0",
            "status": "running",
            "features": ["spaced-repetition", "multi-dimensional-mastery", "smart-recommendation", "universal-learning"]
        }
    
    @app.post("/api/v1/user/register")
    async def register_user(req: UserRegister):
        """注册用户"""
        db = get_api_db()
        user_id = db.create_user(req.dingtalk_uid, req.name)
        if user_id == 0:
            raise HTTPException(status_code=409, detail="User already exists")
        return {"user_id": user_id, "dingtalk_uid": req.dingtalk_uid}
    
    @app.get("/api/v1/user/{user_id}")
    async def get_user(user_id: int):
        """获取用户信息"""
        db = get_api_db()
        user = db.find_user(user_id=user_id)
        if not user:
            raise HTTPException(status_code=404, detail="User not found")
        return user
    
    @app.get("/api/v1/user/{user_id}/stats")
    async def get_user_stats(user_id: int):
        """获取用户学习统计"""
        db = get_api_db()
        user = db.find_user(user_id=user_id)
        if not user:
            raise HTTPException(status_code=404, detail="User not found")
        
        from ctypes import c_uint32
        today = _lib.wc_today()
        stat_ptr = _lib.wc_get_or_create_daily_stat(db._db, user_id, today)
        
        stats = {
            "user_id": user_id,
            "daily_new_limit": user["daily_new_limit"],
            "daily_review_limit": user["daily_review_limit"],
        }
        
        if stat_ptr:
            s = stat_ptr.contents
            stats["today"] = {
                "date": s.date,
                "new_items": s.new_items,
                "reviewed_items": s.reviewed_items,
                "mastered_items": s.mastered_items,
                "wrong_items": s.wrong_items,
                "study_time_sec": s.study_time_sec,
            }
        
        return stats
    
    @app.get("/api/v1/user/{user_id}/daily-queue")
    async def get_daily_queue(user_id: int, count: int = Query(50, ge=1, le=200)):
        """获取今日学习队列"""
        db = get_api_db()
        user = db.find_user(user_id=user_id)
        if not user:
            raise HTTPException(status_code=404, detail="User not found")
        
        queue = db.get_daily_queue(user_id, count)
        return {
            "user_id": user_id,
            "count": len(queue),
            "queue": queue
        }
    
    @app.post("/api/v1/item")
    async def add_item_endpoint(req: ItemAdd):
        """添加学习项"""
        db = get_api_db()
        item_id = db.add_item(
            req.question, req.answer, req.explanation, req.hint,
            req.difficulty, 0, req.category, req.tags
        )
        if item_id == 0:
            raise HTTPException(status_code=409, detail="Item already exists")
        return {"item_id": item_id, "question": req.question}
    
    @app.get("/api/v1/item/{item_id}")
    async def get_item(item_id: int):
        """查询学习项详情"""
        db = get_api_db()
        item = db.find_item(item_id=item_id)
        if not item:
            raise HTTPException(status_code=404, detail="Item not found")
        return item
    
    @app.get("/api/v1/item/search/{question}")
    async def search_item(question: str):
        """按问题文本搜索"""
        db = get_api_db()
        item = db.find_item(question=question)
        if not item:
            raise HTTPException(status_code=404, detail="Item not found")
        return item
    
    @app.get("/api/v1/mastery/{user_id}/{item_id}")
    async def get_mastery(user_id: int, item_id: int):
        """获取用户对某学习项的掌握度"""
        db = get_api_db()
        mastery = db.get_mastery(user_id, item_id)
        if not mastery:
            raise HTTPException(status_code=404, detail="Mastery record not found")
        return mastery
    
    @app.post("/api/v1/study/review")
    async def submit_review(req: ReviewSubmit):
        """提交复习结果"""
        db = get_api_db()
        success = db.review(
            req.user_id, req.item_id, req.quality,
            req.dimension, req.correct, req.score
        )
        if not success:
            raise HTTPException(status_code=400, detail="Review failed")
        
        mastery = db.get_mastery(req.user_id, req.item_id)
        return {
            "success": True,
            "mastery": mastery,
            "recommended_next_mode": db.recommend_mode(req.user_id, req.item_id)
        }
    
    @app.get("/api/v1/study/recommend/{user_id}/{item_id}")
    async def recommend_study_mode(user_id: int, item_id: int):
        """获取推荐的学习模式"""
        db = get_api_db()
        mode_name = db.recommend_mode(user_id, item_id)
        return {
            "user_id": user_id,
            "item_id": item_id,
            "recommended_mode": mode_name
        }
    
    @app.post("/api/v1/db/save")
    async def force_save():
        """强制保存数据库到磁盘"""
        db = get_api_db()
        result = db.save()
        return {"saved": result == 0, "path": db.db_path}


# ========================================================================
# 启动入口
# ========================================================================

def main():
    """启动 HTTP 服务"""
    if not FASTAPI_AVAILABLE:
        print("Error: FastAPI is required. Install with: pip install fastapi uvicorn")
        return
    
    # 预加载数据库
    db = get_db("data/wordcard.db")
    print(f"Database loaded: {db.db_path}")
    
    uvicorn.run(app, host="0.0.0.0", port=8000, log_level="info")

if __name__ == "__main__":
    main()
