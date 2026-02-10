#!/usr/bin/env python3
"""
Ollama 翻译脚本 - 使用远程 Ollama 服务
支持 qwen2.5-7b-instruct 等模型

配置：
- OLLAMA_HOST=http://192.168.124.3:11434/v1
- MODEL=qwen2.5-7b-instruct
"""

import warnings
warnings.filterwarnings('ignore')

import requests
import time
import sys
from pathlib import Path
from tqdm import tqdm

# Ollama 配置
OLLAMA_HOST = "http://192.168.124.3:11434/v1"
MODEL = "qwen2.5-7b-instruct"

EN_WRAP = 65
ZH_WRAP = 40


def translate_ollama(text, source_lang="English", target_lang="Chinese"):
    """调用 Ollama API 翻译文本"""
    url = f"{OLLAMA_HOST}/chat/completions"
    
    prompt = f"""Translate the following {source_lang} text to {target_lang}. 
Only output the translation, no explanations.

{text}"""

    payload = {
        "model": MODEL,
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": 2048,
        "temperature": 0.1
    }

    try:
        response = requests.post(url, json=payload, timeout=120)
        response.raise_for_status()
        result = response.json()
        translation = result["choices"][0]["message"]["content"].strip()
        return translation
    except Exception as e:
        print(f"翻译错误: {e}")
        return f"[翻译失败: {text}]"


def translate_batch_ollama(texts, source_lang="English", target_lang="Chinese"):
    """批量翻译"""
    translations = []
    for text in tqdm(texts, desc="翻译进度"):
        trans = translate_ollama(text, source_lang, target_lang)
        translations.append(trans)
        time.sleep(0.3)
    return translations


def wrap_english(text):
    """英文按字符数换行（单词边界断行）"""
    if not text:
        return ""
    words = text.split()
    lines = []
    current_line = ""
    for word in words:
        if len(current_line) + len(word) + 1 <= EN_WRAP:
            current_line += word + " "
        else:
            if current_line:
                lines.append(current_line.rstrip())
            current_line = word + " "
    if current_line:
        lines.append(current_line.rstrip())
    return '\n'.join(lines)


def wrap_chinese(text, max_chars=40):
    """中文按字符数换行"""
    if not text:
        return ""
    lines = []
    for i in range(0, len(text), max_chars):
        lines.append(text[i:i + max_chars])
    return '\n'.join(lines)


def extract_vocabulary(text, max_words=20):
    """从文章中提取词汇"""
    import re
    from collections import Counter
    import math

    words = re.findall(r'\b[a-zA-Z]+\b', text.lower())
    
    stop_words = {
        'the', 'is', 'are', 'was', 'were', 'be', 'been', 'being',
        'have', 'has', 'had', 'do', 'does', 'did', 'will', 'would',
        'could', 'should', 'may', 'might', 'must', 'shall', 'can',
        'need', 'dare', 'ought', 'used', 'to', 'of', 'in', 'for',
        'on', 'with', 'at', 'by', 'from', 'as', 'into', 'through',
        'during', 'before', 'after', 'above', 'below', 'between',
        'and', 'but', 'or', 'nor', 'so', 'yet', 'both', 'either',
        'neither', 'not', 'only', 'own', 'same', 'than', 'too',
        'very', 'just', 'also', 'now', 'here', 'there', 'when',
        'where', 'why', 'how', 'all', 'each', 'every', 'both',
        'few', 'more', 'most', 'other', 'some', 'such', 'no',
        'any', 'this', 'that', 'these', 'those', 'it', 'its',
        'he', 'she', 'they', 'them', 'his', 'her', 'their',
        'what', 'which', 'who', 'whom', 'whose', 'if', 'then',
        'because', 'until', 'while', 'although', 'though', 'since',
        'unless', 'about', 'against', 'among', 'because', 'before',
        'behind', 'beside', 'between', 'beyond', 'by', 'concerning',
        'considering', 'despite', 'except', 'following', 'like',
        'near', 'regarding', 'since', 'throughout', 'toward',
        'under', 'underneath', 'unlike', 'until', 'upon', 'versus',
        'via', 'within', 'without'
    }
    
    filtered = [w for w in words if w not in stop_words and len(w) > 5]
    word_freq = Counter(filtered)
    
    word_scores = {}
    for word, freq in word_freq.items():
        score = freq * math.log(len(word))
        word_scores[word] = score
    
    sorted_words = sorted(word_scores.items(), key=lambda x: x[1], reverse=True)
    unique_words = []
    seen = set()
    for word, score in sorted_words:
        if word not in seen:
            unique_words.append(word)
            seen.add(word)
    
    return unique_words[:max_words]


