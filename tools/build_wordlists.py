#!/usr/bin/env python3
"""build_wordlists.py — 从 ECDICT 生成考试词表（TSV）

ECDICT（https://github.com/skywind3000/ECDICT）自带中文释义与考试标签，
本脚本把 ecdict.csv 按标签筛成各词表，输出到 data/wordlists/<name>.tsv。

用法:
    python3 tools/build_wordlists.py                 # 全部词表
    python3 tools/build_wordlists.py cet4 cet6       # 指定词表
    python3 tools/build_wordlists.py --refresh       # 强制重新下载 ecdict.csv

依赖: 仅标准库。ecdict.csv 约 63MB，缓存在 ~/.cache/wordcard/。
输出列: word \t phonetic \t pos \t translation \t tag
"""

import argparse
import csv
import json
import os
import re
import sys
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, 'data', 'wordlists')
CACHE = os.path.expanduser('~/.cache/wordcard/ecdict.csv')
ECDICT_URL = 'https://raw.githubusercontent.com/skywind3000/ECDICT/master/ecdict.csv'

# 词表：短名 → (中文标题, ECDICT 标签)
LISTS = {
    'cet4':  ('CET-4 四级', 'cet4'),
    'cet6':  ('CET-6 六级', 'cet6'),
    'ky':    ('考研', 'ky'),
    'toefl': ('托福 TOEFL', 'toefl'),
    'ielts': ('雅思 IELTS', 'ielts'),
    'gre':   ('GRE', 'gre'),
    'gk':    ('高考', 'gk'),
}


def ensure_ecdict(refresh=False):
    if refresh or not os.path.exists(CACHE):
        os.makedirs(os.path.dirname(CACHE), exist_ok=True)
        print(f'下载 ECDICT → {CACHE}')
        tmp = CACHE + '.part'
        urllib.request.urlretrieve(ECDICT_URL, tmp)
        os.replace(tmp, CACHE)
    size = os.path.getsize(CACHE)
    print(f'ECDICT: {CACHE} ({size/1e6:.1f} MB)')
    return CACHE


def _clean(s):
    return (s or '').replace('\r', '').strip()


def _unescape(s):
    # ECDICT 的 translation/definition 用字面量 \n 分隔多行释义；
    # 压成单行（TSV 无内嵌换行/制表符），方便 Python / Dart 简单解析。
    s = _clean(s).replace('\\n', ' ').replace('\\r', ' ')
    s = re.sub(r'[ \t\r\n]+', ' ', s)
    return s.strip()


def build(names):
    ensure_ecdict()
    os.makedirs(OUT_DIR, exist_ok=True)
    wanted = {LISTS[n][1]: n for n in names}
    out_files = {
        n: open(os.path.join(OUT_DIR, f'{n}.tsv'), 'w', encoding='utf-8')
        for n in names
    }
    counts = {n: 0 for n in names}

    with open(CACHE, newline='', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            word = _clean(row.get('word'))
            # 单词表：只收单 token（跳过短语、含空格/连字符的条目）
            if not word or ' ' in word or '-' in word or "'" in word:
                continue
            tags = set((row.get('tag') or '').split())
            hit = [wanted[t] for t in tags if t in wanted]
            if not hit:
                continue
            phonetic = _clean(row.get('phonetic'))
            pos = _clean(row.get('pos'))
            translation = _unescape(row.get('translation'))
            definition = _unescape(row.get('definition'))
            if not translation and not definition:
                continue
            tag = ' '.join(sorted(t for t in tags if t in wanted))
            line = '\t'.join(
                x.replace('\t', ' ') for x in (word, phonetic, pos, translation, tag)
            ) + '\n'
            for name in hit:
                out_files[name].write(line)
                counts[name] += 1

    for f in out_files.values():
        f.close()

    manifest = {}
    for name in names:
        title, tag = LISTS[name]
        manifest[name] = {
            'title': title,
            'tag': tag,
            'count': counts[name],
            'file': f'{name}.tsv',
            'source': 'ECDICT (skywind3000)',
        }
        print(f'  {name:6} {title:12} {counts[name]:5} 词')
    with open(os.path.join(OUT_DIR, 'manifest.json'), 'w', encoding='utf-8') as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)
    print(f'完成 → {OUT_DIR}')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('lists', nargs='*', help='词表名（默认全部）')
    ap.add_argument('--refresh', action='store_true', help='强制重新下载 ecdict.csv')
    args = ap.parse_args()

    if args.refresh:
        ensure_ecdict(refresh=True)

    names = args.lists or list(LISTS)
    bad = [n for n in names if n not in LISTS]
    if bad:
        print(f'未知词表: {bad}；可选: {list(LISTS)}', file=sys.stderr)
        sys.exit(1)
    build(names)


if __name__ == '__main__':
    main()
