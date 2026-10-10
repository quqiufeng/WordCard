#!/usr/bin/env python3
"""context.py — 定位含某词的段落与例句（供对照物料生成）。

优化点：
  · 整词匹配（\bword\b）优先，词干前缀仅作兜底；
  · 段落评分：句末标点↑、整词命中↑；标题/目录/列表/URL/超长↓；
  · 例句按质量排序：整词命中 + 像完整句子（首字母大写、句末标点、长度适中、
    非 URL），跨全篇候选里取最优，而非只取首段。
"""

import html
import re


def _stem(word):
    return word[:-1] if word.endswith('e') and len(word) > 3 else word


def _exact_re(word):
    return re.compile(r'\b' + re.escape(word) + r'\b', re.I)


def exact_count(text, word):
    return len(_exact_re(word).findall(text))


def contains_word(text, word):
    """整词命中，或词干前缀兜底（如 thinks→think）。"""
    if _exact_re(word).search(text):
        return True
    stem = _stem(word.lower())
    if len(stem) >= 4:
        return bool(re.search(r'\b' + re.escape(stem) + r'\w{0,4}\b', text, re.I))
    return False


def _is_toc(p):
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


def _prose_score(p, word):
    words = len(re.findall(r'[A-Za-z]+', p))
    punct = len(re.findall(r'[.!?]', p))
    bullets = p.count('•')
    urls = len(re.findall(r'https?://|www\.', p))
    score = min(words, 60) + punct * 15 + exact_count(p, word) * 8
    if punct == 0:
        score -= 30
    if len(p) < 40:
        score -= 15
    if len(p) > 500:
        score -= 40
    score -= bullets * 6
    score -= urls * 20
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


def _is_sentence(s):
    return (bool(s) and s[0].isupper() and s[-1] in '.!?'
            and 30 <= len(s) <= 240 and 'http' not in s and '@' not in s)


def _is_index_like(s):
    """索引/术语表行：数字或逗号-页码密集。"""
    if not s:
        return False
    digits = sum(c.isdigit() for c in s)
    commas = s.count(',')
    return (digits / len(s) > 0.12
            or (commas > 8 and digits > 15)
            or bool(re.search(r',\s*\d{2,3}\b.*,\s*\d{2,3}\b', s)))


def _sent_score(s, word):
    score = min(exact_count(s, word), 3) * 10
    if _is_sentence(s):
        score += 12
    if len(s) > 240:
        score -= 10
    if 'http' in s or 'www.' in s:
        score -= 40
    if s.count('•') or s.count('.') >= 3:
        score -= 10
    return score


def find_context(text, word, max_sent=2):
    """返回 (段落原文, [例句原文, ...])。"""
    matches = [p for p in split_paragraphs(text) if contains_word(p, word)]
    if not matches:
        return '', []
    para = _clip(max(matches, key=lambda p: _prose_score(p, word)))
    cands = []
    for p in matches:
        for s in split_sentences(p):
            if (contains_word(s, word) and not _is_index_like(s)
                    and s not in cands):
                cands.append(s)
    cands.sort(key=lambda s: _sent_score(s, word), reverse=True)
    return para, cands[:max_sent]
