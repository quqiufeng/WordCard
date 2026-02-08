#!/usr/bin/env python3
"""
生成中英双语文章卡片
用法: python article_card.py article.txt
输出: 当前目录下的 md/pdf/png 文件
"""

import warnings
warnings.filterwarnings('ignore')

import os
import sys
import re
import argparse
from datetime import datetime
from pathlib import Path

import ctranslate2
import transformers

MODEL_DIR = "E:/cuda/nllb-200-3.3B-ct2-float16"

COLORS = {
    'bg': '#F5F5DC',
    'card_bg': '#FFFFFF',
    'title': '#2C3E50',
    'text': '#34495E',
    'translation': '#7F8C8D',
    'accent': '#27AE60',
    'highlight': '#E74C3C',
    'border': '#E0E0E0'
}

CARD_WIDTH = 375
CARD_HEIGHT = 667

FONT_PATH = "LXGWWenKaiMono-Light.ttf"

def load_translator():
    translator = ctranslate2.Translator(MODEL_DIR, device="cuda")
    tokenizer = transformers.AutoTokenizer.from_pretrained(MODEL_DIR)
    return translator, tokenizer

def cleanup_translator(translator, tokenizer):
    import torch
    del translator
    del tokenizer
    torch.cuda.empty_cache()

def translate_batch(translator, tokenizer, texts, target_lang='zho_Hans'):
    import torch
    all_results = []
    batch_size = 64
    
    for i in range(0, len(texts), batch_size):
        batch_texts = texts[i:i + batch_size]
        encoded = tokenizer(batch_texts, return_tensors="pt", padding=True)
        input_ids = encoded["input_ids"]
        
        batch_results = []
        for j in range(len(batch_texts)):
            tokens = tokenizer.convert_ids_to_tokens(input_ids[j])
            results = translator.translate_batch([tokens], target_prefix=[[target_lang]])
            result_tokens = results[0].hypotheses[0]
            if result_tokens and result_tokens[0] == target_lang:
                result_tokens = result_tokens[1:]
            result = tokenizer.convert_tokens_to_string(result_tokens).strip()
            batch_results.append(result)
        
        all_results.extend(batch_results)
        del encoded, input_ids
        torch.cuda.empty_cache()
        
        progress = min(i + batch_size, len(texts))
        print(f"  翻译进度: {progress}/{len(texts)}", end='\r')
    
    print(f"  翻译进度: {len(texts)}/{len(texts)} (100%)")
    all_results = [r.replace("<unk>", "").strip() for r in all_results]
    return all_results

def extract_words(text, min_len=4, max_count=50):
    words = re.findall(r'\b[a-zA-Z]+\b', text.lower())
    word_count = {}
    for word in words:
        if len(word) >= min_len and not word.isdigit():
            word_count[word] = word_count.get(word, 0) + 1
    sorted_words = sorted(word_count.items(), key=lambda x: x[1], reverse=True)
    return [w[0] for w in sorted_words[:max_count]]

def split_sentences(text):
    sentences = re.split(r'[.!?]+', text)
    return [s.strip() for s in sentences if s.strip() and len(s.strip()) > 20][:10]

def wrap_text(text, width=40):
    if len(text) <= width:
        return text
    words = text.split()
    lines = []
    current = ""
    for word in words:
        if len(current) + len(word) + 1 <= width:
            current = current + " " + word if current else word
        else:
            if current:
                lines.append(current)
            current = word
    if current:
        lines.append(current)
    return "\n".join(lines)

def get_pos(word):
    pos = 'adj.'
    if word.endswith('tion') or word.endswith('sion'):
        pos = 'n.'
    elif word.endswith('ly'):
        pos = 'adv.'
    elif word.endswith('ing'):
        pos = 'n./v.'
    elif word.endswith('ed'):
        pos = 'v.'
    elif word.endswith('er') or word.endswith('or'):
        pos = 'n.'
    return pos

