#!/usr/bin/env python3
"""
生成中英双语文章卡片
输出 MD + PDF + PNG 图片格式
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

def load_translator():
    """加载翻译模型"""
    translator = ctranslate2.Translator(MODEL_DIR, device="cuda")
    tokenizer = transformers.AutoTokenizer.from_pretrained(MODEL_DIR)
    return translator, tokenizer

def cleanup_translator(translator, tokenizer):
    """释放GPU内存"""
    import torch
    del translator
    del tokenizer
    torch.cuda.empty_cache()

def translate_batch(translator, tokenizer, texts, target_lang='zho_Hans'):
    """批量翻译"""
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
    """提取词汇"""
    words = re.findall(r'\b[a-zA-Z]+\b', text.lower())
    word_count = {}
    for word in words:
        if len(word) >= min_len and not word.isdigit():
            word_count[word] = word_count.get(word, 0) + 1
    
    sorted_words = sorted(word_count.items(), key=lambda x: x[1], reverse=True)
    return [w[0] for w in sorted_words[:max_count]]

def split_sentences(text):
    """分割句子"""
    sentences = re.split(r'[.!?]+', text)
    result = [s.strip() for s in sentences if s.strip() and len(s.strip()) > 20]
    return result[:10]

def wrap_text(text, width=40):
    """文本换行"""
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

def create_md_content(article):
    """生成MD内容"""
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

    md += """

---

## 精彩句子

"""

    for i, s in enumerate(article['sentences'], 1):
        md += f"**{i}.** {s['original']}\n\n> {s['translation']}\n\n"""

    return md

def article_to_card(input_file, output_dir='./output', difficulty='intermediate'):
    """主函数：文章转卡片"""
    
    input_path = Path(input_file)
    output_path = Path(output_dir) / input_path.stem
    output_path.mkdir(parents=True, exist_ok=True)
    
    cards_path = output_path / 'cards'
    cards_path.mkdir(exist_ok=True)
    
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
    
    print("提取精彩句子...")
    sentences = split_sentences(original)
    
    print("翻译词汇...")
    vocab_list = []
    for w in words:
        trans = translate_batch(translator, tokenizer, [w], target_lang='zho_Hans')[0]
        
        pos = 'adj.'
        if w.endswith('tion') or w.endswith('sion'):
            pos = 'n.'
        elif w.endswith('ly'):
            pos = 'adv.'
        elif w.endswith('ing'):
            pos = 'n./v.'
        elif w.endswith('ed'):
            pos = 'v.'
        elif w.endswith('er') or w.endswith('or'):
            pos = 'n.'
        
        vocab_list.append({
            'word': w,
            'pos': pos,
            'meaning': trans,
            'example': f'This word is {w}.'
        })
    
    print("翻译句子...")
    sent_list = []
    for s in sentences:
        trans = translate_batch(translator, tokenizer, [s], target_lang='zho_Hans')[0]
        sent_list.append({
            'original': s,
            'translation': trans
        })
    
    cleanup_translator(translator, tokenizer)
    
    article = {
        'title': input_path.stem.replace('_', ' ').replace('-', ' ').title(),
        'original': original,
        'translation': translation,
        'vocabulary': vocab_list,
        'sentences': sent_list,
        'difficulty': difficulty,
        'word_count': word_count
    }
    
    print("\n生成文件...")
    
    print("1/3 生成MD...")
    md_content = create_md_content(article)
    md_file = output_path / f"{input_path.stem}.md"
    with open(md_file, 'w', encoding='utf-8') as f:
        f.write(md_content)
    print(f"   MD: {md_file}")
    
    print("2/3 生成PDF... 跳过 (Windows需要系统依赖)")
    print("3/3 生成PNG...")
    try:
        from PIL import Image, ImageDraw, ImageFont
        
        def text_wrap_pil(text, max_width, font):
            """文本换行"""
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
            """绘制卡片"""
            img = Image.new('RGB', (CARD_WIDTH, CARD_HEIGHT), COLORS['bg'])
            draw = ImageDraw.Draw(img)
            
            try:
                font_path = "C:\\Users\\Administrator\\AppData\\Local\\Microsoft\\Windows\\Fonts\\LXGWWenKaiMono-Light.ttf"
                font_title = ImageFont.truetype(font_path, 28)
                font_header = ImageFont.truetype(font_path, 16)
                font_text = ImageFont.truetype(font_path, 14)
                font_small = ImageFont.truetype(font_path, 12)
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
            
            img.save(cards_path / filename)
            print(f"   {filename}: {cards_path / filename}")
        
        cover_texts = [
            f"难度: {article['difficulty']}",
            f"单词数: {article['word_count']}",
            f"词汇: {len(article['vocabulary'])}个",
            f"句子: {len(article['sentences'])}句"
        ]
        draw_card(cover_texts, '01_cover.png', article['title'])
        
        vocab_texts = []
        for v in article['vocabulary'][:10]:
            vocab_texts.append(f"{v['word']} ({v['pos']}) - {v['meaning']}")
        draw_card(vocab_texts, '02_vocab.png', "词汇表")
        
        sentence_texts = []
        for i, s in enumerate(article['sentences'][:5], 1):
            sentence_texts.append(f"{i}. {s['original'][:50]}...")
        draw_card(sentence_texts, '03_sentences.png', "精彩句子")
        
    except ImportError as e:
        print(f"   PNG跳过 (pip install pillow): {e}")
    
    print(f"\n完成! 输出目录: {output_path}")
    print(f"  - MD: {md_file.name if 'md_file' in dir() else 'N/A'}")
    print(f"  - PDF: {pdf_file.name if pdf_file else 'N/A'}")
    print(f"  - PNG: {cards_path}/")

def main():
    parser = argparse.ArgumentParser(description='生成中英双语文章卡片')
    parser.add_argument('input', help='输入文章文件')
    parser.add_argument('-o', '--output', default='./output', help='输出目录')
    parser.add_argument('-d', '--difficulty', default='intermediate', help='难度')
    
    args = parser.parse_args()
    
    article_to_card(args.input, args.output, args.difficulty)

if __name__ == '__main__':
    main()
