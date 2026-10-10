#!/usr/bin/env python3
"""backfill_defs.py — 为缺少中文释义的学习项回填 ECDICT 释义。

修复早期导入（answer 为空）的历史条目。用法:
    python3 tools/backfill_defs.py [db_path]
"""

import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
sys.path.insert(0, os.path.join(ROOT, 'tools'))

import engine      # noqa: E402
import bilingual   # noqa: E402


def main():
    db_path = sys.argv[1] if len(sys.argv) > 1 else 'data/wordcard.db'
    db = engine.WordCardDB.open(db_path)
    items = db.all_items()
    todo = [it for it in items
            if not it.answer.decode('utf-8', 'ignore').strip()]
    print(f'items={len(items)}  缺释义={len(todo)}')
    defs = bilingual.lookup_many(
        [it.question.decode('utf-8', 'ignore') for it in todo])
    n = 0
    for it in todo:
        w = it.question.decode('utf-8', 'ignore')
        d = defs.get(w.lower())
        if not d:
            continue
        _ph, pos, zh, _en = d
        ans = f'{pos} {zh}'.strip() if zh else ''
        if not ans:
            continue
        db.update_item_answer(it.id, ans)
        n += 1
    db.save()
    db.close()
    print(f'回填 {n} 条')


if __name__ == '__main__':
    main()
