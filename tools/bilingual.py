#!/usr/bin/env python3
"""bilingual.py — 中英文对照：查词与物料生成。

优先使用本地 ECDICT（离线、即时、含音标/词性/中文），仅 ECDICT 未收录的词
才落到 LLM（translate.define）。用于导入电子书时生成「中英文对照文件」。

ECDICT 缓存: ~/.cache/wordcard/ecdict.csv（tools/build_wordlists.py 会下载）。
"""

import csv
import os

ECDICT = os.path.expanduser('~/.cache/wordcard/ecdict.csv')
CACHE = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                     'data', 'dict_cache.tsv')


def _norm(s):
    return (s or '').replace('\\n', ' ').replace('\r', ' ').replace('\n', ' ').strip()


def lookup_many(words):
    """批量查 ECDICT，返回 {word_lower: (phonetic, pos, translation)}。

    只扫描一遍 ecdict.csv，命中 word 集合（不建全量索引，省内存）。
    """
    wanted = {w.lower() for w in words if w}
    found = {}
    if not os.path.exists(ECDICT) or not wanted:
        return found
    with open(ECDICT, newline='', encoding='utf-8') as f:
        for row in csv.DictReader(f):
            w = _norm(row.get('word')).lower()
            if w not in wanted or w in found:
                continue
            tr = _norm(row.get('translation')) or _norm(row.get('definition'))
            if not tr:
                continue
            found[w] = (_norm(row.get('phonetic')), _norm(row.get('pos')), tr)
            if len(found) == len(wanted):
                break
    return found


def load_cache():
    """加载 LLM 释义缓存 {word_lower: (pos, translation)}。"""
    cache = {}
    if os.path.exists(CACHE):
        with open(CACHE, encoding='utf-8') as f:
            for line in f:
                p = line.rstrip('\n').split('\t')
                if len(p) >= 3 and p[0]:
                    cache[p[0].lower()] = (p[1], p[2])
    return cache


def append_cache(word, pos, translation):
    if not word or not translation:
        return
    os.makedirs(os.path.dirname(CACHE), exist_ok=True)
    with open(CACHE, 'a', encoding='utf-8') as f:
        f.write(f'{word}\t{_norm(pos)}\t{_norm(translation)}\n')


def write_bilingual(path, rows):
    """写中英文对照文件（TSV）: word, phonetic, pos, translation, context。"""
    os.makedirs(os.path.dirname(path) or '.', exist_ok=True)
    with open(path, 'w', encoding='utf-8') as f:
        for word, ph, pos, tr, ctx in rows:
            cols = [word, ph, pos, tr, ctx]
            f.write('\t'.join(_norm(c).replace('\t', ' ') for c in cols) + '\n')
