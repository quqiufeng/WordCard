#!/usr/bin/env python3
"""ebook_define.py — 异步生成单词中文释义（本地 LLM），逐条输出 JSON 行。

对每个词调用 translate.define（llama-server），**每得到一个结果立即输出一行
JSON 并 flush**，供 App 边生成边回填，无需等全部完成。

用法:
    python3 tools/ebook_define.py --words words.txt
    cat words.txt | python3 tools/ebook_define.py

输出（stdout，每行一个 JSON）:
    {"w": "abandon", "p": "v.", "d": "放弃"}

进度（stderr）: READY / DEFINE i/n / STAGE msg
"""

import argparse
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)


def _stage(msg):
    print(f'STAGE {msg}', file=sys.stderr, flush=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--words', help='单词文件（每行一个）；缺省读 stdin')
    args = ap.parse_args()

    if args.words:
        with open(args.words, encoding='utf-8') as f:
            words = [l.strip() for l in f if l.strip()]
    else:
        words = [l.strip() for l in sys.stdin if l.strip()]

    import bilingual
    cache = bilingual.load_cache()

    # 命中缓存直接输出，不用启动 LLM
    remaining = []
    for w in words:
        if w.lower() in cache:
            pos, tr = cache[w.lower()]
            print(json.dumps({'w': w, 'p': pos, 'd': tr}, ensure_ascii=False),
                  flush=True)
        else:
            remaining.append(w)

    if not remaining:
        return

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

    total = len(remaining)
    for i, w in enumerate(remaining, 1):
        try:
            _en, zh, pos = translate.define(w)
        except Exception:  # noqa: BLE001
            zh, pos = '', ''
        if zh:
            bilingual.append_cache(w, pos, zh)
        print(json.dumps({'w': w, 'p': pos, 'd': zh}, ensure_ascii=False),
              flush=True)
        print(f'DEFINE {i}/{total}', file=sys.stderr, flush=True)


if __name__ == '__main__':
    main()
