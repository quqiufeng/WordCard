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

    def is_chinese_line(line):
        return any('\u4e00' <= c <= '\u9fff' for c in line)

    def merge_lines(lines):
        merged = []
        for l in lines:
            l = l.strip()
            if l:
                merged.append(l)
        return ' '.join(merged)

    def split_bilingual(lines):
        """分离英文段和中文段，交替排列"""
        para_lines = []
        temp_lines = []
        is_chinese = None

        for l in lines:
            l = l.strip()
            if not l:
                continue

            line_is_chinese = is_chinese_line(l)

            if is_chinese is None:
                is_chinese = line_is_chinese
                temp_lines.append(l)
            elif line_is_chinese == is_chinese:
                temp_lines.append(l)
            else:
                # 切换语言，保存当前段
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
                    # 保留每行一个词汇的格式
                    sections['vocabulary'] = [l.strip() for l in current_content if l.strip()]
                else:
                    sections[current_section] = merge_lines(current_content)
                current_content = []
            current_section = None
        elif line == 'ORIGINAL:':
            current_section = 'original'
            current_content = []
        elif line == 'EN-CH:' or line == '中英双语：':
            current_section = 'en_ch'
            current_content = []
        elif line == 'VOCABULARY:':
            current_section = 'vocabulary'
            current_content = []
        elif line == 'SENTENCES:':
            current_section = 'sentences'
            current_content = []
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

