#!/usr/bin/env python3
"""backfill_memo.py — 为学习项批量生成「用法/场景」助记（【用法】…），写入 explanation。

用于词表（CET4/6…）等没有 memo 的条目。结果缓存到 translate_cache，
可重复运行（已生成的跳过）。

用法:
    python3 tools/backfill_memo.py [db_path]
环境变量: WC_MEMO_LIMIT（本次最多处理多少条，默认全部）、WC_MEMO_TAG（仅处理含该 tag 的项）
"""

import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
sys.path.insert(0, os.path.join(ROOT, 'tools'))

import engine      # noqa: E402
import bilingual   # noqa: E402
import translate   # noqa: E402

PREFIX = '【用法】'


def main():
    db_path = sys.argv[1] if len(sys.argv) > 1 else 'data/wordcard.db'
    limit = int(os.environ.get('WC_MEMO_LIMIT', '0')) or None
    tag_filter = os.environ.get('WC_MEMO_TAG')

    db = engine.WordCardDB.open(db_path)
    items = db.all_items()
    todo = []
    for it in items:
        expl = it.explanation.decode('utf-8', 'ignore')
        if expl.startswith(PREFIX):
            continue
        if tag_filter and tag_filter not in it.tags.decode('utf-8', 'ignore'):
            continue
        todo.append(it)
    print(f'items={len(items)}  待生成 memo={len(todo)}')

    if not translate.available():
        print('LLM 不可用')
        db.close()
        return

    cache = bilingual.load_trans_cache()

    def get_memo(word, ctx):
        k = bilingual.trans_key('memo:' + word.lower())
        if k in cache:
            return cache[k]
        m = translate.memo(word, ctx)
        if m:
            cache[k] = m
            bilingual.append_trans_cache('memo:' + word.lower(), m)
        return m

    n = 0
    for it in todo:
        word = it.question.decode('utf-8', 'ignore')
        old = it.explanation.decode('utf-8', 'ignore')
        ctx = old.split('\n')[0][:200]
        m = get_memo(word, ctx)
        if not m:
            continue
        new = (PREFIX + m + '\n' + old)[:1000]
        db.update_item_explanation(it.id, new)
        n += 1
        if n % 20 == 0:
            print(f'  {n}/{len(todo)}', flush=True)
        if limit and n >= limit:
            break
    db.save()
    db.close()
    print(f'完成：写入 {n} 条')


if __name__ == '__main__':
    main()
