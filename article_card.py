#!/usr/bin/env python3
"""PNG + MD + PDF 卡片生成"""

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

    img = Image.new('RGB', (CARD_WIDTH, 1), '#F5F5F5')
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
    for v in article['vocabulary'][:12]:
        word_w = font_en.getlength(v['word'])
        if word_w + font_text.getlength(v['meaning']) + 150 > max_width:
            meaning_lines = wrap_text(v['meaning'], font_text, max_width - 10 - word_w - 120)
            draw.text((MARGIN + 10, y), v['word'], font=font_en, fill='#E74C3C')
            for ml in meaning_lines:
                draw.text((MARGIN + 120, y), ml, font=font_text, fill='#7F8C8D')
                y += LINE_HEIGHT
        else:
            draw.text((MARGIN + 10, y), v['word'], font=font_en, fill='#E74C3C')
            draw.text((MARGIN + 120, y), v['meaning'], font=font_text, fill='#7F8C8D')
            y += LINE_HEIGHT

    y += 30
    draw.text((MARGIN, y), "精彩句子", font=font_section, fill='#27AE60')
    y += 45
    for i, s in enumerate(article['sentences'][:5], 1):
        orig_w = font_en.getlength(f"{i}. ")
        for j, ol in enumerate(wrap_text(s['original'], font_en, max_width - 10 - orig_w)):
            prefix = f"{i}. " if j == 0 else "   "
            draw.text((MARGIN + 10, y), prefix + ol, font=font_en, fill='#34495E')
            y += LINE_HEIGHT
        for tl in wrap_text(s['translation'], font_text, max_width - 30):
            draw.text((MARGIN + 30, y), tl, font=font_text, fill='#7F8C8D')
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
    for v in article['vocabulary'][:12]:
        word_w = font_en.getlength(v['word'])
        if word_w + font_text.getlength(v['meaning']) + 150 > max_width:
            meaning_lines = wrap_text(v['meaning'], font_text, max_width - 10 - word_w - 120)
            draw.text((MARGIN + 10, y), v['word'], font=font_en, fill='#E74C3C')
            for ml in meaning_lines:
                draw.text((MARGIN + 120, y), ml, font=font_text, fill='#7F8C8D')
                y += LINE_HEIGHT
        else:
            draw.text((MARGIN + 10, y), v['word'], font=font_en, fill='#E74C3C')
            draw.text((MARGIN + 120, y), v['meaning'], font=font_text, fill='#7F8C8D')
            y += LINE_HEIGHT

    y += 30
    draw.text((MARGIN, y), "精彩句子", font=font_section, fill='#27AE60')
    y += 45
    for i, s in enumerate(article['sentences'][:5], 1):
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

| 单词 | 释义 |
|------|------|
"""

    for v in article['vocabulary'][:12]:
        content += f"| {v['word']} | {v['meaning']} |\n"

    content += """
---

## 精彩句子

"""

    for i, s in enumerate(article['sentences'][:5], 1):
        content += f"> **{s['original']}**\n>\n> {s['translation']}\n\n"

    with open(output_path, 'w', encoding='utf-8') as f:
        f.write(content)

    print(f"MD: {output_path}")
    return True

def create_pdf(article, output_path):
    try:
        from fpdf2 import FPDF
    except ImportError as e:
        print(f"PDF: 跳过 - {e}")
        return False

    class PDF(FPDF):
        def header(self):
            self.set_font("helvetica", "B", 16)
            self.cell(0, 10, "WordCard", 0, 1, "L")
            self.ln(5)

        def chapter_title(self, title):
            self.set_font("helvetica", "B", 14)
            self.set_text_color(39, 174, 96)
            self.cell(0, 10, title, 0, 1, "L")
            self.set_text_color(0, 0, 0)
            self.ln(3)

        def chapter_body(self, body, indent=False):
            self.set_font("helvetica", "", 11)
            if indent:
                self.set_x(15)
            self.multi_cell(0, 7, body)
            self.ln()

        def simple_table(self, headers, rows):
            self.set_font("helvetica", "B", 11)
            col_width = 60
            for h in headers:
                self.cell(col_width, 8, h, 1, 0, "C")
            self.ln()
            self.set_font("helvetica", "", 10)
            for row in rows:
                self.cell(col_width, 7, row[0], 1, 0, "L")
                text = row[1][:35] + "..." if len(row[1]) > 35 else row[1]
                self.cell(col_width, 7, text, 1, 1, "L")

    pdf = PDF()
    pdf.add_page()
    pdf.set_auto_page_break(True, margin=15)

    pdf.set_font("helvetica", "B", 18)
    pdf.cell(0, 10, article["title"], 0, 1, "C")
    pdf.ln(5)

    pdf.chapter_title("原文")
    pdf.chapter_body(article["original"], indent=True)

    pdf.chapter_title("译文")
    pdf.chapter_body(article["translation"], indent=True)

    pdf.chapter_title("词汇表")
    vocab_rows = [(v["word"], v["meaning"]) for v in article["vocabulary"][:12]]
    pdf.simple_table(["Word", "Meaning"], vocab_rows)
    pdf.ln(5)

    pdf.chapter_title("精彩句子")
    for s in article["sentences"][:5]:
        pdf.set_font("helvetica", "B", 10)
        pdf.multi_cell(0, 6, s["original"])
        pdf.set_font("helvetica", "I", 10)
        pdf.set_text_color(100, 100, 100)
        pdf.multi_cell(0, 6, s["translation"])
        pdf.set_text_color(0, 0, 0)
        pdf.ln(5)

    try:
        pdf.save(output_path)
        print(f"PDF: {output_path}")
        return True
    except Exception as e:
        print(f"PDF: 生成失败 ({e})")
        return False

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
