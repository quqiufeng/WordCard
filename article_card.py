#!/usr/bin/env python3
"""卡片生成：把 solar_system_trans.txt 原样渲染成 MD/PNG/PDF"""

import warnings
warnings.filterwarnings('ignore')

import os
import sys
from datetime import datetime

def load_txt(txt_file):
    """读取 txt 文件，按区块解析"""
    with open(txt_file, 'r', encoding='utf-8') as f:
        content = f.read()

    sections = {}
    current_section = None
    current_content = []

    for line in content.split('\n'):
        if line.startswith('TITLE:'):
            sections['title'] = line.replace('TITLE:', '').strip()
        elif line == '---':
            if current_section:
                sections[current_section] = '\n'.join(current_content).strip()
                current_content = []
            current_section = None
        elif line == 'ORIGINAL:':
            current_section = 'original'
        elif line == 'EN-CH:':
            current_section = 'en_ch'
        elif line == 'VOCABULARY:':
            current_section = 'vocabulary'
        elif line == 'SENTENCES:':
            current_section = 'sentences'
        elif current_section:
            current_content.append(line)

    if current_section:
        sections[current_section] = '\n'.join(current_content).strip()

    return sections

def create_md(sections, output_path):
    """生成 MD 文件"""
    content = f"# {sections.get('title', '')}\n\n"
    content += f"> 生成时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n\n"
    content += "---\n\n"
    content += "## 原文\n\n"
    content += sections.get('original', '') + "\n\n"
    content += "---\n\n"
    content += "## 中英双语\n\n"
    content += sections.get('en_ch', '') + "\n\n"
    content += "---\n\n"
    content += "## 词汇表\n\n"

    vocab_lines = sections.get('vocabulary', '').split('\n')
    vocab_lines = [line for line in vocab_lines if line.strip()]

    def parse_vocab(line):
        """解析 '1. word|中文' 格式，去掉序号，返回 (英文, 中文)"""
        if '|' in line:
            parts = line.split('|', 1)
            en = parts[0].strip()
            cn = parts[1].strip()
            import re
            en = re.sub(r'^\d+\.\s*', '', en)
            return en, cn
        return line, ""

    def format_cell(en, cn, col_width=35, min_space=3):
        """英文 + 空白 + 中文 = 固定列宽"""
        en_len = len(en)
        cn_len = len(cn)
        space_len = col_width - en_len - cn_len
        if space_len < min_space:
            space_len = min_space
        return f"{en}{' ' * space_len}{cn}"

    left_col = vocab_lines[:len(vocab_lines)//2]
    right_col = vocab_lines[len(vocab_lines)//2:]

    col_width = 35

    for i in range(max(len(left_col), len(right_col))):
        left_en, left_cn = parse_vocab(left_col[i]) if i < len(left_col) else ("", "")
        right_en, right_cn = parse_vocab(right_col[i]) if i < len(right_col) else ("", "")

        left_item = format_cell(left_en, left_cn, col_width)
        right_item = format_cell(right_en, right_cn, col_width)

        content += f"| {left_item} | {right_item} |\n"

    content += "\n"
    content += "---\n\n"
    content += "## 精彩句子\n\n"
    content += sections.get('sentences', '') + "\n"

    with open(output_path, 'w', encoding='utf-8') as f:
        f.write(content)
    print(f"MD: {output_path}")

def create_png(sections, output_path):
    """生成 PNG 图片"""
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
    CARD_WIDTH = 780

    def get_text_height(text, is_chinese=False):
        """计算文本高度"""
        lines = text.split('\n')
        height = 0
        for line in lines:
            if line.strip():
                height += LINE_HEIGHT_CN if is_chinese else LINE_HEIGHT
        return height

    # 计算总高度
    y = MARGIN
    y += 45  # WordCard
    y += 45 + 30  # 标题
    y += 20
    y += 45 + 45  # 原文
    y += get_text_height(sections.get('original', ''), False)
    y += 30
    y += 45 + 45  # 中英双语
    y += get_text_height(sections.get('en_ch', ''), True)
    y += 30
    y += 45 + 45  # 词汇表
    vocab_lines = sections.get('vocabulary', '').split('\n')
    y += len([l for l in vocab_lines if l.strip()]) * LINE_HEIGHT_CN
    y += 30
    y += 45 + 45  # 精彩句子
    y += get_text_height(sections.get('sentences', ''), True)
    y += MARGIN

    img = Image.new('RGB', (CARD_WIDTH, int(y)), '#F5F5F5')
    draw = ImageDraw.Draw(img)
    y = MARGIN

    # WordCard
    draw.text((MARGIN, y), "WordCard", font=font_section, fill='#27AE60')
    y += 45

    # 标题
    for line in sections.get('title', '').split('\n'):
        draw.text((MARGIN, y), line, font=font_title, fill='#34495E')
        y += 45
    y += 30

    # 原文
    y += 20
    draw.text((MARGIN, y), "原文", font=font_section, fill='#27AE60')
    y += 45
    for line in sections.get('original', '').split('\n'):
        if line.strip():
            draw.text((MARGIN + 10, y), line, font=font_en, fill='#34495E')
            y += LINE_HEIGHT
    y += 30

    # 中英双语
    draw.text((MARGIN, y), "中英双语", font=font_section, fill='#27AE60')
    y += 45
    for line in sections.get('en_ch', '').split('\n'):
        if line.strip():
            is_cn = any('\u4e00' <= c <= '\u9fff' for c in line)
            draw.text((MARGIN + 10, y), line, font=font_text if is_cn else font_en, fill='#7F8C8D' if is_cn else '#34495E')
            y += LINE_HEIGHT_CN if is_cn else LINE_HEIGHT
    y += 30

    # 词汇表
    draw.text((MARGIN, y), "词汇表", font=font_section, fill='#27AE60')
    y += 45
    center_x = CARD_WIDTH // 2
    left_y = y
    right_y = y
    left_col = vocab_lines[:len(vocab_lines)//2]
    right_col = vocab_lines[len(vocab_lines)//2:]

    for i, line in enumerate(left_col):
        if line.strip():
            draw.text((MARGIN + 10, left_y), line, font=font_en, fill='#E74C3C')
            left_y += LINE_HEIGHT_CN
        draw.line((MARGIN, left_y, center_x - 10, left_y), fill='#E0E0E0')
        left_y += 10

    for i, line in enumerate(right_col):
        if line.strip():
            draw.text((center_x + 20, right_y), line, font=font_en, fill='#E74C3C')
            right_y += LINE_HEIGHT_CN
        draw.line((center_x + 10, right_y, CARD_WIDTH - MARGIN, right_y), fill='#E0E0E0')
        right_y += 10

    draw.line((center_x, y, center_x, max(left_y, right_y)), fill='#E0E0E0')
    y = max(left_y, right_y)
    y += 30

    # 精彩句子
    draw.text((MARGIN, y), "精彩句子", font=font_section, fill='#27AE60')
    y += 45
    for line in sections.get('sentences', '').split('\n'):
        if line.strip():
            is_cn = any('\u4e00' <= c <= '\u9fff' for c in line)
            draw.text((MARGIN + 10, y), line, font=font_text if is_cn else font_en, fill='#7F8C8D' if is_cn else '#34495E')
            y += LINE_HEIGHT_CN if is_cn else LINE_HEIGHT

    img.save(output_path)
    print(f"PNG: {output_path}")
    return True

def create_pdf(sections, output_path):
    """生成 PDF 文件"""
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
    pdf.cell(0, 10, sections.get('title', ''), 0, 1, 'C')
    pdf.ln(5)

    vocab = sections.get('vocabulary', '').split('\n')
    sentences = sections.get('sentences', '').split('\n')
    pdf.set_font('LXGW', '', 8)
    pdf.cell(0, 5, f"Vocabulary: {len([v for v in vocab if v.strip()])} | Sentences: {len([s for s in sentences if s.strip()])}", 0, 1, 'C')
    pdf.ln(5)

    # 原文
    pdf.add_page()
    pdf.set_font('LXGW', '', 12)
    pdf.cell(0, 10, '原文 / Original', 0, 1, 'L')
    pdf.line(10, pdf.get_y(), 90, pdf.get_y())
    pdf.ln(3)
    pdf.set_font('LXGW', '', 9)
    for line in sections.get('original', '').split('\n'):
        if line.strip():
            pdf.multi_cell(0, 5, line)
            pdf.ln(2)

    # 中英双语
    pdf.add_page()
    pdf.set_font('LXGW', '', 12)
    pdf.cell(0, 10, '中英双语 / EN-CH', 0, 1, 'L')
    pdf.line(10, pdf.get_y(), 90, pdf.get_y())
    pdf.ln(3)
    pdf.set_font('LXGW', '', 9)
    for line in sections.get('en_ch', '').split('\n'):
        if line.strip():
            pdf.multi_cell(0, 5, line)
            pdf.ln(2)

    # 词汇表
    pdf.add_page()
    pdf.set_font('LXGW', '', 12)
    pdf.cell(0, 10, '词汇表 / Vocabulary', 0, 1, 'L')
    pdf.line(10, pdf.get_y(), 90, pdf.get_y())
    pdf.ln(3)
    pdf.set_font('LXGW', '', 9)
    left_col = vocab[:len(vocab)//2]
    right_col = vocab[len(vocab)//2:]
    for i in range(max(len(left_col), len(right_col))):
        y = pdf.get_y()
        if i < len(left_col) and left_col[i].strip():
            pdf.text(12, y + 3, left_col[i])
        if i < len(right_col) and right_col[i].strip():
            pdf.line(50, y, 50, y + 5)
            pdf.text(54, y + 3, right_col[i])
        pdf.ln(10)

    # 精彩句子
    pdf.add_page()
    pdf.set_font('LXGW', '', 12)
    pdf.cell(0, 10, '精彩句子 / Sentences', 0, 1, 'L')
    pdf.line(10, pdf.get_y(), 90, pdf.get_y())
    pdf.ln(3)
    pdf.set_font('LXGW', '', 9)
    for line in sections.get('sentences', '').split('\n'):
        if line.strip():
            is_cn = any('\u4e00' <= c <= '\u9fff' for c in line)
            if is_cn:
                pdf.set_text_color(100, 100, 100)
            pdf.multi_cell(0, 5, line)
            pdf.set_text_color(0, 0, 0)
            pdf.ln(2)

    pdf.output(output_path)
    print(f"PDF: {output_path}")
    return True

def main():
    if len(sys.argv) < 2:
        print("用法: python article_card.py solar_system_trans.txt")
        print("文件放在 output 目录")
        sys.exit(1)

    input_file = sys.argv[1]
    txt_file = f"output/{input_file}" if not input_file.startswith('output/') else input_file

    if not os.path.exists(txt_file):
        print(f"错误: 文件不存在 {txt_file}")
        sys.exit(1)

    print(f"读取: {txt_file}")
    sections = load_txt(txt_file)
    print(f"标题: {sections.get('title', '')}")

    base_name = os.path.splitext(os.path.basename(txt_file))[0]
    os.makedirs('output', exist_ok=True)

    create_md(sections, f"output/{base_name}.md")
    create_png(sections, f"output/{base_name}.png")
    create_pdf(sections, f"output/{base_name}.pdf")

if __name__ == '__main__':
    main()