def save_bilingual_txt(article, base_path):
    txt_file = str(base_path) + '_trans.txt'
    with open(txt_file, 'w', encoding='utf-8') as f:
        f.write(f"TITLE: {article['title']}\n")
        f.write(f"DIFFICULTY: {article['difficulty']}\n")
        f.write(f"WORD_COUNT: {article['word_count']}\n")
        f.write(f"DATE: {datetime.now().strftime('%Y-%m-%d')}\n")
        f.write("---\n")
        f.write("ORIGINAL:\n")
        f.write(article['original'] + "\n")
        f.write("---\n")
        f.write("TRANSLATION:\n")
        f.write(article['translation'] + "\n")
        f.write("---\n")
        f.write("VOCABULARY:\n")
        for v in article['vocabulary']:
            f.write(f"{v['word']}|{v['pos']}|{v['meaning']}|{v['example']}\n")
        f.write("---\n")
        f.write("SENTENCES:\n")
        for s in article['sentences']:
            f.write(f"{s['original']}|{s['translation']}\n")
    print(f"   txt: {txt_file}")
    return txt_file

def load_bilingual_txt(txt_file):
    article = {
        'title': '', 'difficulty': 'intermediate', 'word_count': 0,
        'original': '', 'translation': '', 'vocabulary': [], 'sentences': []
    }
    section = None
    original_lines = []
    translation_lines = []
    
    with open(txt_file, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.rstrip('\n')
            if line.startswith('TITLE:'):
                article['title'] = line.replace('TITLE:', '').strip()
            elif line.startswith('DIFFICULTY:'):
                article['difficulty'] = line.replace('DIFFICULTY:', '').strip()
            elif line.startswith('WORD_COUNT:'):
                article['word_count'] = int(line.replace('WORD_COUNT:', '').strip())
            elif line == '---':
                section = None
            elif line == 'ORIGINAL:':
                section = 'original'
                original_lines = []
            elif line == 'TRANSLATION:':
                section = 'translation'
                translation_lines = []
            elif line == 'VOCABULARY:':
                section = 'vocabulary'
            elif line == 'SENTENCES:':
                section = 'sentences'
            elif section == 'original':
                original_lines.append(line)
            elif section == 'translation':
                translation_lines.append(line)
            elif section == 'vocabulary' and '|' in line:
                parts = line.split('|', 3)
                if len(parts) >= 3:
                    article['vocabulary'].append({'word': parts[0], 'pos': parts[1], 'meaning': parts[2], 'example': parts[3] if len(parts) > 3 else ''})
            elif section == 'sentences' and '|' in line:
                parts = line.split('|', 1)
                if len(parts) >= 2:
                    article['sentences'].append({'original': parts[0], 'translation': parts[1]})
    
    article['original'] = '\n'.join(original_lines)
    article['translation'] = '\n'.join(translation_lines)
    return article

def save_md(article, base_path):
    md_file = str(base_path) + '.md'
    md = f"""# {article['title']}

> 生成时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
> 难度: {article['difficulty']}
> 字数: {article['word_count']}

---

## 原文

{article['original']}

---

## 译文

{article['translation']}

---

## 词汇表

| 单词 | 词性 | 释义 | 例句 |
|------|------|------|------|
"""
    for v in article['vocabulary']:
        example = wrap_text(v['example'], 30)
        md += f"| **{v['word']}** | {v['pos']} | {v['meaning']} | {example} |\n"
    md += "\n---\n## 精彩句子\n\n"
    for i, s in enumerate(article['sentences'], 1):
        md += f"**{i}.** {s['original']}\n\n> {s['translation']}\n\n"
    md += "\n---\n*Generated by WordCard*"
    with open(md_file, 'w', encoding='utf-8') as f:
        f.write(md)
    print(f"   md: {md_file}")
    return md_file

def save_pdf(article, base_path):
    pdf_file = str(base_path) + '.pdf'
    
    try:
        from fpdf import FPDF
        
        class MyPDF(FPDF):
            def header(self):
                self.set_font("Helvetica", size=8)
                self.cell(0, 5, "WordCard", align="R")
                self.ln(5)
            
            def footer(self):
                self.set_y(-15)
                self.set_font("Helvetica", size=8)
                self.cell(0, 10, f"Page {self.page_no()}", align="C")
        
        pdf = MyPDF(unit="mm", format=(90, 160))
        pdf.add_page()
        pdf.add_font("LXGW", "", "LXGWWenKaiMono-Light.ttf", uni=True)
        
        pdf.set_font("LXGW", size=16)
        pdf.cell(0, 10, article['title'], align="C", new_x="LMARGIN", new_y="NEXT")
        pdf.ln(5)
        
        pdf.set_font("LXGW", size=9)
        pdf.cell(0, 5, f"难度: {article['difficulty']} | 词数: {article['word_count']}", align="C", new_x="LMARGIN", new_y="NEXT")
        pdf.cell(0, 5, f"词汇: {len(article['vocabulary'])}个 | 句子: {len(article['sentences'])}句", align="C", new_x="LMARGIN", new_y="NEXT")
        
        pdf.add_page()
        pdf.set_font("LXGW", size=12)
        pdf.cell(0, 8, "原文", new_x="LMARGIN", new_y="NEXT")
        pdf.line(10, pdf.get_y(), 80, pdf.get_y())
        pdf.ln(3)
        
        pdf.set_font("LXGW", size=9)
        original_text = article['original'].replace('\n', ' ')[:800]
        pdf.multi_cell(0, 5, original_text)
        
        pdf.add_page()
        pdf.set_font("LXGW", size=12)
        pdf.cell(0, 8, "译文", new_x="LMARGIN", new_y="NEXT")
        pdf.line(10, pdf.get_y(), 80, pdf.get_y())
        pdf.ln(3)
        
        pdf.set_font("LXGW", size=9)
        trans_text = article['translation'].replace('\n', ' ')[:800]
        pdf.multi_cell(0, 5, trans_text)
        
        pdf.add_page()
        pdf.set_font("LXGW", size=12)
        pdf.cell(0, 8, f"词汇表 ({len(article['vocabulary'])}词)", new_x="LMARGIN", new_y="NEXT")
        pdf.line(10, pdf.get_y(), 80, pdf.get_y())
        pdf.ln(3)
        
        pdf.set_font("LXGW", size=8)
        for v in article['vocabulary'][:18]:
            pdf.set_font("LXGW", size=9)
            pdf.cell(25, 5, v['word'], 0, 0, "L")
            pdf.set_font("LXGW", size=8)
            pdf.cell(15, 5, f"({v['pos']})", 0, 0, "L")
            pdf.ln(4)
            pdf.multi_cell(0, 4, v['meaning'])
            pdf.ln(1)
        
        pdf.add_page()
        pdf.set_font("LXGW", size=12)
        pdf.cell(0, 8, "精彩句子", new_x="LMARGIN", new_y="NEXT")
        pdf.line(10, pdf.get_y(), 80, pdf.get_y())
        pdf.ln(3)
        
        pdf.set_font("LXGW", size=8)
        for i, s in enumerate(article['sentences'][:6], 1):
            pdf.set_font("LXGW", size=9)
            pdf.cell(0, 5, f"{i}.", new_x="LMARGIN", new_y="NEXT")
            pdf.multi_cell(0, 4, s['original'][:80])
            pdf.set_font("LXGW", size=8)
            pdf.set_text_color(100, 100, 100)
            pdf.multi_cell(0, 4, s['translation'][:80])
            pdf.set_text_color(0, 0, 0)
            pdf.ln(2)
        
        pdf.output(pdf_file)
        print(f"   pdf: {pdf_file}")
        return pdf_file
        
    except Exception as e:
        print(f"   pdf: 跳过 ({e})")
        return None

def save_png(article, base_path):
    cards_dir = str(base_path) + '_cards'
    os.makedirs(cards_dir, exist_ok=True)
    
    try:
        from PIL import Image, ImageDraw, ImageFont
        
        def text_wrap_pil(text, max_width, font):
            lines = []
            words = text.split()
            current_line = ""
            for word in words:
                test_line = current_line + " " + word if current_line else word
                bbox = font.getbbox(test_line)
                if bbox[2] - bbox[0] <= max_width - 40:
                    current_line = test_line
                else:
                    if current_line:
                        lines.append(current_line)
                    current_line = word
            if current_line:
                lines.append(current_line)
            return lines
        
        def draw_card(texts, filename, title=""):
            img = Image.new('RGB', (CARD_WIDTH, CARD_HEIGHT), COLORS['bg'])
            draw = ImageDraw.Draw(img)
            try:
                font_title = ImageFont.truetype(FONT_PATH, 28)
                font_header = ImageFont.truetype(FONT_PATH, 16)
                font_text = ImageFont.truetype(FONT_PATH, 14)
                font_small = ImageFont.truetype(FONT_PATH, 12)
            except:
                font_title = ImageFont.load_default()
                font_header = ImageFont.load_default()
                font_text = ImageFont.load_default()
                font_small = ImageFont.load_default()
            
            draw.text((20, 20), "WordCard", font=font_header, fill=COLORS['accent'])
            if title:
                bbox = font_title.getbbox(title)
                draw.text(((CARD_WIDTH - (bbox[2] - bbox[0])) // 2, 50), title, font=font_title, fill=COLORS['title'])
            
            y = 90
            for text in texts:
                lines = text_wrap_pil(text, CARD_WIDTH - 60, font_text)
                for line in lines:
                    if y > CARD_HEIGHT - 40:
                        break
                    bbox = font_text.getbbox(line)
                    draw.text((40, y), line, font=font_text, fill=COLORS['text'])
                    y += bbox[3] - bbox[1] + 8
            
            draw.text((CARD_WIDTH - 80, CARD_HEIGHT - 25), filename.split('.')[0], font=font_small, fill=COLORS['translation'])
            img.save(cards_dir + '/' + filename)
            print(f"   {filename}: {cards_dir}/{filename}")
        
        cover_texts = [f"难度: {article['difficulty']}", f"单词数: {article['word_count']}", 
                      f"词汇: {len(article['vocabulary'])}个", f"句子: {len(article['sentences'])}句"]
        draw_card(cover_texts, '01_cover.png', article['title'])
        
        vocab_texts = [f"{v['word']} ({v['pos']}) - {v['meaning']}" for v in article['vocabulary'][:10]]
        draw_card(vocab_texts, '02_vocab.png', "词汇表")
        
        sentence_texts = [f"{i}. {s['original'][:50]}..." for i, s in enumerate(article['sentences'][:5], 1)]
        draw_card(sentence_texts, '03_sentences.png', "精彩句子")
        
        return cards_dir
    except ImportError:
        print(f"   png: 跳过 (pip install pillow)")
        return None

def main():
    if len(sys.argv) < 2:
        print("用法: python article_card.py 文章.txt")
        print("输出: 当前目录下的 md/pdf/png 文件")
        return
    
    input_file = sys.argv[1]
    input_path = Path(input_file)
    
    if not input_path.exists():
        print(f"文件不存在: {input_file}")
        return
    
    base_path = input_path.with_suffix('')
    txt_file = str(base_path) + '_trans.txt'
    
    if Path(txt_file).exists():
        print(f"检测到双语txt文件: {txt_file}")
        print(f"跳过翻译，直接生成卡片...\n")
        article = load_bilingual_txt(txt_file)
    else:
        print(f"读取文章: {input_path.name}")
        with open(input_path, 'r', encoding='utf-8') as f:
            original = f.read()
        word_count = len(original.split())
        print(f"字数: {word_count}")
        
        print("加载翻译模型...")
        translator, tokenizer = load_translator()
        print("翻译中...")
        translation = translate_batch(translator, tokenizer, [original], target_lang='zho_Hans')[0]
        
        print("提取词汇...")
        words = extract_words(original, min_len=4, max_count=30)
        
        print("提取句子...")
        sentences = split_sentences(original)
        
        print("翻译词汇...")
        vocab_list = [{'word': w, 'pos': get_pos(w), 'meaning': translate_batch(translator, tokenizer, [w], target_lang='zho_Hans')[0], 'example': f'This word is {w}.'} for w in words]
        
        print("翻译句子...")
        sent_list = [{'original': s, 'translation': translate_batch(translator, tokenizer, [s], target_lang='zho_Hans')[0]} for s in sentences]
        
        cleanup_translator(translator, tokenizer)
        
        article = {
            'title': input_path.stem.replace('_', ' ').replace('-', ' ').title(),
            'original': original,
            'translation': translation,
            'vocabulary': vocab_list,
            'sentences': sent_list,
            'difficulty': 'intermediate',
            'word_count': word_count
        }
        
        print("\n保存双语txt...")
        save_bilingual_txt(article, base_path)
    
    print("\n生成卡片...")
    print("="*40)
    save_md(article, base_path)
    save_pdf(article, base_path)
    save_png(article, base_path)
    
    print("\n完成!")

if __name__ == '__main__':
    main()
