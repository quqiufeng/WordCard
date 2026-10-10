#!/usr/bin/env python3
"""ebook_translate.py — 用本地 LLM 翻译物料的**段落与例句**，并生成每词的**用法/场景描述**。

读取 ebook_extract.py 产出的 JSONL 物料，对每个词：
  · 翻译 para / sents（英文→中文，带缓存 data/translate_cache.jsonl）
  · 生成一句中文「使用场景/助记描述」memo（同样缓存）
逐条输出 JSON 并 flush，供 App 动态回填；完成后原地补全物料文件。

用法:
    python3 tools/ebook_translate.py --material data/books/<slug>.jsonl
输出（stdout，每行）:
    {"w":"template","para_zh":"...","sents_zh":["..."],"memo":"一句用法描述"}
进度（stderr）: READY / TRANS i/n
"""

import argparse
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

import bilingual  # noqa: E402


def _stage(msg):
    print(f'STAGE {msg}', file=sys.stderr, flush=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--material', required=True, help='物料 JSONL 路径')
    args = ap.parse_args()

    items = []
    with open(args.material, encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if line:
                items.append(json.loads(line))

    cache = bilingual.load_trans_cache()

    try:
        import translate
        ok = translate.available()
    except Exception as e:  # noqa: BLE001
        ok = False
        translate = None
        _stage(f'LLM 初始化失败: {e}')
    if ok:
        print('READY', file=sys.stderr, flush=True)

    def tr(text):
        if not text:
            return ''
        k = bilingual.trans_key(text)
        if k in cache:
            return cache[k]
        if not ok:
            return ''
        try:
            zh = translate.translate(text)
        except Exception:  # noqa: BLE001
            zh = ''
        if zh:
            cache[k] = zh
            bilingual.append_trans_cache(text, zh)
        return zh

    def memo(word, ctx):
        k = bilingual.trans_key('memo:' + word.lower())
        if k in cache:
            return cache[k]
        if not ok:
            return ''
        try:
            m = translate.memo(word, ctx)
        except Exception:  # noqa: BLE001
            m = ''
        if m:
            cache[k] = m
            bilingual.append_trans_cache('memo:' + word.lower(), m)
        return m

    total = len(items)
    for n, it in enumerate(items, 1):
        para_zh = tr(it.get('para', ''))
        sents_zh = [tr(s) for s in it.get('sents', [])]
        ctx = it.get('para', '') or (it.get('sents') or [''])[0]
        m = memo(it.get('w', ''), ctx)
        it['para_zh'] = para_zh
        it['sents_zh'] = sents_zh
        it['memo'] = m
        print(json.dumps({'w': it.get('w', ''), 'para_zh': para_zh,
                          'sents_zh': sents_zh, 'memo': m},
                         ensure_ascii=False), flush=True)
        print(f'TRANS {n}/{total}', file=sys.stderr, flush=True)

    with open(args.material, 'w', encoding='utf-8') as f:
        for it in items:
            f.write(json.dumps(it, ensure_ascii=False) + '\n')


if __name__ == '__main__':
    main()
