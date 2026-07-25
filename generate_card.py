#!/usr/bin/env python3
"""卡片生成（txt2png 新版）：解析 _trans.txt -> MD / PNG / PDF"""

import warnings; warnings.filterwarnings('ignore')
import os, sys
from datetime import datetime

sys.path.insert(0, os.path.dirname(__file__) or '.')
import txt2png

FONT = 'LXGWWenKai-Regular.ttf'

# ---------- text parser ----------

def load_txt(txt_file):
    with open(txt_file, 'r', encoding='utf-8') as f:
        content = f.read()
    sections = {}
    current_section = None
    current_content = []

    def is_chinese_line(line):
        return any('\u4e00' <= c <= '\u9fff' for c in line)

    def merge_lines(lines):
        merged = []
        for l in lines:
            l = l.strip()
            if l: merged.append(l)
        return ' '.join(merged)

    def split_bilingual(lines):
        para_lines = []
        temp_lines = []
        is_chinese = None
        for l in lines:
            l = l.strip()
            if not l: continue
            line_is_chinese = is_chinese_line(l)
            if is_chinese is None:
                is_chinese = line_is_chinese
                temp_lines.append(l)
            elif line_is_chinese == is_chinese:
                temp_lines.append(l)
            else:
                para_lines.append(merge_lines(temp_lines))
                temp_lines = [l]
                is_chinese = line_is_chinese
        if temp_lines:
            para_lines.append(merge_lines(temp_lines))
        return '\n'.join(para_lines)

    for line in content.split('\n'):
        if line.startswith('TITLE:'):
            sections['title'] = line.replace('TITLE:', '').strip()
        elif line == '---':
            if current_section:
                if current_section == 'original':
                    sections['original'] = merge_lines(current_content)
                elif current_section in ('en_ch', 'sentences'):
                    sections[current_section] = split_bilingual(current_content)
                elif current_section == 'vocabulary':
                    sections['vocabulary'] = [l.strip() for l in current_content if l.strip()]
                else:
                    sections[current_section] = merge_lines(current_content)
                current_content = []
            current_section = None
        elif line == 'ORIGINAL:':
            current_section = 'original'; current_content = []
        elif line == 'EN-CH:':
            current_section = 'en_ch'; current_content = []
        elif line == 'VOCABULARY:':
            current_section = 'vocabulary'; current_content = []
        elif line == 'SENTENCES:':
            current_section = 'sentences'; current_content = []
        elif current_section:
            current_content.append(line)
    if current_section:
        if current_section == 'original':
            sections['original'] = merge_lines(current_content)
        elif current_section in ('en_ch', 'sentences'):
            sections[current_section] = split_bilingual(current_content)
        elif current_section == 'vocabulary':
            sections['vocabulary'] = [l.strip() for l in current_content if l.strip()]
        else:
            sections[current_section] = merge_lines(current_content)
    return sections

# ---------- helpers ----------

def _is_cjk(c):
    return '\u4e00' <= c <= '\u9fff'

def _tw(text):
    return sum(2 if _is_cjk(c) else 1 for c in text)

def _wrap_en(text, max_w):
    if not text: return ''
    words = text.split()
    lines = []
    cur = ''
    for w in words:
        if _tw(cur) + _tw(w) + 1 <= max_w:
            cur += w + ' '
        else:
            if cur: lines.append(cur.rstrip())
            cur = w + ' '
    if cur: lines.append(cur.rstrip())
    return '\n'.join(lines)

def _wrap_cn(text, max_w):
    if not text: return ''
    lines = []
    cur = ''
    for c in text:
        if _tw(cur) + (2 if _is_cjk(c) else 1) <= max_w:
            cur += c
        else:
            if cur: lines.append(cur)
            cur = c
    if cur: lines.append(cur)
    return '\n'.join(lines)

def _pv(line):
    """parse vocab line: 'word|中文' or '1. word|中文'"""
    if '|' not in line:
        return line, ''
    parts = line.split('|', 1)
    en = parts[0].strip()
    dot = en.find('. ')
    if dot > 0 and en[:dot].isdigit():
        en = en[dot+2:]
    return en, parts[1].strip()

