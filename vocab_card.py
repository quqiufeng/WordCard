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

# 字体预设
FONT_PRESETS = {
    'sans':  '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
    'serif': '/usr/share/fonts/opentype/noto/NotoSerifCJK-Regular.ttc',
    'kai':   '/usr/share/fonts/truetype/arphic/ukai.ttc',
    'hei':   '/usr/share/fonts/truetype/wqy/wqy-microhei.ttc',
    'zenhei':'/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc',
    'maple':       os.path.expanduser('~/.local/share/fonts/MapleMono/MapleMono-NF-CN-Regular.ttf'),
    'maple-medium':os.path.expanduser('~/.local/share/fonts/MapleMono/MapleMono-NF-CN-Medium.ttf'),
    'maple-semibold':os.path.expanduser('~/.local/share/fonts/MapleMono/MapleMono-NF-CN-SemiBold.ttf'),
    'maple-bold':  os.path.expanduser('~/.local/share/fonts/MapleMono/MapleMono-NF-CN-Bold.ttf'),
}

# 含中文的等宽/全字库字体 → 中英统一
_MULTI_FONTS = {'maple', 'maple-medium', 'maple-semibold', 'maple-bold',
                'zenhei', 'hei'}
FONT_CN = FONT_PRESETS['kai']      # 中文：楷体
FONT_EN = FONT_PRESETS['serif']    # 西文：宋体
for _p in FONT_PRESETS.values():
    if not os.path.exists(_p):
        continue
# 保证 FONT 有效
FONT = FONT_EN  # 兼容
def _is_cjk(s):
    return any('\u4e00' <= ch <= '\u9fff' or '\u3000' <= ch <= '\u303f' or '\uff00' <= ch <= '\uffef' for ch in s)

def _font_for(text):
    return FONT_CN if _is_cjk(text) else FONT_EN

# 中国传统配色（参考 src/dotui.h）
BG     = 0xE2F0CB   # 霜地
INK    = 0x1D1B1C   # 墨色
GREEN  = 0x2E8B57   # 青绿
RED    = 0xD92121   # 朱砂红
MUTED  = 0x5B6B4F
ACCENT = 0x2A3C5C   # 黛蓝
BORDER = 0xC4D6A6

W = 1000
MARGIN = 50
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
    return canvas.measure(_font_for(text), fs, text)

def _wrap(canvas, text, fs, max_w):
    if not text:
        return []
    # 中文按字断行，英文按词断行
    is_cjk = _is_cjk(text)
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

