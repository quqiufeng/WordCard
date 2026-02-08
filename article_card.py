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

def wrap_text(text, font, max_width):
    if not text:
        return []

    lines = []
    for paragraph in text.split('\n'):
        if not paragraph.strip():
            lines.append('')
            continue

        words = list(paragraph)
        current_line = ""

        for char in words:
            test_line = current_line + char
            width = font.getlength(test_line)

            if width <= max_width:
                current_line = test_line
            else:
                if current_line:
                    lines.append(current_line)
                current_line = char

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
        font_text = ImageFont.truetype(font_path, 22)
        font_en = ImageFont.truetype(font_path_en, 22)
    except Exception as e:
        print(f"字体加载失败: {e}")
        return False

    MARGIN = 40
    LINE_HEIGHT = 32
    CARD_WIDTH = 1000
    max_width = CARD_WIDTH - MARGIN * 2

    y = MARGIN

    y += 45
    for line in wrap_text(article['title'], font_title, max_width):
        y += LINE_HEIGHT + 5
    y += 30
    y += 20
    y += 45
    for line in article['original'].split('\n'):
        if line.strip():
            for l in wrap_text(line, font_en, max_width - 10):
                y += LINE_HEIGHT
    y += 30
    y += 45
    for line in article['translation'].split('\n'):
        if line.strip():
            for l in wrap_text(line, font_text, max_width - 10):
                y += LINE_HEIGHT
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
        word_w = font_en.getlength(v['word'])
        if word_w + font_text.getlength(v['meaning']) + 80 > center_x - MARGIN - 20:
            meaning_lines = wrap_text(v['meaning'], font_text, center_x - MARGIN - 220)
            left_y += len(meaning_lines) * LINE_HEIGHT
        else:
            left_y += LINE_HEIGHT

    for i in range(len(right_col)):
        v = right_col[i]
        word_w = font_en.getlength(v['word'])
        if word_w + font_text.getlength(v['meaning']) + 80 > CARD_WIDTH - center_x - MARGIN - 20:
            meaning_lines = wrap_text(v['meaning'], font_text, CARD_WIDTH - center_x - MARGIN - 230)
            right_y += len(meaning_lines) * LINE_HEIGHT
        else:
            right_y += LINE_HEIGHT

    y = max(left_y, right_y) + 10
    y += 30
    y += 45
    for i, s in enumerate(article['sentences'], 1):
        orig_w = font_en.getlength(f"{i}. ")
        for j, ol in enumerate(wrap_text(s['original'], font_en, max_width - 10 - orig_w)):
            y += LINE_HEIGHT
        for tl in wrap_text(s['translation'], font_text, max_width - 30):
            y += LINE_HEIGHT
        y += 10

    final_height = y + MARGIN

    img = Image.new('RGB', (CARD_WIDTH, int(final_height)), '#F5F5F5')
    draw = ImageDraw.Draw(img)
    y = MARGIN

    draw.text((MARGIN, y), "WordCard", font=font_section, fill='#27AE60')
    y += 45

    for line in wrap_text(article['title'], font_title, max_width):
        draw.text((MARGIN, y), line, font=font_title, fill='#34495E')
        y += LINE_HEIGHT + 5
    y += 30

    y += 20
    draw.text((MARGIN, y), "原文", font=font_section, fill='#27AE60')
    y += 45
    for line in article['original'].split('\n'):
        if line.strip():
            for l in wrap_text(line, font_en, max_width - 10):
                draw.text((MARGIN + 10, y), l, font=font_en, fill='#34495E')
                y += LINE_HEIGHT

    y += 30
    draw.text((MARGIN, y), "译文", font=font_section, fill='#27AE60')
    y += 45
    for line in article['translation'].split('\n'):
        if line.strip():
            for l in wrap_text(line, font_text, max_width - 10):
                draw.text((MARGIN + 10, y), l, font=font_text, fill='#7F8C8D')
                y += LINE_HEIGHT

    y += 30
    draw.text((MARGIN, y), "词汇表", font=font_section, fill='#27AE60')
    y += 45

    left_start_y = y
    left_y = y
    right_y = y

    for i in range(len(left_col)):
        v = left_col[i]
        word_w = font_en.getlength(v['word'])
        if word_w + font_text.getlength(v['meaning']) + 80 > center_x - MARGIN - 20:
            meaning_lines = wrap_text(v['meaning'], font_text, center_x - MARGIN - 220)
            draw.text((MARGIN + 10, left_y), v['word'], font=font_en, fill='#E74C3C')
            for ml in meaning_lines:
                draw.text((MARGIN + 220, left_y), ml, font=font_text, fill='#7F8C8D')
                left_y += LINE_HEIGHT
        else:
            draw.text((MARGIN + 10, left_y), v['word'], font=font_en, fill='#E74C3C')
            draw.text((MARGIN + 220, left_y), v['meaning'], font=font_text, fill='#7F8C8D')
            left_y += LINE_HEIGHT

        draw.line((MARGIN, left_y, center_x - 10, left_y), fill='#E0E0E0')
        left_y += 10

    for i in range(len(right_col)):
        v = right_col[i]
        word_w = font_en.getlength(v['word'])
        if word_w + font_text.getlength(v['meaning']) + 80 > CARD_WIDTH - center_x - MARGIN - 20:
            meaning_lines = wrap_text(v['meaning'], font_text, CARD_WIDTH - center_x - MARGIN - 230)
            draw.text((center_x + 20, right_y), v['word'], font=font_en, fill='#E74C3C')
            for ml in meaning_lines:
                draw.text((center_x + 230, right_y), ml, font=font_text, fill='#7F8C8D')
                right_y += LINE_HEIGHT
        else:
            draw.text((center_x + 20, right_y), v['word'], font=font_en, fill='#E74C3C')
            draw.text((center_x + 230, right_y), v['meaning'], font=font_text, fill='#7F8C8D')
            right_y += LINE_HEIGHT

        draw.line((center_x + 10, right_y, CARD_WIDTH - MARGIN, right_y), fill='#E0E0E0')
        right_y += 10

    draw.line((center_x, left_start_y, center_x, max(left_y, right_y)), fill='#E0E0E0')

    y = max(left_y, right_y) + 10

    y += 30
    draw.text((MARGIN, y), "精彩句子", font=font_section, fill='#27AE60')
    y += 45
    for i, s in enumerate(article['sentences'], 1):
        orig_w = font_en.getlength(f"{i}. ")
        for j, ol in enumerate(wrap_text(s['original'], font_en, max_width - 10 - orig_w)):
            prefix = f"{i}. " if j == 0 else "   "
            draw.text((MARGIN + 10, y), prefix + ol, font=font_en, fill='#34495E')
            y += LINE_HEIGHT
        for tl in wrap_text(s['translation'], font_text, max_width - 30):
            draw.text((MARGIN + 30, y), tl, font=font_text, fill='#7F8C8D')
            y += LINE_HEIGHT
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

## 词汇表

| English (120) | Chinese (80) | English (120) | Chinese (80) |
|---------------|--------------|---------------|--------------|
"""

    vocab = article['vocabulary']
    half = (len(vocab) + 1) // 2
    left_col = vocab[:half]
    right_col = vocab[half:]

    for i in range(len(left_col)):
        left_v = left_col[i]
        right_v = right_col[i] if i < len(right_col) else None

        left_word = left_v['word'][:118]
        left_mean = left_v['meaning'][:78]

        if right_v:
            right_word = right_v['word'][:118]
            right_mean = right_v['meaning'][:78]
            content += f"| {left_word:<118} | {left_mean:<78} | {right_word:<118} | {right_mean:<78} |\n"
        else:
            content += f"| {left_word:<118} | {left_mean:<78} |                      |                      |\n"

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
