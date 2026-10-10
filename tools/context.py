#!/usr/bin/env python3
"""context.py — 定位含某词的段落与例句（供对照物料生成）。"""

import html
import re


def _stem(word):
    return word[:-1] if word.endswith('e') and len(word) > 3 else word


def contains_word(text, word):
    wl = word.lower()
    stem = _stem(wl)
    for tok in re.findall(r"[A-Za-z]+", text.lower()):
        if tok == wl:
            return True
        if len(stem) >= 4 and tok.startswith(stem):
            return True
    return False


def _is_toc(p):
    # 目录/索引行：点线引导或数字占比高
    if len(re.findall(r'\.\s*\.', p)) >= 3:
        return True
    digits = sum(c.isdigit() for c in p)
    return len(p) > 0 and digits / len(p) > 0.25


def split_paragraphs(text):
    out = []
    for p in re.split(r'\n\s*\n', text):
        p = html.unescape(p)
        p = re.sub(r'\s+', ' ', p).strip()
        if len(p) >= 20 and re.search(r'[A-Za-z]{3}', p) and not _is_toc(p):
            out.append(p)
    return out


def split_sentences(para):
    return [s.strip() for s in re.split(r'(?<=[.!?])\s+', para)
            if len(s.strip()) >= 15]


def find_context(text, word, max_sent=2):
    """返回 (段落原文, [例句原文, ...])。"""
    para_hit = ''
    sents = []
    for p in split_paragraphs(text):
        if contains_word(p, word):
            if not para_hit:
                para_hit = p
            for s in split_sentences(p):
                if contains_word(s, word) and s not in sents:
                    sents.append(s)
                    if len(sents) >= max_sent:
                        break
        if para_hit and len(sents) >= max_sent:
            break
    return para_hit, sents
