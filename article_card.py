#!/usr/bin/env python3
"""
生成中英双语文章卡片
分两步：
1. python article_card.py article.txt --step=translate  (翻译生成双语txt)
2. python article_card.py article.txt --step=render     (从txt生成md/pdf/png)
"""

import warnings
warnings.filterwarnings('ignore')

import os
import sys
import re
import argparse
import json
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

FONT_PATH = "C:\\Users\\Administrator\\AppData\\Local\\Microsoft\\Windows\\Fonts\\LXGWWenKaiMono-Light.ttf"

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

def generate_bilingual_txt(article, output_path):
    """生成双语txt文件"""
    txt_file = output_path / f"{article['title'].replace(' ', '_')}.txt"
    
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
    
    print(f"   双语txt: {txt_file}")
    return txt_file

def parse_bilingual_txt(txt_file):
    """解析双语txt文件"""
    article = {
        'title': '',
        'difficulty': 'intermediate',
        'word_count': 0,
        'original': '',
        'translation': '',
        'vocabulary': [],
        'sentences': []
    }
    
    section = None
    
    with open(txt_file, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            
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
            elif line == 'TRANSLATION:':
                section = 'translation'
            elif line == 'VOCABULARY:':
                section = 'vocabulary'
            elif line == 'SENTENCES:':
                section = 'sentences'
            elif section == 'original':
                article['original'] = line
            elif section == 'translation':
                article['translation'] = line
            elif section == 'vocabulary':
                if line and '|' in line:
                    parts = line.split('|', 3)
                    if len(parts) >= 3:
                        article['vocabulary'].append({
                            'word': parts[0],
                            'pos': parts[1],
                            'meaning': parts[2],
                            'example': parts[3] if len(parts) > 3 else ''
                        })
            elif section == 'sentences':
                if line and '|' in line:
                    parts = line.split('|', 1)
                    if len(parts) >= 2:
                        article['sentences'].append({
                            'original': parts[0],
                            'translation': parts[1]
                        })
    
    return article

def generate_md(article, output_path):
    """生成MD文件"""
    md_file = output_path / f"{article['title'].replace(' ', '_')}.md"
    
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
        md += f"**{i}.** {s['original']}\n\n> {s['translation']}\n\n"

    md += "\n---\n*Generated by WordCard*"

    with open(md_file, 'w', encoding='utf-8') as f:
        f.write(md)
    
    print(f"   MD: {md_file}")
    return md_file

def generate_pdf(article, output_path):
    """生成PDF文件"""
    pdf_file = output_path / f"{article['title'].replace(' ', '_')}.pdf"
    
    try:
        from weasyprint import HTML
        
        pdf_html = f"""<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>{article['title']}</title>
    <style>
        @font-face {{
            font-family: 'LXGW';
            src: url('LXGWWenKaiMono-Light.ttf') format('truetype');
        }}
        * {{ margin: 0; padding: 0; box-sizing: border-box; }}
        body {{
            font-family: 'LXGW', 'Microsoft YaHei', sans-serif;
            font-size: 14px;
            line-height: 1.8;
            color: {COLORS['text']};
            background: {COLORS['bg']};
        }}
        .page {{
            width: 375px;
            min-height: 667px;
            padding: 20px;
            background: {COLORS['bg']};
            margin: 0 auto;
            page-break-after: always;
        }}
        .cover {{
            display: flex;
            flex-direction: column;
            justify-content: center;
            align-items: center;
            text-align: center;
            background: linear-gradient(135deg, {COLORS['bg']} 0%, #FAFAFA 100%);
        }}
        .title {{
            font-size: 28px;
            font-weight: bold;
            color: {COLORS['title']};
            margin-bottom: 20px;
        }}
        .meta {{
            font-size: 12px;
            color: {COLORS['translation']};
            margin-top: 10px;
        }}
        .section-title {{
            font-size: 18px;
            font-weight: bold;
            color: {COLORS['accent']};
            margin: 20px 0 10px 0;
            padding-bottom: 5px;
            border-bottom: 2px solid {COLORS['accent']};
        }}
        .content {{
            font-size: 14px;
            line-height: 1.8;
            text-indent: 2em;
        }}
        .vocab-item {{
            background: {COLORS['card_bg']};
            padding: 10px;
            border-radius: 8px;
            margin: 8px 0;
        }}
        .word {{
            font-weight: bold;
            color: {COLORS['highlight']};
        }}
        .pos {{
            color: {COLORS['accent']};
            margin-left: 5px;
        }}
        .meaning {{
            font-size: 12px;
            color: {COLORS['translation']};
        }}
        .footer {{
            text-align: center;
            margin-top: 20px;
            font-size: 10px;
            color: {COLORS['translation']};
        }}
    </style>
</head>
<body>
    <div class="page cover">
        <div class="title">{article['title']}</div>
        <div class="meta">
            <p>难度: {article['difficulty']}</p>
            <p>单词数: {article['word_count']}</p>
            <p>词汇: {len(article['vocabulary'])}个</p>
            <p>句子: {len(article['sentences'])}句</p>
            <p style="margin-top: 30px;">{datetime.now().strftime('%Y-%m-%d')}</p>
        </div>
    </div>
    
    <div class="page">
        <div class="section-title">原文</div>
        <div class="content">{article['original'].replace(chr(10), '<br>')[:1500]}</div>
        <div class="footer">Page 2</div>
    </div>
    
    <div class="page">
        <div class="section-title">译文</div>
        <div class="content">{article['translation'].replace(chr(10), '<br>')[:1500]}</div>
        <div class="footer">Page 3</div>
    </div>
    
    <div class="page">
        <div class="section-title">词汇表 ({len(article['vocabulary'])}词)</div>
"""

        for v in article['vocabulary'][:15]:
            pdf_html += f"""
        <div class="vocab-item">
            <span class="word">{v['word']}</span> <span class="pos">{v['pos']}</span>
            <div class="meaning">{v['meaning']}</div>
        </div>
"""

        pdf_html += """
        <div class="footer">Page 4</div>
    </div>
    
    <div class="page">
        <div class="section-title">精彩句子</div>
"""

        for i, s in enumerate(article['sentences'][:5], 1):
            pdf_html += f"""
        <div class="vocab-item">
            <div>{i}. {s['original']}</div>
            <div class="meaning">{s['translation']}</div>
        </div>
"""

        pdf_html += """
        <div class="footer">Page 5</div>
    </div>
</body>
</html>"""
        
        HTML(string=pdf_html).write_pdf(pdf_file)
        print(f"   PDF: {pdf_file}")
        return pdf_file
        
    except ImportError as e:
        print(f"   PDF跳过: 需要安装 weasyprint")
        return None

def generate_png(article, output_path):
    """生成PNG图片卡片"""
    cards_path = output_path / 'cards'
    cards_path.mkdir(exist_ok=True)
    
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
        
        return cards_path
        
    except ImportError as e:
        print(f"   PNG跳过: pip install pillow")
        return None

def step_translate(input_file, output_dir='./output', difficulty='intermediate'):
    """步骤1：翻译生成双语txt"""
    input_path = Path(input_file)
    output_path = Path(output_dir) / input_path.stem
    output_path.mkdir(parents=True, exist_ok=True)
    
    txt_file = output_path / f"{input_path.stem}.txt"
    if txt_file.exists():
        print(f"双语txt已存在: {txt_file}")
        print("如需重新翻译，请删除该文件")
        return
    
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
    
    print("\n保存双语txt...")
    generate_bilingual_txt(article, output_path)
    
    print("\n翻译完成!")
    print(f"输出目录: {output_path}")
    print(f"下一步: python article_card.py {input_file} --step=render")

def step_render(input_file, output_dir='./output'):
    """步骤2：从txt生成md/pdf/png"""
    input_path = Path(input_file)
    output_path = Path(output_dir) / input_path.stem
    
    txt_file = None
    for f in output_path.glob('*.txt'):
        txt_file = f
        break
    
    if not txt_file:
        print(f"未找到双语txt文件: {output_path}")
        print(f"请先运行: python article_card.py {input_file} --step=translate")
        return
    
    print(f"读取双语txt: {txt_file.name}")
    
    article = parse_bilingual_txt(txt_file)
    print(f"标题: {article['title']}")
    print(f"词汇: {len(article['vocabulary'])}个")
    print(f"句子: {len(article['sentences'])}句")
    
    print("\n生成文件...")
    
    print("1/3 生成MD...")
    generate_md(article, output_path)
    
    print("2/3 生成PDF...")
    generate_pdf(article, output_path)
    
    print("3/3 生成PNG...")
    generate_png(article, output_path)
    
    print(f"\n完成! 输出目录: {output_path}")

def main():
    parser = argparse.ArgumentParser(description='生成中英双语文章卡片')
    parser.add_argument('input', help='输入文章文件')
    parser.add_argument('-o', '--output', default='./output', help='输出目录')
    parser.add_argument('-d', '--difficulty', default='intermediate', help='难度')
    
    args = parser.parse_args()
    
    input_path = Path(args.input)
    output_path = Path(args.output) / input_path.stem
    output_path.mkdir(parents=True, exist_ok=True)
    
    txt_file = output_path / f"{input_path.stem}.txt"
    
    if txt_file.exists():
        print(f"检测到双语txt文件: {txt_file.name}")
        print(f"跳过翻译，直接生成卡片...\n")
        step_render(args.input, args.output)
    else:
        print(f"未检测到双语txt文件，开始翻译...\n")
        step_translate(args.input, args.output, args.difficulty)
        print("\n" + "="*50)
        print("翻译完成，现在生成卡片...")
        print("="*50 + "\n")
        step_render(args.input, args.output)

if __name__ == '__main__':
    main()