# ---------- MD ----------

def create_md(sections, output_path):
    EN_W = 52
    ZH_W = 50
    content = '# ' + sections.get('title', '') + '\n\n'
    content += '> ' + datetime.now().strftime('%Y-%m-%d %H:%M:%S') + '\n\n---\n\n## \u539f\u6587\n\n'
    content += _wrap_en(sections.get('original', ''), EN_W) + '\n\n---\n\n## \u4e2d\u82f1\u53cc\u8bed\n\n'
    for line in sections.get('en_ch', '').split('\n'):
        if _is_cjk(line[0:1]):
            content += _wrap_cn(line, ZH_W) + '\n\n'
        else:
            content += _wrap_en(line, EN_W) + '\n\n'
    content += '---\n\n## \u8bcd\u6c47\u8868\n\n'
    vl = [l for l in sections.get('vocabulary', []) if l.strip()]
    mid = len(vl) // 2
    for i in range(max(len(vl[:mid]), len(vl[mid:]))):
        le, lc = _pv(vl[i]) if i < len(vl[:mid]) else ('', '')
        re2, rc = _pv(vl[mid+i]) if mid+i < len(vl) else ('', '')
        lf = le + '  ' + lc
        rf = re2 + '  ' + rc
        content += '| ' + lf.ljust(30) + ' | ' + rf.ljust(30) + ' |\n'
    content += '\n---\n\n## \u7cbe\u5f69\u53e5\u5b50\n\n'
    for line in sections.get('sentences', '').split('\n'):
        if _is_cjk(line[0:1]):
            content += _wrap_cn(line, ZH_W) + '\n\n'
        else:
            content += _wrap_en(line, EN_W) + '\n\n'
    with open(output_path, 'w', encoding='utf-8') as f:
        f.write(content)
    print('  MD:', output_path)

# ---------- PNG ----------

