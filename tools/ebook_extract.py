#!/usr/bin/env python3
"""ebook_extract.py — 复用 importer 解析电子书，输出**含段落/例句**的中英文对照词条。

策略（已定）：
  · 单词释义 → 本地 ECDICT 词典（离线、秒级，含音标/词性/中英释义）
  · 段落与例句 → 原文直接带出，中文译文由 App 端异步调 LLM 翻译并回填

解析复用 Python 管道（importer + wordpick + context）。并写出对照物料：
  --bilingual data/books/<slug>.tsv   (词级速查: word/phonetic/pos/zh/context)
  --material  data/books/<slug>.jsonl (含段落/例句，供加载与翻译)

用法:
    python3 tools/ebook_extract.py <book> [--max 200] [--bilingual f.tsv] [--material f.jsonl] [--out f.json]
"""

import argparse
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

import importer  # noqa: E402
import bilingual  # noqa: E402
import context as ctx  # noqa: E402


def _stage(msg):
    print(f'STAGE {msg}', file=sys.stderr, flush=True)


def _clean(text):
    """去 HTML/链接残留，保留段落换行。"""
    text = importer.clean_text(text)
    text = re.sub(r'\[([^\]]*)\]\([^)]*\)', r'\1', text)  # markdown 链接
    text = re.sub(r'\[\]\([^)]*\)', '', text)             # 空链接
    return text


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('book')
    ap.add_argument('--max', type=int, default=200)
    ap.add_argument('--max-sent', type=int, default=2)
    ap.add_argument('--bilingual', help='词级中英文对照 TSV')
    ap.add_argument('--material', help='含段落/例句的 JSONL 物料')
    ap.add_argument('--llm', action='store_true', help='ECDICT 未收录词用 LLM 补释义')
    ap.add_argument('--out', help='词条 JSON 文件（App 消费）')
    args = ap.parse_args()

    _stage('解析中')
    info = importer.extract(args.book)
    text = _clean(info['text'])
    words = importer.extract_words(text, max_words=args.max * 2)
    words = [(w, c) for (w, c) in words if "'" not in w and '’' not in w]
    words = words[:args.max]

    _stage('查词（ECDICT）')
    ecd = bilingual.lookup_many([w for w, _ in words])
    cache = bilingual.load_cache()

    out_words = []
    material_lines = []
    tsv_rows = []
    missing = []
    for ranked, (w, sent_ctx) in enumerate(words, 1):
        wl = w.lower()
        ph = pos = zh = en = ''
        if wl in ecd:
            ph, pos, zh, en = ecd[wl]
        elif wl in cache:
            pos, zh = cache[wl]
        else:
            missing.append(w)
        para, sents = ctx.find_context(text, w, args.max_sent)
        # 无段落时退回 wordpick 给的上下文句
        if not para and sent_ctx:
            para = sent_ctx
        item = {
            'w': w, 'rank': ranked, 'ph': ph, 'p': pos, 'd': zh, 'e': en,
            'para': para, 'sents': sents,
            'para_zh': '', 'sents_zh': [],
        }
        out_words.append(item)
        material_lines.append(item)
        tsv_rows.append((w, ph, pos, zh, para or sent_ctx))

    if args.llm and missing:
        _stage(f'LLM 补释义（{len(missing)} 个）')
        try:
            import translate
            ok = translate.available()
        except Exception as e:  # noqa: BLE001
            ok = False
            _stage(f'LLM 初始化失败: {e}')
        if ok:
            total, done = len(missing), 0
            for w in missing:
                try:
                    _e, _z, _p = translate.define(w)
                except Exception:  # noqa: BLE001
                    _z, _p = '', ''
                if _z:
                    bilingual.append_cache(w, _p, _z)
                    for it in out_words:
                        if it['w'] == w:
                            it['d'], it['p'] = _z, _p
                            break
                done += 1
                print(f'DEFINE {done}/{total}', file=sys.stderr, flush=True)

    if args.bilingual:
        bilingual.write_bilingual(args.bilingual, tsv_rows)
    if args.material:
        os.makedirs(os.path.dirname(args.material) or '.', exist_ok=True)
        with open(args.material, 'w', encoding='utf-8') as f:
            for it in material_lines:
                f.write(json.dumps(it, ensure_ascii=False) + '\n')

    out = {
        'title': info.get('title') or os.path.splitext(os.path.basename(args.book))[0],
        'author': info.get('author', ''),
        'count': len(out_words),
        'words': out_words,
    }
    if args.out:
        with open(args.out, 'w', encoding='utf-8') as f:
            json.dump(out, f, ensure_ascii=False)
    else:
        json.dump(out, sys.stdout, ensure_ascii=False)


if __name__ == '__main__':
    main()
