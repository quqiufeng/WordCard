#!/usr/bin/env python3
"""ebook_extract.py — 复用 importer 解析电子书，输出中英文对照词条 JSON。

解析复用现有 Python 管道（importer.extract + extract_words + wordpick）；
释义**优先离线查 ECDICT**（秒级、含音标/词性/中文），未收录的词留给 App 端
异步 LLM 回填（tools/ebook_define.py）。生成「中英文对照文件」供后续直接加载。

用法:
    python3 tools/ebook_extract.py <book> [--max 200] [--bilingual out.tsv] [--llm]

输出（--out 或 stdout，UTF-8 JSON）:
    {"title": "...", "author": "...", "count": 123,
     "words": [{"w": "abandon", "ph": "ә'bændәn", "p": "vt.", "d": "放弃", "ctx": "..."}]}

进度（stderr）: STAGE <msg>
"""

import argparse
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

import importer  # noqa: E402
import bilingual  # noqa: E402


def _stage(msg):
    print(f'STAGE {msg}', file=sys.stderr, flush=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('book')
    ap.add_argument('--max', type=int, default=200)
    ap.add_argument('--bilingual', help='把中英文对照写入该 TSV 文件')
    ap.add_argument('--llm', action='store_true',
                    help='对 ECDICT 未收录的词用本地 LLM 生成释义')
    ap.add_argument('--out', help='写入 JSON 文件（避免 stdout 噪声污染）')
    args = ap.parse_args()

    _stage('解析中')
    info = importer.extract(args.book)
    words = importer.extract_words(info['text'], max_words=args.max)

    _stage('查词（ECDICT）')
    ecd = bilingual.lookup_many([w for w, _ in words])
    cache = bilingual.load_cache()

    out_words = []
    rows = []
    missing = []
    for w, ctx in words:
        wl = w.lower()
        ph = pos = tr = ''
        if wl in ecd:
            ph, pos, tr = ecd[wl]
        elif wl in cache:
            pos, tr = cache[wl]
        else:
            missing.append(w)
        out_words.append({'w': w, 'ctx': ctx, 'ph': ph, 'p': pos, 'd': tr})
        rows.append((w, ph, pos, tr, ctx))

    if args.llm and missing:
        _stage(f'LLM 释义（{len(missing)} 个未收录词）')
        try:
            import translate
            ok = translate.available()
        except Exception as e:  # noqa: BLE001
            ok = False
            _stage(f'LLM 初始化失败: {e}')
        if ok:
            total = len(missing)
            done = 0
            for w in missing:
                try:
                    _en, zh, pos = translate.define(w)
                except Exception:  # noqa: BLE001
                    zh, pos = '', ''
                if zh:
                    bilingual.append_cache(w, pos, zh)
                    for i, ow in enumerate(out_words):
                        if ow['w'] == w:
                            ow['d'], ow['p'] = zh, pos
                            rows[i] = (rows[i][0], rows[i][1], pos, zh, rows[i][4])
                            break
                done += 1
                print(f'DEFINE {done}/{total}', file=sys.stderr, flush=True)

    if args.bilingual:
        bilingual.write_bilingual(args.bilingual, rows)

    out = {
        'title': info.get('title') or os.path.splitext(os.path.basename(args.book))[0],
        'author': info.get('author', ''),
        'count': len(words),
        'words': out_words,
    }
    if args.out:
        with open(args.out, 'w', encoding='utf-8') as f:
            json.dump(out, f, ensure_ascii=False)
    else:
        json.dump(out, sys.stdout, ensure_ascii=False)


if __name__ == '__main__':
    main()
