#!/usr/bin/env python3
"""vocab_card — 生成单词学习卡（双解释义 + 双语段落 + 双语句例句）

用法:
  python3 vocab_card.py BOOK [--max 30] [--level 4] [--sent 3] [--out output/]
  python3 vocab_card.py BOOK --words rebellion,windmill,comrade

每张卡含:
  · 单词 + 词性 + CEFR 等级
  · 中英双语释义
  · 含该词的段落（原文 + 中文翻译）
  · 数条含该词的例句（原文 + 中文翻译）
"""

import os, re, sys, argparse, html

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)) or '.')
import importer, wordpick, translate, txt2png

FONT = '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc'
if not os.path.exists(FONT):
    FONT = '/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc'

# 中国传统配色（参考 src/dotui.h）
BG     = 0xE2F0CB   # 霜地
INK    = 0x1D1B1C   # 墨色
GREEN  = 0x2E8B57   # 青绿
RED    = 0xD92121   # 朱砂红
MUTED  = 0x5B6B4F
ACCENT = 0x2A3C5C   # 黛蓝
BORDER = 0xC4D6A6

W = 820
MARGIN = 40
TEXT_W = W - 2 * MARGIN

# ── 文本解析 ──────────────────────────────────────────────

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

def split_paragraphs(text):
    paras = re.split(r'\n\s*\n', text)
    out = []
    for p in paras:
        p = html.unescape(p)
        p = re.sub(r'\s+', ' ', p).strip()
        if len(p) >= 20 and re.search(r'[A-Za-z]{3}', p):
            out.append(p)
    return out

def split_sentences(para):
    sents = re.split(r'(?<=[.!?])\s+', para)
    return [s.strip() for s in sents if len(s.strip()) >= 15]

def find_context(text, word, max_sent=3):
    """返回 (段落原文, [例句原文, ...])"""
    paras = split_paragraphs(text)
    para_hit = ''
    sents = []
    for p in paras:
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

def _truncate(s, n=320):
    return s if len(s) <= n else s[:n].rstrip() + '...'

def build_card(word, level_name, text, max_sent=3):
    para, sents = find_context(text, word, max_sent)
    en_def, zh_def, pos = translate.define(word)
    card = {
        'word': word, 'level': level_name, 'pos': pos,
        'en_def': en_def, 'zh_def': zh_def,
        'para_en': _truncate(para), 'para_zh': '',
        'sents': [],
    }
    if para:
        card['para_zh'] = translate.translate(_truncate(para))
    for s in sents:
        card['sents'].append((s, translate.translate(s)))
    return card

# ── Markdown ──────────────────────────────────────────────

def render_md(cards, book_title, out_path):
    lines = [f'# {book_title} — 词汇卡\n', f'> {len(cards)} 词\n', '---\n']
    for i, c in enumerate(cards, 1):
        lines.append(f'## {i}. {c["word"]}  [{c["level"]}]')
        if c['pos']:
            lines.append(f'*{c["pos"]}*')
        lines.append('')
        lines.append(f'**释义**：{c["zh_def"]}')
        lines.append(f'')
        lines.append(f'> {c["en_def"]}')
        if c['para_en']:
            lines.append('')
            lines.append('**段落**：')
            lines.append('')
            lines.append(f'- {c["para_en"]}')
            lines.append(f'- {c["para_zh"]}')
        if c['sents']:
            lines.append('')
            lines.append('**例句**：')
            lines.append('')
            for en, zh in c['sents']:
                lines.append(f'{en}')
                lines.append('')
                lines.append(f'*\u3000{zh}*')
                lines.append('')
        lines.append('\n---\n')
    with open(out_path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines))
    return out_path

# ── PNG ───────────────────────────────────────────────────

def _measure(canvas, fs, text):
    return canvas.measure(FONT, fs, text)

def _wrap(canvas, text, fs, max_w):
    if not text:
        return []
    # 中文按字断行，英文按词断行
    is_cjk = any('\u4e00' <= ch <= '\u9fff' for ch in text)
    out, cur = [], ''
    units = list(text) if is_cjk else text.split()
    joiner = '' if is_cjk else ' '
    for u in units:
        test = (cur + joiner + u) if cur else u
        if _measure(canvas, fs, test) <= max_w:
            cur = test
        else:
            if cur:
                out.append(cur)
            cur = u
    if cur:
        out.append(cur)
    return out