def create_md(sections, output_path):
    """生成 MD 文件"""
    ZH_WRAP = 25  # 中文换行字符数
    EN_WRAP = 50  # 英文换行字符数（单词边界断行）

    def is_chinese(text):
        return any('\u4e00' <= c <= '\u9fff' for c in text)

    def get_text_width(text):
        """计算显示宽度：英文字符=1，中文字符=2，[ ] 也按2处理避免在括号处换行"""
        width = 0
        for c in text:
            if is_chinese(c) or c in '[]':
                width += 2
            else:
                width += 1
        return width

    def wrap_english_md(text, max_width):
        """英文换行（单词边界断行）"""
        if not text:
            return ""
        words = text.split()
        lines = []
        current_line = ""
        for word in words:
            if get_text_width(current_line) + get_text_width(word) + 1 <= max_width:
                current_line += word + " "
            else:
                if current_line:
                    lines.append(current_line.rstrip())
                current_line = word + " "
        if current_line:
            lines.append(current_line.rstrip())
        return '\n'.join(lines)

    def wrap_md(text, max_chars):
        """MD格式换行"""
        if not text:
            return ""
        lines = []
        for i in range(0, len(text), max_chars):
            lines.append(text[i:i + max_chars])
        return '\n'.join(lines)

    content = f"# {sections.get('title', '')}\n\n"
    content += f"> 生成时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n\n"
    content += "---\n\n"
    content += "## 原文\n\n"
    content += wrap_english_md(sections.get('original', ''), EN_WRAP) + "\n\n"
    content += "---\n\n"
    content += "## 中英双语\n\n"
    en_ch_lines = sections.get('en_ch', '').split('\n')
    for line in en_ch_lines:
        if is_chinese(line):
            content += wrap_md(line, ZH_WRAP * 2) + "\n"
        else:
            content += wrap_english_md(line, EN_WRAP) + "\n"
    content += "\n---\n\n"
    content += "## 词汇表\n\n"

    vocab_lines = sections.get('vocabulary', [])
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

    def text_width(text):
        """计算文本显示宽度：英文字符=1，中文字符=2"""
        width = 0
        for c in text:
            if '\u4e00' <= c <= '\u9fff':
                width += 2  # 中文字符宽度2
            else:
                width += 1  # 英文字符宽度1
        return width

    def format_cell(en, cn, col_width=35, min_space=3):
        """英文 + 空白 + 中文 = 固定列宽（按显示宽度）"""
        en_w = text_width(en)
        cn_w = text_width(cn)
        space_len = col_width - en_w - cn_w
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

    try:
        font_title = ImageFont.truetype(font_path, 36)
        font_section = ImageFont.truetype(font_path, 26)
        font_text = ImageFont.truetype(font_path, 26)
        font_en = ImageFont.truetype(font_path, 22)
    except Exception as e:
        print(f"字体加载失败: {e}")
        return False

    MARGIN = 40
    LINE_HEIGHT = 42
    LINE_HEIGHT_CN = 52
    CARD_WIDTH = 780
    EN_WRAP = 50  # 英文换行字符数（单词边界断行）
    ZH_WRAP = 25  # 中文换行字符数

    def is_chinese(text):
        return any('\u4e00' <= c <= '\u9fff' for c in text)

    def get_text_width(text):
        """计算显示宽度：英文字符=1，中文字符=2，[ ] 也按2处理避免在括号处换行"""
        width = 0
        for c in text:
            if is_chinese(c) or c in '[]':
                width += 2
            else:
                width += 1
        return width

    def wrap_english(text, max_width):
        """英文换行（单词边界断行）"""
        if not text:
            return []
        words = text.split()
        lines = []
        current_line = ""
        for word in words:
            if get_text_width(current_line) + get_text_width(word) + 1 <= max_width:
                current_line += word + " "
            else:
                if current_line:
                    lines.append(current_line.rstrip())
                current_line = word + " "
        if current_line:
            lines.append(current_line.rstrip())
        return lines

    def wrap_chinese(text, max_chars):
        """中文按字符数换行"""
        if not text:
            return []
        lines = []
        for i in range(0, len(text), max_chars):
            lines.append(text[i:i + max_chars])
        return lines

    def text_display_width(text):
        """计算文本显示需要多少像素宽度"""
        return get_text_width(text) * 10

    # 词汇表解析
    vocab_lines = sections.get('vocabulary', [])
    vocab_lines = [l for l in vocab_lines if l.strip()]

    def parse_vocab(line):
        if '|' in line:
            parts = line.split('|', 1)
            en = parts[0].strip()
            cn = parts[1].strip()
            import re
            en = re.sub(r'^\d+\.\s*', '', en)
            return en, cn
        return line, ""

    # 计算总高度
    y = MARGIN
    y += 45  # WordCard
    for line in wrap_english(sections.get('title', ''), EN_WRAP):
        y += LINE_HEIGHT + 5
    y += 30
    y += 20
    y += 45  # 原文标题
    for line in sections.get('original', '').split('\n'):
        if line.strip():
            for l in wrap_english(line, EN_WRAP):
                y += LINE_HEIGHT
    y += 30
    y += 45  # 中英双语标题
    for line in sections.get('en_ch', '').split('\n'):
        if line.strip():
            if is_chinese(line):
                for l in wrap_chinese(line, ZH_WRAP):
                    y += LINE_HEIGHT_CN
            else:
                for l in wrap_english(line, EN_WRAP):
                    y += LINE_HEIGHT
    y += 30
    y += 45  # 词汇表标题
    left_col = vocab_lines[:len(vocab_lines)//2]
    right_col = vocab_lines[len(vocab_lines)//2:]
    for _ in range(max(len(left_col), len(right_col))):
        y += LINE_HEIGHT_CN
    y += 30
    y += 45  # 精彩句子标题
    for line in sections.get('sentences', '').split('\n'):
        if line.strip():
            if is_chinese(line):
                for l in wrap_chinese(line, ZH_WRAP):
                    y += LINE_HEIGHT_CN
            else:
                for l in wrap_english(line, EN_WRAP):
                    y += LINE_HEIGHT
    y += MARGIN

    img = Image.new('RGB', (CARD_WIDTH, int(y)), '#F5F5F5')
    draw = ImageDraw.Draw(img)
    y = MARGIN

    # WordCard
    draw.text((MARGIN, y), "WordCard", font=font_section, fill='#27AE60')
    y += 45

    # 标题
    for line in wrap_english(sections.get('title', ''), EN_WRAP):
        draw.text((MARGIN, y), line, font=font_title, fill='#34495E')
        y += LINE_HEIGHT + 5
    y += 30

    # 原文
    y += 20
    draw.text((MARGIN, y), "原文", font=font_section, fill='#27AE60')
    y += 45
    for line in wrap_english(sections.get('original', ''), EN_WRAP):
        draw.text((MARGIN + 10, y), line, font=font_text, fill='#34495E')
        y += LINE_HEIGHT
    y += 30

    # 中英双语
    draw.text((MARGIN, y), "中英双语", font=font_section, fill='#27AE60')
    y += 45
    en_ch_lines = sections.get('en_ch', '').split('\n')
    for line in en_ch_lines:
        if is_chinese(line):
            for l in wrap_chinese(line, ZH_WRAP):
                draw.text((MARGIN + 10, y), l, font=font_text, fill='#7F8C8D')
                y += LINE_HEIGHT_CN
        else:
            for l in wrap_english(line, EN_WRAP):
                draw.text((MARGIN + 10, y), l, font=font_text, fill='#34495E')
                y += LINE_HEIGHT
    y += 30

    # 词汇表
    draw.text((MARGIN, y), "词汇表", font=font_section, fill='#27AE60')
    y += 45
    center_x = CARD_WIDTH // 2
    left_y = y
    right_y = y

    for i in range(max(len(left_col), len(right_col))):
        # 左列
        left_en, left_cn = parse_vocab(left_col[i]) if i < len(left_col) else ("", "")
        if left_en or left_cn:
            draw.text((MARGIN + 10, left_y), f"{left_en}  {left_cn}", font=font_text, fill='#E74C3C')
            left_y += LINE_HEIGHT_CN
        draw.line((MARGIN, left_y, center_x - 10, left_y), fill='#E0E0E0')
        left_y += 10

        # 右列
        right_en, right_cn = parse_vocab(right_col[i]) if i < len(right_col) else ("", "")
        if right_en or right_cn:
            draw.text((center_x + 20, right_y), f"{right_en}  {right_cn}", font=font_text, fill='#E74C3C')
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
            if is_chinese(line):
                for l in wrap_chinese(line, ZH_WRAP):
                    draw.text((MARGIN + 10, y), l, font=font_text, fill='#7F8C8D')
                    y += LINE_HEIGHT_CN
            else:
                for l in wrap_english(line, EN_WRAP):
                    draw.text((MARGIN + 10, y), l, font=font_text, fill='#34495E')
                    y += LINE_HEIGHT

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

    vocab = sections.get('vocabulary', [])
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