def render_png(card, out_path, width=1000, min_height=0):
    scale = width / 1000.0
    MARGIN = int(50 * scale)
    TEXT_W = width - 2 * MARGIN
    FS = int(27 * scale)
    FS_T = int(52 * scale)
    FS_SEC = int(25 * scale)
    FS_SM = int(21 * scale)
    LH = lambda fs: int(fs * 1.6)

    W = width
    probe = txt2png.Canvas(W, 100, BG)

    def para_h(text, fs):
        return len(_wrap(probe, text, fs, TEXT_W)) * LH(fs)

    h = MARGIN
    h += LH(FS_SM) + int(8 * scale)
    h += LH(FS_T) + int(24 * scale)
    h += para_h(card['zh_def'], FS) + para_h(card['en_def'], FS_SM) + int(24 * scale)
    if card['para_en']:
        h += LH(FS_SEC) + int(6 * scale) + para_h(card['para_en'], FS) + para_h(card['para_zh'], FS) + int(20 * scale)
    if card['sents']:
        h += LH(FS_SEC) + int(6 * scale)
        for en, zh in card['sents']:
            h += para_h(en, FS) + para_h(zh, FS_SM) + int(14 * scale)
    h += MARGIN
    if min_height:
        h = max(h, min_height)

    c = txt2png.Canvas(W, h, BG)
    y = MARGIN
    c.draw_text(FONT_EN, FS_SM, 'WordCard', MARGIN, y + c.ascent(FONT, FS_SM), GREEN)
    c.draw_text(FONT_EN, FS_SM, card['level'], MARGIN + int(120 * scale), y + c.ascent(FONT, FS_SM), MUTED)
    y += LH(FS_SM) + int(8 * scale)
    c.draw_text(FONT_EN, FS_T, card['word'], MARGIN, y + c.ascent(FONT, FS_T), RED)
    if card['pos']:
        xw = c.measure(FONT_EN, FS_T, card['word'])
        c.draw_text(FONT_EN, FS_SM, card['pos'], MARGIN + xw + int(14 * scale), y + c.ascent(FONT, FS_T), MUTED)
    y += LH(FS_T) + int(24 * scale)
    for line in _wrap(c, card['zh_def'], FS, TEXT_W):
        c.draw_text(FONT_CN, FS, line, MARGIN, y + c.ascent(FONT_CN, FS), INK); y += LH(FS)
    for line in _wrap(c, card['en_def'], FS_SM, TEXT_W):
        c.draw_text(FONT_EN, FS_SM, line, MARGIN, y + c.ascent(FONT_EN, FS_SM), MUTED); y += LH(FS_SM)
    y += int(24 * scale)
    if card['para_en']:
        c.draw_text(FONT_CN, FS_SEC, '段落', MARGIN, y + c.ascent(FONT, FS_SEC), GREEN)
        y += LH(FS_SEC) + int(6 * scale)
        for line in _wrap(c, card['para_en'], FS, TEXT_W):
            c.draw_text(FONT_EN, FS, line, MARGIN, y + c.ascent(FONT_EN, FS), INK); y += LH(FS)
        for line in _wrap(c, card['para_zh'], FS, TEXT_W):
            c.draw_text(FONT_CN, FS, line, MARGIN, y + c.ascent(FONT_CN, FS), ACCENT); y += LH(FS)
        y += int(20 * scale)
    if card['sents']:
        c.draw_text(FONT_CN, FS_SEC, '例句', MARGIN, y + c.ascent(FONT, FS_SEC), GREEN)
        y += LH(FS_SEC) + int(6 * scale)
        for idx, (en, zh) in enumerate(card['sents'], 1):
            c.draw_text(FONT_EN, FS_SM, f'{idx}.', MARGIN, y + c.ascent(FONT_EN, FS_SM), RED)
            for line in _wrap(c, en, FS, TEXT_W - int(24 * scale)):
                c.draw_text(FONT_EN, FS, line, MARGIN + int(24 * scale), y + c.ascent(FONT_EN, FS), INK); y += LH(FS)
            for line in _wrap(c, zh, FS_SM, TEXT_W - int(24 * scale)):
                c.draw_text(FONT_CN, FS_SM, line, MARGIN + int(24 * scale), y + c.ascent(FONT_CN, FS_SM), ACCENT); y += LH(FS_SM)
            y += int(14 * scale)
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
    ap.add_argument('--size', default='xhs',
                    help='xhs/小红薯=1920x2560(3:4), sq/朋友圈=2048x2048, 或 WxH')
    ap.add_argument('--font-cn', default=None, help='覆盖中文字体')
    ap.add_argument('--font', default='serif',
                    help='sans/serif/kai/hei/zenhei 或字体文件路径')
    ap.add_argument('--no-png', action='store_true')
    a = ap.parse_args()

    global FONT_CN, FONT_EN
    if a.font in FONT_PRESETS:
        if a.font in _MULTI_FONTS:
            FONT_CN = FONT_EN = FONT_PRESETS[a.font]
        else:
            FONT_EN = FONT_PRESETS[a.font]
    elif os.path.exists(a.font):
        FONT_EN = a.font
    if a.font_cn:
        FONT_CN = a.font_cn
    print(f'字体: 中文={os.path.basename(FONT_CN)}  西文={os.path.basename(FONT_EN)}')

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
        # 尺寸预设
        presets = {'xhs': (1920, 2560), '小红薯': (1920, 2560), 'xiaohongshu': (1920, 2560),
                   'sq': (2048, 2048), '朋友圈': (2048, 2048), 'pyq': (2048, 2048)}
        if a.size in presets:
            pw, ph = presets[a.size]
        elif 'x' in a.size:
            pw, ph = (int(x) for x in a.size.lower().split('x'))
        else:
            pw, ph = 1920, 2560
        for c in cards:
            p = os.path.join(a.out, f"card_{c['word']}.png")
            render_png(c, p, width=pw, min_height=ph)
        print(f'PNG: {len(cards)} 张 ({pw}x{ph}) → {a.out}/card_*.png')

if __name__ == '__main__':
    main()