def render_png(card, out_path):
    FS = 18
    FS_T = 30
    FS_SEC = 16
    FS_SM = 15
    LH = lambda fs: int(fs * 1.55)

    probe = txt2png.Canvas(W, 100, BG)
    # 预估高度
    def para_h(text, fs):
        n = len(_wrap(probe, text, fs, TEXT_W))
        return n * LH(fs)
    h = MARGIN
    h += LH(FS_SM) + 8                       # label
    h += LH(FS_T) + 24                       # word
    h += para_h(card['zh_def'], FS) + para_h(card['en_def'], FS_SM) + 24
    if card['para_en']:
        h += LH(FS_SEC) + 6 + para_h(card['para_en'], FS) + para_h(card['para_zh'], FS) + 20
    if card['sents']:
        h += LH(FS_SEC) + 6
        for en, zh in card['sents']:
            h += para_h(en, FS) + para_h(zh, FS_SM) + 14
    h += MARGIN

    c = txt2png.Canvas(W, h, BG)
    y = MARGIN
    # 顶部标签
    c.draw_text(FONT, FS_SM, 'WordCard', MARGIN, y + c.ascent(FONT, FS_SM), GREEN)
    c.draw_text(FONT, FS_SM, card['level'], MARGIN + 120, y + c.ascent(FONT, FS_SM), MUTED)
    y += LH(FS_SM) + 8
    # 单词
    c.draw_text(FONT, FS_T, card['word'], MARGIN, y + c.ascent(FONT, FS_T), RED)
    if card['pos']:
        xw = c.measure(FONT, FS_T, card['word'])
        c.draw_text(FONT, FS_SM, card['pos'], MARGIN + xw + 14, y + c.ascent(FONT, FS_T), MUTED)
    y += LH(FS_T) + 24
    # 释义
    for line in _wrap(c, card['zh_def'], FS, TEXT_W):
        c.draw_text(FONT, FS, line, MARGIN, y + c.ascent(FONT, FS), INK)
        y += LH(FS)
    for line in _wrap(c, card['en_def'], FS_SM, TEXT_W):
        c.draw_text(FONT, FS_SM, line, MARGIN, y + c.ascent(FONT, FS_SM), MUTED)
        y += LH(FS_SM)
    y += 24
    # 段落
    if card['para_en']:
        c.draw_text(FONT, FS_SEC, '段落', MARGIN, y + c.ascent(FONT, FS_SEC), GREEN)
        y += LH(FS_SEC) + 6
        for line in _wrap(c, card['para_en'], FS, TEXT_W):
            c.draw_text(FONT, FS, line, MARGIN, y + c.ascent(FONT, FS), INK)
            y += LH(FS)
        for line in _wrap(c, card['para_zh'], FS, TEXT_W):
            c.draw_text(FONT, FS, line, MARGIN, y + c.ascent(FONT, FS), ACCENT)
            y += LH(FS)
        y += 20
    # 例句
    if card['sents']:
        c.draw_text(FONT, FS_SEC, '例句', MARGIN, y + c.ascent(FONT, FS_SEC), GREEN)
        y += LH(FS_SEC) + 6
        for idx, (en, zh) in enumerate(card['sents'], 1):
            c.draw_text(FONT, FS_SM, f'{idx}.', MARGIN, y + c.ascent(FONT, FS_SM), RED)
            for k, line in enumerate(_wrap(c, en, FS, TEXT_W - 24)):
                c.draw_text(FONT, FS, line, MARGIN + 24, y + c.ascent(FONT, FS), INK)
                y += LH(FS)
            for line in _wrap(c, zh, FS_SM, TEXT_W - 24):
                c.draw_text(FONT, FS_SM, line, MARGIN + 24, y + c.ascent(FONT, FS_SM), ACCENT)
                y += LH(FS_SM)
            y += 14
    c.save(out_path)
    return out_path

# ── main ──────────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('book')
    ap.add_argument('--max', type=int, default=20)
    ap.add_argument('--level', type=int, default=4)
    ap.add_argument('--sent', type=int, default=3)
    ap.add_argument('--words', default=None, help='逗号分隔，覆盖自动选词')
    ap.add_argument('--out', default='output')
    ap.add_argument('--no-png', action='store_true')
    a = ap.parse_args()

    os.makedirs(a.out, exist_ok=True)
    print('解析电子书...')
    info = importer.extract(a.book)
    text = html.unescape(info['text'])
    title = info['title'] or os.path.basename(a.book)

    if a.words:
        words = [(w.strip().lower(), 0.0, 0, 0) for w in a.words.split(',') if w.strip()]
    else:
        print(f'选择词汇 (level={a.level})...')
        words = [(w, s, z, n, lv) for (w, _c, s, z, n, lv) in
                 wordpick.select(text, max_words=a.max, level=a.level)]

    if not translate.available():
        print('错误: 本地 LLM 翻译服务不可用', file=sys.stderr)
        sys.exit(1)

    cards = []
    for i, (w, *_rest) in enumerate(words, 1):
        lv = _rest[3] if len(_rest) >= 4 else 0
        lname = wordpick.CEFR_NAMES.get(lv, '') if lv else ''
        print(f'  [{i}/{len(words)}] {w} ...')
        cards.append(build_card(w, lname, text, a.sent))

    md = os.path.join(a.out, 'vocab_cards.md')
    render_md(cards, title, md)
    print('MD:', md)

    if not a.no_png:
        for c in cards:
            p = os.path.join(a.out, f"card_{c['word']}.png")
            render_png(c, p)
        print(f'PNG: {len(cards)} 张 → {a.out}/card_*.png')

if __name__ == '__main__':
    main()
