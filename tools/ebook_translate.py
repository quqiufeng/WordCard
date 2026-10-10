#!/usr/bin/env python3
"""ebook_translate.py — 用本地 LLM 翻译物料的**段落与例句**（词义走 ECDICT，不在此）。

读取 ebook_extract.py 产出的 JSONL 物料，对每个词的 para / sents 调用
translate.translate（带缓存），逐条输出结果并 flush，供 App 动态回填；
全部完成后把物料 JSONL 原地补全（para_zh / sents_zh），供下次直接加载。

用法:
    python3 tools/ebook_translate.py --material data/books/<slug>.jsonl
输出（stdout，每行）:
    {"w": "template", "para_zh": "...", "sents_zh": ["...", "..."]}
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


def _tr(text, cache, translate):
    if not text:
        return ''
    k = bilingual.trans_key(text)
    if k in cache:
        return cache[k]
    try:
        zh = translate.translate(text)
    except Exception:  # noqa: BLE001
        zh = ''
    if zh:
        cache[k] = zh
        bilingual.append_trans_cache(text, zh)
    return zh


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

    # 需要翻译的文本
    todo = []
    for it in items:
        for t in [it.get('para', '')] + list(it.get('sents', [])):
            if t and bilingual.trans_key(t) not in cache:
                todo.append(t)
    if todo:
        try:
            import translate
            ok = translate.available()
        except Exception as e:  # noqa: BLE001
            ok = False
            _stage(f'LLM 初始化失败: {e}')
        if not ok:
            _stage('LLM 不可用')
            return
        print('READY', file=sys.stderr, flush=True)

    total = len(items)
    for n, it in enumerate(items, 1):
        para_zh = _tr(it.get('para', ''), cache, translate) if todo else \
            cache.get(bilingual.trans_key(it.get('para', '')), '')
        sents_zh = []
        for s in it.get('sents', []):
            if todo:
                sents_zh.append(_tr(s, cache, translate))
            else:
                sents_zh.append(cache.get(bilingual.trans_key(s), ''))
        it['para_zh'] = para_zh
        it['sents_zh'] = sents_zh
        print(json.dumps({'w': it.get('w', ''), 'para_zh': para_zh,
                          'sents_zh': sents_zh}, ensure_ascii=False),
              flush=True)
        print(f'TRANS {n}/{total}', file=sys.stderr, flush=True)

    # 原地补全物料文件
    with open(args.material, 'w', encoding='utf-8') as f:
        for it in items:
            f.write(json.dumps(it, ensure_ascii=False) + '\n')


if __name__ == '__main__':
    main()
