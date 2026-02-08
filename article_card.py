#!/usr/bin/env python3
"""PNG + MD + PDF 卡片生成"""

import warnings
warnings.filterwarnings('ignore')

import os
import sys
from datetime import datetime

def load_bilingual_txt(txt_file):
    article = {
        'title': '', 'original': '', 'translation': '',
        'vocabulary': [], 'sentences': []
    }
    section = None

    with open(txt_file, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.rstrip('\n')
            if line.startswith('TITLE:'):
                article['title'] = line.replace('TITLE:', '').strip()
            elif line == '---':
                section = None
            elif section == 'original':
                article['original'] += line + '\n'
            elif section == 'translation':
                article['translation'] += line + '\n'
            elif line == 'ORIGINAL:':
                section = 'original'
            elif line == 'TRANSLATION:':
                section = 'translation'
            elif line == 'VOCABULARY:':
                section = 'vocab'
            elif line == 'SENTENCES:':
                section = 'sent'
            elif section == 'vocab' and '|' in line:
                parts = line.split('|', 3)
                if len(parts) >= 3:
                    article['vocabulary'].append({
                        'word': parts[0],
                        'meaning': parts[2]
                    })
            elif section == 'sent' and '|' in line:
                parts = line.split('|', 1)
                if len(parts) >= 2:
                    article['sentences'].append({
                        'original': parts[0],
                        'translation': parts[1]
                    })
    return article

def text_width(text, font):
    import unicodedata
    width = 0
    for c in text:
        if unicodedata.east_asian_width(c) in ('W', 'F'):
            width += 2
        else:
            width += 1
    return width

def is_chinese(text):
    import re
    return bool(re.search('[\u4e00-\u9fff]', text))

def wrap_text(text, max_chars=40):
    if not text:
        return []

    lines = []
    for paragraph in text.split('\n'):
        if not paragraph.strip():
            lines.append('')
            continue

        if is_chinese(paragraph):
            i = 0
            while i < len(paragraph):
                lines.append(paragraph[i:i + max_chars])
                i += max_chars
        else:
            words = paragraph.split(' ')
            current_line = ""
            for word in words:
                if len(current_line) + len(word) + 1 <= max_chars:
                    current_line += (" " if current_line else "") + word
                else:
                    if current_line:
                        lines.append(current_line)
                    current_line = word
            if current_line:
                lines.append(current_line)

    return lines

def create_png(article, output_path):
    from PIL import Image, ImageDraw, ImageFont

    font_path = "LXGWWenKaiMono-Bold.ttf"
    font_path_en = "JetBrainsMono-Bold.ttf"

    try:
        font_title = ImageFont.truetype(font_path, 36)
        font_section = ImageFont.truetype(font_path, 26)
        font_text = ImageFont.truetype(font_path, 26)
        font_en = ImageFont.truetype(font_path_en, 22)
    except Exception as e:
        print(f"字体加载失败: {e}")
        return False

    MARGIN = 40
    LINE_HEIGHT = 42
    LINE_HEIGHT_CN = 52
    CARD_WIDTH = 680
    LINE_CHARS = 40
    LINE_CHARS_CN = 23
    max_width = CARD_WIDTH - MARGIN * 2

    y = MARGIN

    y += 45
    for line in wrap_text(article['title'], LINE_CHARS):
        y += LINE_HEIGHT + 5
    y += 30
    y += 20
    y += 45
    for line in article['original'].split('\n'):
        if line.strip():
            for l in wrap_text(line, LINE_CHARS):
                y += LINE_HEIGHT
    y += 30
    y += 45
    for line in article['translation'].split('\n'):
        if line.strip():
            for l in wrap_text(line, LINE_CHARS_CN):
                y += LINE_HEIGHT_CN
    y += 30
    y += 45

    vocab = article['vocabulary']
    half = (len(vocab) + 1) // 2
    left_col = vocab[:half]
    right_col = vocab[half:]

    center_x = CARD_WIDTH // 2

    left_y = y
    right_y = y

    for i in range(len(left_col)):
        v = left_col[i]
        word_w = text_width(v['word'], font_en)
        if word_w + text_width(v['meaning'], font_text) + 80 > center_x - MARGIN - 20:
            meaning_lines = wrap_text(v['meaning'], LINE_CHARS_CN)
            left_y += len(meaning_lines) * LINE_HEIGHT_CN
        else:
            left_y += LINE_HEIGHT_CN

    for i in range(len(right_col)):
        v = right_col[i]
        word_w = text_width(v['word'], font_en)
        if word_w + text_width(v['meaning'], font_text) + 80 > CARD_WIDTH - center_x - MARGIN - 20:
            meaning_lines = wrap_text(v['meaning'], LINE_CHARS_CN)
            right_y += len(meaning_lines) * LINE_HEIGHT_CN
        else:
            right_y += LINE_HEIGHT_CN

    y = max(left_y, right_y) + 10
    y += 30
    y += 45
    for i, s in enumerate(article['sentences'], 1):
        orig_w = font_en.getlength(f"{i}. ")
        for j, ol in enumerate(wrap_text(s['original'], LINE_CHARS)):
            y += LINE_HEIGHT
        for tl in wrap_text(s['translation'], LINE_CHARS_CN):
            y += LINE_HEIGHT_CN
        y += 10

    final_height = y + MARGIN

    img = Image.new('RGB', (CARD_WIDTH, int(final_height)), '#F5F5F5')
    draw = ImageDraw.Draw(img)
    y = MARGIN

    draw.text((MARGIN, y), "WordCard", font=font_section, fill='#27AE60')
    y += 45

    for line in wrap_text(article['title'], LINE_CHARS):
        draw.text((MARGIN, y), line, font=font_title, fill='#34495E')
        y += LINE_HEIGHT + 5
    y += 30

    y += 20
    draw.text((MARGIN, y), "原文", font=font_section, fill='#27AE60')
    y += 45
    for line in article['original'].split('\n'):
        if line.strip():
            for l in wrap_text(line, LINE_CHARS):
                draw.text((MARGIN + 10, y), l, font=font_en, fill='#34495E')
                y += LINE_HEIGHT

    y += 30
    draw.text((MARGIN, y), "译文", font=font_section, fill='#27AE60')
    y += 45
    for line in article['translation'].split('\n'):
        if line.strip():
            for l in wrap_text(line, LINE_CHARS_CN):
                draw.text((MARGIN + 10, y), l, font=font_text, fill='#7F8C8D')
                y += LINE_HEIGHT_CN

    y += 30
    draw.text((MARGIN, y), "词汇表", font=font_section, fill='#27AE60')
    y += 45

    left_start_y = y
    left_y = y
    right_y = y

    for i in range(len(left_col)):
        v = left_col[i]
        word_w = text_width(v['word'], font_en)
        if word_w + text_width(v['meaning'], font_text) + 80 > center_x - MARGIN - 20:
            meaning_lines = wrap_text(v['meaning'], LINE_CHARS_CN)
            draw.text((MARGIN + 10, left_y), v['word'], font=font_en, fill='#E74C3C')
            for ml in meaning_lines:
                draw.text((MARGIN + 220, left_y), ml, font=font_text, fill='#7F8C8D')
                left_y += LINE_HEIGHT_CN
        else:
            draw.text((MARGIN + 10, left_y), v['word'], font=font_en, fill='#E74C3C')
            draw.text((MARGIN + 220, left_y), v['meaning'], font=font_text, fill='#7F8C8D')
            left_y += LINE_HEIGHT_CN

        draw.line((MARGIN, left_y, center_x - 10, left_y), fill='#E0E0E0')
        left_y += 10

    for i in range(len(right_col)):
        v = right_col[i]
        word_w = text_width(v['word'], font_en)
        if word_w + text_width(v['meaning'], font_text) + 80 > CARD_WIDTH - center_x - MARGIN - 20:
            meaning_lines = wrap_text(v['meaning'], LINE_CHARS_CN)
            draw.text((center_x + 20, right_y), v['word'], font=font_en, fill='#E74C3C')
            for ml in meaning_lines:
                draw.text((center_x + 230, right_y), ml, font=font_text, fill='#7F8C8D')
                right_y += LINE_HEIGHT_CN
        else:
            draw.text((center_x + 20, right_y), v['word'], font=font_en, fill='#E74C3C')
            draw.text((center_x + 230, right_y), v['meaning'], font=font_text, fill='#7F8C8D')
            right_y += LINE_HEIGHT_CN

        draw.line((center_x + 10, right_y, CARD_WIDTH - MARGIN, right_y), fill='#E0E0E0')
        right_y += 10

    draw.line((center_x, left_start_y, center_x, max(left_y, right_y)), fill='#E0E0E0')

    y = max(left_y, right_y) + 10
    y += 30
    draw.text((MARGIN, y), "精彩句子", font=font_section, fill='#27AE60')
    y += 45
    for i, s in enumerate(article['sentences'], 1):
        orig_w = font_en.getlength(f"{i}. ")
        for j, ol in enumerate(wrap_text(s['original'], LINE_CHARS)):
            prefix = f"{i}. " if j == 0 else "   "
            draw.text((MARGIN + 10, y), prefix + ol, font=font_en, fill='#34495E')
            y += LINE_HEIGHT
        for tl in wrap_text(s['translation'], LINE_CHARS_CN):
            draw.text((MARGIN + 30, y), tl, font=font_text, fill='#7F8C8D')
            y += LINE_HEIGHT_CN
        y += 10

    img.save(output_path)
    print(f"PNG: {output_path}")
    return True

def create_md(article, output_path):
    content = f"""# {article['title']}

> 生成时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}

---

## 原文

{article['original']}

---

## 译文

{article['translation']}

---

"""

    for i, s in enumerate(article['sentences'], 1):
        content += f"> **{s['original']}**\n>\n> {s['translation']}\n\n"

    with open(output_path, 'w', encoding='utf-8') as f:
        f.write(content)

    print(f"MD: {output_path}")
    return True

def create_pdf(article, output_path):
    try:
        from fpdf import FPDF
    except ImportError:
        print("PDF: 跳过（需安装: pip install fpdf）")
        return False

    FONT_PATH = "LXGWWenKai-Regular.ttf"

    class PDF(FPDF):
        def header(self):
            self.set_font('Arial', 'B', 12)
            self.cell(0, 10, 'WordCard', 0, 1, 'R')
            self.ln(5)

        def footer(self):
            self.set_y(-15)
            self.set_font('Arial', 'I', 8)
            self.cell(0, 10, 'Page %d' % self.page_no(), 0, 0, 'C')

    pdf = PDF(unit='mm', format=(100, 178))
    pdf.add_page()

    pdf.add_font('LXGW', '', FONT_PATH, uni=True)

    pdf.set_font('LXGW', '', 10)
    pdf.cell(0, 10, article["title"], 0, 1, 'C')
    pdf.ln(5)

    pdf.set_font('LXGW', '', 8)
    pdf.cell(0, 5, f"Vocabulary: {len(article['vocabulary'])} | Sentences: {len(article['sentences'])}", 0, 1, 'C')
    pdf.ln(5)

    pdf.add_page()
    pdf.set_font('LXGW', '', 12)
    pdf.cell(0, 10, '原文 / Original', 0, 1, 'L')
    pdf.line(10, pdf.get_y(), 90, pdf.get_y())
    pdf.ln(3)

    pdf.set_font('LXGW', '', 9)
    original_lines = article['original'].replace('\n', ' ').split('. ')
    for para in original_lines:
        pdf.multi_cell(0, 5, para + '.')
        pdf.ln(2)

    pdf.add_page()
    pdf.set_font('LXGW', '', 12)
    pdf.cell(0, 10, '译文 / Translation', 0, 1, 'L')
    pdf.line(10, pdf.get_y(), 90, pdf.get_y())
    pdf.ln(3)

    pdf.set_font('LXGW', '', 9)
    trans_lines = article['translation'].replace('\n', ' ').split('. ')
    for para in trans_lines:
        pdf.multi_cell(0, 5, para + '.')
        pdf.ln(2)

    pdf.add_page()
    pdf.set_font('LXGW', '', 12)
    pdf.cell(0, 10, '词汇表 / Vocabulary', 0, 1, 'L')
    pdf.line(10, pdf.get_y(), 90, pdf.get_y())
    pdf.ln(3)

    pdf.set_font('LXGW', '', 9)

    vocab = article['vocabulary']
    half = (len(vocab) + 1) // 2
    left_col = vocab[:half]
    right_col = vocab[half:]

    for i in range(max(len(left_col), len(right_col))):
        y = pdf.get_y()

        if i < len(left_col):
            v = left_col[i]
            pdf.text(12, y + 3, f"{v['word']} - {v['meaning']}")

        pdf.line(50, y, 50, y + 5)

        if i < len(right_col):
            v = right_col[i]
            pdf.text(54, y + 3, f"{v['word']} - {v['meaning']}")

        pdf.ln(10)

    pdf.add_page()
    pdf.set_font('LXGW', '', 12)
    pdf.cell(0, 10, '精彩句子 / Sentences', 0, 1, 'L')
    pdf.line(10, pdf.get_y(), 90, pdf.get_y())
    pdf.ln(3)

    for i, s in enumerate(article['sentences'], 1):
        pdf.set_font('LXGW', '', 9)
        pdf.multi_cell(0, 5, f"{i}. {s['original']}")
        pdf.set_font('LXGW', '', 9)
        pdf.set_text_color(100, 100, 100)
        pdf.multi_cell(0, 5, s['translation'])
        pdf.set_text_color(0, 0, 0)
        pdf.ln(2)

    pdf.output(output_path)
    print(f"PDF: {output_path}")
    return True

def main():
    if len(sys.argv) < 2:
        print("用法: python article_card.py article.txt")
        sys.exit(1)

    txt_file = sys.argv[1].replace('.txt', '') + '_trans.txt'
    article = load_bilingual_txt(txt_file)

    base_name = os.path.splitext(txt_file)[0]

    os.makedirs('output', exist_ok=True)

    create_png(article, f"output/{os.path.basename(base_name)}.png")
    create_md(article, f"output/{os.path.basename(base_name)}.md")
    create_pdf(article, f"output/{os.path.basename(base_name)}.pdf")

if __name__ == '__main__':
    main()