def create_png(sections, output_path):
    font_path = FONT
    if not os.path.exists(font_path):
        font_path = os.path.join(os.path.dirname(__file__) or '.', FONT)

    MARGIN = 40
    W = 780
    COL_GAP = 20
    GREEN = 0x27AE60
    DARK = 0x34495E
    GRAY = 0x7F8C8D
    RED = 0xE74C3C
    BG = 0xF5F5F5
    FS_TITLE = 26
    FS_SECTION = 20
    FS_BODY = 18
    FS_VOCAB = 16
    FS_LABEL = 20

    def measure_wrapped(fp, fs, text):
        return probe.measure(fp, fs, text)
    def asc_wrapped(fp, fs):
        return probe.ascent(fp, fs)
    def wrap_en(text, max_w, fs):
        if not text: return []
        words = text.split()
        lines = []; cur = ''
        for w in words:
            test = (cur + ' ' + w).strip()
            if measure_wrapped(font_path, fs, test) <= max_w: cur = test
            else:
                if cur: lines.append(cur)
                cur = w
        if cur: lines.append(cur)
        return lines
    def wrap_cn(text, max_w, fs):
        if not text: return []
        lines = []; cur = ''
        for ch in text:
            test = cur + ch
            if measure_wrapped(font_path, fs, test) <= max_w: cur = test
            else:
                if cur: lines.append(cur)
                cur = ch
        if cur: lines.append(cur)
        return lines
    def line_h(fs):
        return int(fs * 1.4)
    def write_para(text, fs, x, baseline, color, max_w):
        wlines = wrap_en(text, max_w, fs) if not _is_cjk(text[0:1]) else wrap_cn(text, max_w, fs)
        bl = baseline
        for line in wlines:
            c.draw_text(font_path, fs, line, x, bl, color)
            bl += line_h(fs)
        return bl

    TEXT_W = W - 2 * MARGIN
    probe = txt2png.Canvas(100, 100, BG)

    def est_h():
        fs = FS_BODY
        a = asc_wrapped(font_path, fs)
        y = MARGIN
        y += line_h(FS_LABEL) + 10
        y += line_h(FS_TITLE) + 20
        y += line_h(FS_SECTION) + 5
        y += a
        for line in wrap_en(sections.get('original', ''), TEXT_W, fs):
            y += line_h(fs)
        y += 20 + line_h(FS_SECTION) + 5
        for line in sections.get('en_ch', '').split('\n'):
            if not line.strip(): y += line_h(fs) // 2; continue
            y += a
            wl = wrap_en(line, TEXT_W, fs) if not _is_cjk(line[0:1]) else wrap_cn(line, TEXT_W, fs)
            y += len(wl) * line_h(fs)
        y += 20 + line_h(FS_SECTION) + 5
        vl = [l for l in sections.get('vocabulary', []) if l.strip()]
        y += ((len(vl) + 1) // 2) * line_h(FS_VOCAB)
        y += 20 + line_h(FS_SECTION) + 5
        for line in sections.get('sentences', '').split('\n'):
            if not line.strip(): y += line_h(fs) // 2; continue
            y += a
            wl = wrap_en(line, TEXT_W, fs) if not _is_cjk(line[0:1]) else wrap_cn(line, TEXT_W, fs)
            y += len(wl) * line_h(fs)
        return y + MARGIN

    H = int(est_h() * 1.2)
    c = txt2png.Canvas(W, H, BG)
    y = MARGIN
    bl = y + asc_wrapped(font_path, FS_LABEL)
    c.draw_text(font_path, FS_LABEL, 'WordCard', MARGIN, bl, GREEN)
    y += line_h(FS_LABEL) + 10
    bl = y + asc_wrapped(font_path, FS_TITLE)
    c.draw_text(font_path, FS_TITLE, sections.get('title', ''), MARGIN, bl, DARK)
    y += line_h(FS_TITLE) + 20

    bl = y + asc_wrapped(font_path, FS_SECTION)
    c.draw_text(font_path, FS_SECTION, '\u539f\u6587', MARGIN, bl, GREEN)
    y += line_h(FS_SECTION) + 5
    bl = y + asc_wrapped(font_path, FS_BODY)
    y = write_para(sections.get('original', ''), FS_BODY, MARGIN, bl, DARK, TEXT_W)
    y += 20

    bl = y + asc_wrapped(font_path, FS_SECTION)
    c.draw_text(font_path, FS_SECTION, '\u4e2d\u82f1\u53cc\u8bed', MARGIN, bl, GREEN)
    y += line_h(FS_SECTION) + 5
    for line in sections.get('en_ch', '').split('\n'):
        if not line.strip(): y += line_h(FS_BODY) // 2; continue
        bl = y + asc_wrapped(font_path, FS_BODY)
        color = GRAY if _is_cjk(line[0:1]) else DARK
        y = write_para(line, FS_BODY, MARGIN, bl, color, TEXT_W)
    y += 20

    bl = y + asc_wrapped(font_path, FS_SECTION)
    c.draw_text(font_path, FS_SECTION, '\u8bcd\u6c47\u8868', MARGIN, bl, GREEN)
    y += line_h(FS_SECTION) + 5
    vl = [l for l in sections.get('vocabulary', []) if l.strip()]
    mid = len(vl) // 2
    col_w = (TEXT_W - COL_GAP) // 2
    for i in range(max(len(vl[:mid]), len(vl[mid:]))):
        bl2 = y + asc_wrapped(font_path, FS_VOCAB)
        left = vl[i] if i < len(vl[:mid]) else ''
        right = vl[mid+i] if mid+i < len(vl) else ''
        if left: c.draw_text(font_path, FS_VOCAB, left, MARGIN, bl2, RED)
        if right: c.draw_text(font_path, FS_VOCAB, right, MARGIN + col_w + COL_GAP, bl2, RED)
        y += line_h(FS_VOCAB)
    y += 20

    bl = y + asc_wrapped(font_path, FS_SECTION)
    c.draw_text(font_path, FS_SECTION, '\u7cbe\u5f69\u53e5\u5b50', MARGIN, bl, GREEN)
    y += line_h(FS_SECTION) + 5
    for line in sections.get('sentences', '').split('\n'):
        if not line.strip(): y += line_h(FS_BODY) // 2; continue
        bl = y + asc_wrapped(font_path, FS_BODY)
        color = GRAY if _is_cjk(line[0:1]) else DARK
        y = write_para(line, FS_BODY, MARGIN, bl, color, TEXT_W)

    c.save(output_path)
    print('  PNG:', output_path)
def create_pdf(sections, output_path):
    try:
        from fpdf import FPDF
    except ImportError:
        print('  PDF: skip (pip install fpdf2)')
        return

    font_path = FONT
    if not os.path.exists(font_path):
        font_path = os.path.join(os.path.dirname(__file__) or '.', FONT)

    class PDF(FPDF):
        def footer(self):
            self.set_y(-15)
            self.set_font('Helvetica', 'I', 8)
            self.cell(0, 10, str(self.page_no()), 0, 0, 'C')

    pdf = PDF(unit='mm', format=(105, 148))
    pdf.add_font('CJK', '', font_path, uni=True)

    def add_sec(title, lines, fs=9):
        pdf.add_page()
        pdf.set_font('CJK', '', 12)
        pdf.cell(0, 10, title, 0, 1)
        pdf.set_draw_color(39, 174, 96)
        pdf.line(10, pdf.get_y(), 95, pdf.get_y())
        pdf.ln(3)
        pdf.set_font('CJK', '', fs)
        for line in lines:
            if line.strip():
                pdf.multi_cell(0, 4.5, line.strip())
                pdf.ln(1.5)

    add_sec('\u539f\u6587 / ' + sections.get('title', ''),
            sections.get('original', '').split('\n'))
    add_sec('\u4e2d\u82f1\u53cc\u8bed', sections.get('en_ch', '').split('\n'))

    vl = [l for l in sections.get('vocabulary', []) if l.strip()]
    pdf.add_page()
    pdf.set_font('CJK', '', 12)
    pdf.cell(0, 10, '\u8bcd\u6c47\u8868', 0, 1)
    pdf.line(10, pdf.get_y(), 95, pdf.get_y())
    pdf.ln(3)
    pdf.set_font('CJK', '', 8)
    mid = len(vl) // 2
    for i in range(max(len(vl[:mid]), len(vl[mid:]))):
        left = vl[i] if i < len(vl[:mid]) else ''
        right = vl[mid+i] if mid+i < len(vl) else ''
        y = pdf.get_y()
        if left: pdf.text(12, y+3, left)
        if right: pdf.text(55, y+3, right)
        pdf.ln(6)

    add_sec('\u7cbe\u5f69\u53e5\u5b50', sections.get('sentences', '').split('\n'))
    pdf.output(output_path)
    print('  PDF:', output_path)

# ---------- main ----------

def main():
    txt_files = []
    if len(sys.argv) < 2:
        if os.path.exists('output'):
            for f in os.listdir('output'):
                if f.endswith('_trans.txt'):
                    txt_files.append(os.path.join('output', f))
        if not txt_files:
            print('Usage: python3 generate_card.py <input.txt> [...]')
            sys.exit(1)
    else:
        for arg in sys.argv[1:]:
            p = arg if os.path.exists(arg) else os.path.join('output', arg)
            if os.path.exists(p):
                txt_files.append(p)
            else:
                print('Skip:', arg)

    os.makedirs('output', exist_ok=True)

    for txt_file in txt_files:
        print()
        print('File:', txt_file)
        sections = load_txt(txt_file)
        print('Title:', sections.get('title', ''))
        base = os.path.splitext(os.path.basename(txt_file))[0]
        create_md(sections, os.path.join('output', base + '.md'))
        create_png(sections, os.path.join('output', base + '.png'))
        create_pdf(sections, os.path.join('output', base + '.pdf'))

    print()
    print('Done')

if __name__ == '__main__':
    main()