def load_article(txt_path):
    """读取原始文章"""
    with open(txt_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    lines = content.strip().split('\n')
    title = lines[0].strip()
    
    paragraphs = []
    current_para = []
    for line in lines[1:]:
        line = line.strip()
        if line:
            current_para.append(line)
        elif current_para:
            paragraphs.append(' '.join(current_para))
            current_para = []
    if current_para:
        paragraphs.append(' '.join(current_para))
    
    return title, paragraphs


def create_trans_file(title, paragraphs, translations, vocab_list, vocab_trans, sent_list, sent_trans, output_path):
    """生成 trans 格式文件"""
    content = f"TITLE: {title}\n\n"
    
    formatted_en = []
    for para in paragraphs:
        formatted_en.append(wrap_english(para))
    
    formatted_zh = []
    for trans in translations:
        formatted_zh.append(wrap_chinese(trans))
    
    content += "ORIGINAL:\n"
    content += '\n'.join(formatted_en)
    content += '\n\n'
    content += "---\n\n"
    content += "EN-CH:\n"
    
    for i, (en_para, zh_para) in enumerate(zip(formatted_en, formatted_zh), 1):
        content += f"{en_para}\n\n{zh_para}\n\n"
    
    content += "---\n\n"
    content += "VOCABULARY:\n"
    for i in range(len(vocab_list)):
        content += f"{i+1}. {vocab_list[i]}|{vocab_trans[i]}\n"
    content += '\n'
    content += "---\n\n"
    content += "SENTENCES:\n"
    for i in range(len(sent_list)):
        content += f"{i+1}. {sent_list[i]}\n\n{sent_trans[i]}\n\n"
    
    with open(output_path, 'w', encoding='utf-8') as f:
        f.write(content)
    
    print(f"生成文件: {output_path}")


def main():
    if len(sys.argv) < 2:
        print("用法: python ollama_translate.py article.txt")
        print(f"Ollama: {OLLAMA_HOST}")
        print(f"模型: {MODEL}")
        sys.exit(1)
    
    input_file = sys.argv[1]
    input_path = Path(input_file)
    
    if not input_path.exists():
        print(f"错误: 文件不存在 {input_file}")
        sys.exit(1)
    
    print(f"读取文章: {input_path.name}")
    title, paragraphs = load_article(input_path)
    print(f"标题: {title}")
    print(f"段落数: {len(paragraphs)}")
    print(f"Ollama: {OLLAMA_HOST}")
    print(f"模型: {MODEL}")
    
    print("\n" + "=" * 50)
    print("翻译整篇文章...")
    translations = translate_batch_ollama(paragraphs)
    
    print("\n提取词汇...")
    vocab_list = extract_vocabulary(' '.join(paragraphs), 20)
    print(f"词汇数量: {len(vocab_list)}")
    
    print("翻译词汇表...")
    vocab_trans = translate_batch_ollama(vocab_list)
    
    print("提取精彩句子...")
    import re
    text_clean = ' '.join(paragraphs).replace('!', '.').replace('?', '.')
    sents = re.split(r'(?<=[.!?])\s+', text_clean)
    sent_list = []
    matched_words = set()
    for sent in sents:
        sent = sent.strip()
        if len(sent) < 80 or len(sent) > 250:
            continue
        sent_lower = sent.lower()
        for word in vocab_list:
            if word in sent_lower and word not in matched_words:
                sent_list.append(sent)
                matched_words.add(word)
                break
        if len(sent_list) >= 15:
            break
    print(f"句子数量: {len(sent_list)}")
    
    print("翻译精彩句子...")
    sent_trans = translate_batch_ollama(sent_list)
    
    print("\n" + "=" * 50)
    print("生成输出文件...")
    import os
    os.makedirs('output', exist_ok=True)
    output_file = f"output/{input_path.stem}_trans.txt"
    create_trans_file(title, paragraphs, translations, vocab_list, vocab_trans, sent_list, sent_trans, output_file)
    
    print("\n完成!")


if __name__ == "__main__":
    main()
