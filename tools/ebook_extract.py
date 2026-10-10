#!/usr/bin/env python3
"""ebook_extract.py — 复用 importer 解析电子书，输出词条 JSON 供 Flutter 导入。

解析完全复用现有 Python 管道（importer.extract + extract_words + wordpick），
Flutter 端不再实现任何解析逻辑，只消费本脚本输出的 JSON。

用法:
    python3 tools/ebook_extract.py <book.epub|mobi|azw3|pdf|md|txt> [--max 200]

输出（stdout，UTF-8 JSON）:
    {"title": "...", "author": "...", "count": 123,
     "words": [{"w": "abandon", "ctx": "He abandoned ..."}, ...]}
"""

import argparse
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

import importer  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('book')
    ap.add_argument('--max', type=int, default=200)
    ap.add_argument('--out', help='写入 JSON 文件（避免 stdout 噪声污染）')
    args = ap.parse_args()

    info = importer.extract(args.book)
    words = importer.extract_words(info['text'], max_words=args.max)
    out = {
        'title': info.get('title') or os.path.splitext(os.path.basename(args.book))[0],
        'author': info.get('author', ''),
        'count': len(words),
        'words': [{'w': w, 'ctx': ctx} for w, ctx in words],
    }
    if args.out:
        with open(args.out, 'w', encoding='utf-8') as f:
            json.dump(out, f, ensure_ascii=False)
    else:
        json.dump(out, sys.stdout, ensure_ascii=False)


if __name__ == '__main__':
    main()
