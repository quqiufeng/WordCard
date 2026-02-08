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
    """批量翻译 - 参考translate.py实现"""
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

def create_pdf_html(article, is_single=False):
    """生成PDF HTML"""
    original_lines = article['original'].replace('\n\n', '\n').split('\n')[:30]
    translation_lines = article['translation'].replace('\n\n', '\n').split('\n')[:30]
    
    vocab_html = ""
    for v in article['vocabulary'][:20]:
        vocab_html += f"""
        <div class="vocab-item">
            <span class="word">{v['word']}</span>
            <span class="pos">{v['pos']}</span>
            <span class="meaning">{v['meaning']}</span>
        </div>
        """

    return f"""<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <style>
        @font-face {{
            font-family: 'SourceHanSans';
            src: url('SourceHanSansSC-Regular.otf') format('opentype');
        }}
        * {{ margin: 0; padding: 0; box-sizing: border-box; }}
        body {{
            font-family: 'SourceHanSans', '思源黑体', 'Microsoft YaHei', sans-serif;
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
            background: linear-gradient(135deg, {COLORS['bg']} 0%, {COLORS['card_bg']} 100%);
        }}
        .title {{
            font-size: 28px;
            font-weight: bold;
            color: {COLORS['title']};
            margin-bottom: 20px;
        }}
        .subtitle {{
            font-size: 14px;
            color: {COLORS['translation']};
            margin-bottom: 40px;
        }}
        .meta {{
            font-size: 12px;
            color: {COLORS['translation']};
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
            text-align: justify;
        }}
        .vocab-grid {{
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 10px;
        }}
        .vocab-item {{
            background: {COLORS['card_bg']};
            padding: 10px;
            border-radius: 8px;
            font-size: 12px;
        }}
        .word {{
            font-weight: bold;
            color: {COLORS['highlight']};
            font-size: 14px;
        }}
        .pos {{
            color: {COLORS['accent']};
            margin-left: 5px;
        }}
        .meaning {{
            color: {COLORS['text']};
            margin-top: 3px;
        }}
        .sentence {{
            background: {COLORS['card_bg']};
            padding: 12px;
            border-radius: 8px;
            margin: 8px 0;
        }}
        .sentence-en {{
            font-size: 13px;
            color: {COLORS['text']};
        }}
        .sentence-zh {{
            font-size: 12px;
            color: {COLORS['translation']};
            margin-top: 5px;
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
"""

def generate_cover_page(article):
    """封面页"""
    return f"""
    <div class="page cover">
        <div class="title">{article['title']}</div>
        <div class="subtitle">WordCard · 英语学习</div>
        <div class="meta">
            <p>难度: {article['difficulty']}</p>
            <p>单词数: {article['word_count']}</p>
            <p>词汇: {len(article['vocabulary'])}个</p>
            <p>句子: {len(article['sentences'])}句</p>
            <p style="margin-top: 30px;">{datetime.now().strftime('%Y-%m-%d')}</p>
        </div>
    </div>
"""

def generate_original_page(article):
    """原文页"""
    content = article['original'].replace('\n\n', '\n')
    lines = [wrap_text(line, 35) for line in content.split('\n')[:40]]
    content_html = '<br>'.join(lines)
    
    return f"""
    <div class="page">
        <div class="section-title">原文</div>
        <div class="content">{content_html}</div>
        <div class="footer">Page 2</div>
    </div>
"""

def generate_translation_page(article):
    """译文页"""
    content = article['translation'].replace('\n\n', '\n')
    lines = [wrap_text(line, 35) for line in content.split('\n')[:40]]
    content_html = '<br>'.join(lines)
    
    return f"""
    <div class="page">
        <div class="section-title">译文</div>
        <div class="content">{content_html}</div>
        <div class="footer">Page 3</div>
    </div>
"""

def generate_vocab_page(article):
    """词汇页"""
    vocab_html = ""
    for v in article['vocabulary'][:30]:
        vocab_html += f"""
        <div class="sentence">
            <div class="sentence-en"><span class="word">{v['word']}</span> <span class="pos">{v['pos']}</span></div>
            <div class="sentence-zh">{v['meaning']}</div>
        </div>
        """
    
    return f"""
    <div class="page">
        <div class="section-title">词汇表 ({len(article['vocabulary'])}词)</div>
        {vocab_html}
        <div class="footer">Page 4</div>
    </div>
"""

def generate_sentences_page(article):
    """精彩句子页"""
    sentences_html = ""
    for s in article['sentences']:
        sentences_html += f"""
        <div class="sentence">
            <div class="sentence-en">{s['original']}</div>
            <div class="sentence-zh">{s['translation']}</div>
        </div>
        """
    
    return f"""
    <div class="page">
        <div class="section-title">精彩句子</div>
        {sentences_html}
        <div class="footer">Page 5</div>
    </div>
"""

