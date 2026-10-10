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


def _prose_score(p):
    """正文段落评分：句末标点权重高；标题/目录/列表/过长均扣分。"""
    words = len(re.findall(r'[A-Za-z]+', p))
    punct = len(re.findall(r'[.!?]', p))
    bullets = p.count('•')
    score = min(words, 60) + punct * 15
    if punct == 0:
        score -= 30            # 无句末标点，疑似标题
    if len(p) < 40:
        score -= 15            # 过短
    if len(p) > 500:
        score -= 40            # 过长（整章/索引）
    score -= bullets * 4       # 列表项（多为目录/要点）
    return score


def _clip(p, max_chars=360):
    """截到不超过 max_chars，尽量落在句末（避免切出极短片段）。"""
    if len(p) <= max_chars:
        return p
    cut = p[:max_chars]
    ends = [m.end() for m in re.finditer(r'[.!?](\s|$)', cut)]
    ends = [e for e in ends if e >= 120]
    if ends:
        return cut[:ends[-1]].strip()
    return cut.rstrip() + '…'


def find_context(text, word, max_sent=2):
    """返回 (段落原文, [例句原文, ...])。

    在含该词的段落中选「正文感」最强的一段（跳过标题/目录，长度适中），
    再从该段及后续匹配段抽取例句。
    """
    matches = [p for p in split_paragraphs(text) if contains_word(p, word)]
    if not matches:
        return '', []
    para = _clip(max(matches, key=_prose_score))
    sents = []
    for p in [para] + [m for m in matches if m != para]:
        for s in split_sentences(p):
            if contains_word(s, word) and s not in sents:
                sents.append(s)
                if len(sents) >= max_sent:
                    break
        if len(sents) >= max_sent:
            break
    return para, sents
