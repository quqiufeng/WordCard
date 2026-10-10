#!/usr/bin/env python3
"""ebook_extract.py — 复用 importer 解析电子书，输出词条 JSON 供 Flutter 导入。

解析完全复用现有 Python 管道（importer.extract + extract_words + wordpick），
Flutter 端不再实现任何解析逻辑，只消费本脚本输出的 JSON。
`--define` 时再用本地 LLM（translate.define）生成中文释义。

用法:
    python3 tools/ebook_extract.py <book.epub|mobi|azw3|pdf|md|txt> [--max 200] [--define] [--out f.json]

输出（stdout 或 --out，UTF-8 JSON）:
    {"title": "...", "author": "...", "count": 123,
     "words": [{"w": "abandon", "ctx": "...", "d": "放弃", "p": "v."}, ...]}

进度（stderr，逐行）:
    STAGE <msg>        通用阶段提示
    DEFINE <i>/<n>     释义生成进度
"""

import argparse
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

import importer  # noqa: E402


def _stage(msg):
    print(f'STAGE {msg}', file=sys.stderr, flush=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('book')
    ap.add_argument('--max', type=int, default=200)
    ap.add_argument('--define', action='store_true',
                    help='用本地 LLM 生成中文释义（较慢）')
    ap.add_argument('--out', help='写入 JSON 文件（避免 stdout 噪声污染）')
    args = ap.parse_args()

    _stage('解析中')
    info = importer.extract(args.book)
    words = importer.extract_words(info['text'], max_words=args.max)

    defs = {}
    if args.define and words:
        _stage('加载 LLM')
        try:
            import translate
            ok = translate.available()
        except Exception as e:  # noqa: BLE001
            ok = False
            _stage(f'LLM 初始化失败: {e}')
        if ok:
            total = len(words)
            for i, (w, _ctx) in enumerate(words, 1):
                try:
                    _en, zh, pos = translate.define(w)
                except Exception:  # noqa: BLE001
                    zh, pos = '', ''
                if zh:
                    defs[w] = (zh, pos)
                print(f'DEFINE {i}/{total}', file=sys.stderr, flush=True)
        else:
            _stage('LLM 不可用，跳过释义')

    out = {
        'title': info.get('title') or os.path.splitext(os.path.basename(args.book))[0],
        'author': info.get('author', ''),
        'count': len(words),
        'words': [
            {'w': w, 'ctx': ctx,
             'd': defs.get(w, ('', ''))[0],
             'p': defs.get(w, ('', ''))[1]}
            for w, ctx in words
        ],
    }
    if args.out:
        with open(args.out, 'w', encoding='utf-8') as f:
            json.dump(out, f, ensure_ascii=False)
    else:
        json.dump(out, sys.stdout, ensure_ascii=False)


if __name__ == '__main__':
    main()