def generate_image_html(article, page_type):
    """生成单页图片HTML"""
    return f"""<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <style>
        @font-face {{
            font-family: 'SourceHanSans';
            src: url('SourceHanSansSC-Regular.otf') format('opentype');
        }}
        * {{ margin: 0; padding: 0; box-sizing: border-box; }}
        body {{
            width: {CARD_WIDTH}px;
            height: {CARD_HEIGHT}px;
            font-family: 'SourceHanSans', '思源黑体', 'Microsoft YaHei', sans-serif;
            font-size: 14px;
            line-height: 1.8;
            color: {COLORS['text']};
            background: {COLORS['bg']};
            overflow: hidden;
        }}
        .card {{
            width: 100%;
            height: 100%;
            padding: 20px;
            background: linear-gradient(135deg, {COLORS['bg']} 0%, #FAFAFA 100%);
            display: flex;
            flex-direction: column;
        }}
        .header {{
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 15px;
            padding-bottom: 10px;
            border-bottom: 1px solid {COLORS['border']};
        }}
        .logo {{
            font-size: 12px;
            color: {COLORS['accent']};
            font-weight: bold;
        }}
        .page-num {{
            font-size: 10px;
            color: {COLORS['translation']};
        }}
        .title {{
            font-size: 20px;
            font-weight: bold;
            color: {COLORS['title']};
            margin-bottom: 10px;
        }}
        .section-title {{
            font-size: 14px;
            font-weight: bold;
            color: {COLORS['accent']};
            margin: 12px 0 8px 0;
        }}
        .content {{
            font-size: 13px;
            line-height: 1.8;
            text-indent: 2em;
            flex: 1;
            overflow: hidden;
        }}
        .footer {{
            text-align: center;
            font-size: 10px;
            color: {COLORS['translation']};
            padding-top: 10px;
            border-top: 1px solid {COLORS['border']};
        }}
    </style>
</head>
<body>
    <div class="card">
        <div class="header">
            <span class="logo">WordCard</span>
            <span class="page-num">{page_type}</span>
        </div>
"""

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
    
    print("2/3 生成PDF...")
    try:
        from weasyprint import HTML
        
        html = create_pdf_html(article)
        html += generate_cover_page(article)
        html += generate_original_page(article)
        html += generate_translation_page(article)
        html += generate_vocab_page(article)
        html += generate_sentences_page(article)
        html += "</body></html>"
        
        pdf_file = output_path / f"{input_path.stem}.pdf"
        HTML(string=html).write_pdf(pdf_file, stylesheets=[html])
        print(f"   PDF: {pdf_file}")
    except ImportError:
        print("   PDF跳过 (pip install weasyprint)")
    
    print("3/3 生成PNG...")
    try:
        from PIL import Image, ImageDraw, ImageFont
        
        def render_card(html_content, filename):
            from weasyprint import HTML
            html = f"""<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <style>
        @font-face {{
            font-family: 'SourceHanSans';
            src: url('SourceHanSansSC-Regular.otf') format('opentype');
        }}
        * {{ margin: 0; padding: 0; box-sizing: border-box; }}
        body {{
            width: {CARD_WIDTH}px;
            height: {CARD_HEIGHT}px;
            font-family: 'SourceHanSans', '思源黑体', sans-serif;
            font-size: 14px;
            line-height: 1.8;
            color: {COLORS['text']};
            background: {COLORS['bg']};
            padding: 20px;
        }}
        .title {{
            font-size: 22px;
            font-weight: bold;
            color: {COLORS['title']};
            text-align: center;
            margin-bottom: 15px;
        }}
        .section-title {{
            font-size: 14px;
            font-weight: bold;
            color: {COLORS['accent']};
            margin: 10px 0;
        }}
        .content {{
            font-size: 13px;
            line-height: 1.8;
            text-indent: 2em;
        }}
        .vocab-item {{
            background: {COLORS['card_bg']};
            padding: 8px;
            border-radius: 6px;
            margin: 5px 0;
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
    </style>
</head>
<body>
{html_content}
</body>
</html>"""
            
            png_file = cards_path / filename
            HTML(string=html, base_url=str(output_path)).write_png(png_file)
            print(f"   {filename}: {png_file}")
        
        cover_content = f'<div class="title">{article["title"]}</div><div style="text-align:center;color:{COLORS["translation"]};margin-top:30px;"><p>难度: {article["difficulty"]}</p><p>单词: {len(article["vocabulary"])}</p></div>'
        render_card(cover_content, '01_cover.png')
        
        vocab_content = '<div class="section-title">词汇表</div>'
        for v in article['vocabulary'][:15]:
            vocab_content += f'<div class="vocab-item"><span class="word">{v["word"]}</span> <span class="pos">{v["pos"]}</span><div class="meaning">{v["meaning"]}</div></div>'
        render_card(vocab_content, '02_vocab.png')
        
        sentences_content = '<div class="section-title">精彩句子</div>'
        for s in article['sentences'][:5]:
            sentences_content += f'<div class="vocab-item">{s["original"]}<div class="meaning">{s["translation"]}</div></div>'
        render_card(sentences_content, '03_sentences.png')
        
    except ImportError as e:
        print(f"   PNG跳过 (pip install weasyprint pillow): {e}")
    
    print(f"\n完成! 输出目录: {output_path}")
    print(f"  - MD: {md_file.name}")
    print(f"  - PDF: {pdf_file.name if 'pdf_file' in dir() else 'N/A'}")
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
