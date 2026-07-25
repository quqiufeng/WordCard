"""WordCard REST API — FastAPI"""

import os, sys
sys.path.insert(0, os.path.dirname(__file__) or '.')
import engine, importer
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import Optional

app = FastAPI(title='WordCard', version='4.0')

# ── Models ─────────────────────────────────────────────────

class ImportReq(BaseModel):
    book_path: str

class UserCreate(BaseModel):
    dingtalk_uid: str
    name: str = ''

class ItemCreate(BaseModel):
    question: str
    answer: str = ''
    explanation: str = ''
    source_id: int = 0

class ReviewReq(BaseModel):
    user_id: int
    item_id: int
    quality: int  # 0-5

# ── Dependencies ───────────────────────────────────────────

def get_db():
    db = engine.WordCardDB.open('data/wordcard.db')
    try:
        yield db
    finally:
        db.close()

# ── Routes ─────────────────────────────────────────────────

@app.get('/')
def root():
    return {'service': 'WordCard', 'version': '4.0'}

@app.post('/api/v1/user')
def create_user(req: UserCreate):
    db = engine.WordCardDB.open('data/wordcard.db')
    try:
        uid = db.create_user(req.dingtalk_uid, req.name)
        if not uid:
            existing = db.find_user(dingtalk_uid=req.dingtalk_uid)
            if existing:
                return {'user_id': existing.id, 'name': existing.name.decode('utf-8')}
            raise HTTPException(400, 'User exists')
        db.save()
        return {'user_id': uid}
    finally:
        db.close()

@app.get('/api/v1/user/{uid}')
def get_user(uid: int):
    db = engine.WordCardDB.open('data/wordcard.db')
    try:
        u = db.find_user(user_id=uid)
        if not u:
            raise HTTPException(404, 'User not found')
        return {
            'id': u.id, 'name': u.name.decode('utf-8'),
            'daily_new_limit': u.daily_new_limit,
            'daily_review_limit': u.daily_review_limit,
            'created_at': u.created_at,
        }
    finally:
        db.close()

@app.post('/api/v1/item')
def create_item(req: ItemCreate):
    db = engine.WordCardDB.open('data/wordcard.db')
    try:
        item_id = db.add_item(req.question, req.answer, req.explanation,
                               source_id=req.source_id)
        if not item_id:
            existing = db.find_item(question=req.question)
            if existing:
                return {'item_id': existing.id}
            raise HTTPException(400, 'Failed to add')
        db.save()
        return {'item_id': item_id}
    finally:
        db.close()

@app.get('/api/v1/item/{item_id}')
def get_item(item_id: int):
    db = engine.WordCardDB.open('data/wordcard.db')
    try:
        item = db.find_item(item_id=item_id)
        if not item:
            raise HTTPException(404)
        return {
            'id': item.id,
            'question': item.question.decode('utf-8'),
            'answer': item.answer.decode('utf-8'),
            'explanation': item.explanation.decode('utf-8'),
        }
    finally:
        db.close()

@app.post('/api/v1/review')
def submit_review(req: ReviewReq):
    db = engine.WordCardDB.open('data/wordcard.db')
    try:
        m = db.find_mastery(req.user_id, req.item_id)
        if not m:
            m = db.get_or_create_mastery(req.user_id, req.item_id)
        db.sm2_update(m, req.quality)
        db.record_activity(req.user_id, False, req.quality >= 3, 5)
        db.save()
        return {
            'next_review': m.next_review,
            'interval_days': m.interval_days,
            'repetitions': m.repetitions,
            'ease_factor': m.ease_factor,
            'overall': m.overall,
        }
    finally:
        db.close()

@app.get('/api/v1/queue/{user_id}')
def get_queue(user_id: int, max_count: int = 20):
    db = engine.WordCardDB.open('data/wordcard.db')
    try:
        now = engine.WordCardDB.now()
        queue = db.daily_queue(user_id, now, max_count)
        items = []
        for item_id, mode in queue:
            item = db.find_item(item_id=item_id)
            if item:
                items.append({
                    'item_id': item_id,
                    'question': item.question.decode('utf-8'),
                    'mode': mode,
                })
        return {'items': items, 'total': len(items)}
    finally:
        db.close()

@app.post('/api/v1/import')
def import_book(req: ImportReq):
    try:
        count = importer.import_book(req.book_path)
        return {'added': count}
    except Exception as e:
        raise HTTPException(400, str(e))

@app.get('/api/v1/stats/{user_id}')
def get_stats(user_id: int):
    db = engine.WordCardDB.open('data/wordcard.db')
    try:
        now = engine.WordCardDB.now()
        due = db.get_due_items(user_id, now, 9999)
        new = db.get_new_items(user_id, 0, 9999)
        return {
            'user_id': user_id,
            'due_review': len(due),
            'new_available': len(new),
        }
    finally:
        db.close()

if __name__ == '__main__':
    import uvicorn
    uvicorn.run(app, host='0.0.0.0', port=8000)
