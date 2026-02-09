#!/usr/bin/env python3
"""
翻译英文文章为中英双语格式
生成 solar_system_trans.txt 格式的输出文件
"""

import warnings
warnings.filterwarnings('ignore')

import ctranslate2
import transformers
import time
import sys
from pathlib import Path
from tqdm import tqdm

MODEL_DIR = "E:/cuda/nllb-200-3.3B-ct2-float16"

EN_WRAP = 65  # 英文每行字符数（与中文40字符宽度对齐）
ZH_WRAP = 40  # 中文每行字符数

LANG_CODE_MAP = {
    'en': 'eng_Latn',
    'zh': 'zho_Hans',
}

def load_translator():
    """加载 CTranslate2 翻译模型"""
    print(f"加载翻译模型: {MODEL_DIR}")
    translator = ctranslate2.Translator(MODEL_DIR, device="cuda")
    tokenizer = transformers.AutoTokenizer.from_pretrained(MODEL_DIR)
    print(f"设备: {translator.device}\n")
    return translator, tokenizer

def cleanup(translator, tokenizer):
    """释放 GPU 内存"""
    import torch
    del translator
    del tokenizer
    torch.cuda.empty_cache()

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
        else:
            if current_para:
                paragraphs.append(' '.join(current_para))
                current_para = []
    
    if current_para:
        paragraphs.append(' '.join(current_para))

    return title, paragraphs

def translate_text(translator, tokenizer, text, source_lang="eng_Latn", target_lang="zho_Hans"):
    """翻译单个文本"""
    import torch

    encoded = tokenizer.encode(text)
    tokens = tokenizer.convert_ids_to_tokens(encoded)

    results = translator.translate_batch([tokens], target_prefix=[[target_lang]])

    result_tokens = results[0].hypotheses[0]
    if result_tokens and result_tokens[0] == target_lang:
        result_tokens = result_tokens[1:]

    result = tokenizer.convert_tokens_to_string(result_tokens).strip()
    result = result.replace("<unk>", "").strip()

    del encoded
    torch.cuda.empty_cache()

    return result

def translate_batch(translator, tokenizer, texts, source_lang="eng_Latn", target_lang="zho_Hans"):
    """翻译文本列表（逐个翻译，确保质量）"""
    all_results = []

    for text in tqdm(texts, desc="翻译进度"):
        try:
            result = translate_text(translator, tokenizer, text, source_lang, target_lang)
            all_results.append(result)
        except Exception as e:
            print(f"\n  翻译错误: {e}")
            all_results.append(text)

    return all_results

def wrap_english(text):
    """英文按字符数换行，在单词边界处断行"""
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
    """中文按汉字数换行"""
    if not text:
        return ""
    lines = []
    for i in range(0, len(text), max_chars):
        lines.append(text[i:i+max_chars])
    return '\n'.join(lines)

def extract_vocabulary(text, max_words=20):
    """从文章中提取词汇，按重要性加权排序"""
    import re
    import math
    from collections import Counter

    words = re.findall(r'\b[a-zA-Z]+\b', text.lower())

    stop_words = {
        # 冠词
        'a', 'an', 'the',
        # 介词
        'in', 'on', 'at', 'to', 'for', 'of', 'with', 'by', 'from', 'up', 'out', 'as',
        'into', 'like', 'through', 'after', 'over', 'between', 'under', 'above',
        # 代词
        'i', 'me', 'my', 'we', 'us', 'our', 'you', 'your', 'he', 'him', 'his', 'she',
        'her', 'it', 'its', 'they', 'them', 'their', 'what', 'who', 'which', 'whom',
        # 连词
        'and', 'but', 'or', 'nor', 'so', 'yet', 'if', 'then',
        # 动词
        'is', 'am', 'are', 'was', 'were', 'be', 'been', 'being', 'have', 'has', 'had',
        'do', 'does', 'did', 'will', 'would', 'shall', 'should', 'can', 'could', 'may',
        'might', 'must', 'get', 'got', 'go', 'goes', 'went', 'come', 'came', 'see', 'saw',
        'know', 'knew', 'think', 'thought', 'say', 'said', 'tell', 'told', 'ask', 'asked',
        'work', 'works', 'make', 'made', 'take', 'took', 'give', 'gave', 'find', 'found',
        # 副词
        'not', 'no', 'yes', 'very', 'just', 'only', 'also', 'too', 'now', 'here', 'there',
        'when', 'where', 'why', 'how', 'all', 'each', 'both', 'few', 'more', 'most', 'other',
        'some', 'such', 'ever', 'never', 'always', 'often', 'still', 'even', 'back',
        # 形容词
        'new', 'old', 'good', 'bad', 'great', 'high', 'small', 'large', 'long', 'short',
        'young', 'big', 'red', 'black', 'white', 'same', 'different', 'able', 'sure',
        # 特殊
        'about', 'into', 'out', 'off', 'down', 'up', 'one', 'two', 'first', 'last',
    }

    # 过滤停用词和短单词（<=5字符太简单）
    filtered = [w for w in words if w not in stop_words and len(w) > 5]

    # 计算词频
    word_freq = Counter(filtered)

    # 简单加权：词频 × log(长度)
    # 高频且长的词更重要
    word_scores = {}
    for word, freq in word_freq.items():
        score = freq * math.log(len(word))
        word_scores[word] = score

    # 按分数降序排序
    sorted_words = sorted(word_scores.items(), key=lambda x: x[1], reverse=True)

    # 去重取前N个
    unique_words = []
    for word, score in sorted_words:
        if word not in unique_words:
            unique_words.append(word)
        if len(unique_words) >= max_words:
            break

    return unique_words[:max_words]

def extract_sentences(text, vocab_list, max_sents=20):
    """从文章中提取包含词汇表中词汇的句子"""
    import re

    text_clean = text.replace('!', '.').replace('?', '.')
    sents = re.split(r'(?<=[.!?])\s+', text_clean)

    good_sents = []
    matched_words = set()

    for sent in sents:
        sent = sent.strip()
        if len(sent) < 80 or len(sent) > 250:
            continue

        sent_lower = sent.lower()

        for word in vocab_list:
            if word in sent_lower and word not in matched_words:
                good_sents.append(sent)
                matched_words.add(word)
                break

        if len(good_sents) >= max_sents:
            break

    return good_sents

def highlight_vocab_in_text(text, vocab_list):
    """将原文中的词汇表单词替换为 [单词] 格式"""
    import re
    result = text
    for word in vocab_list:
        pattern = r'\b' + re.escape(word) + r'\b'
        replacement = f'[{word}]'
        result = re.sub(pattern, replacement, result, flags=re.IGNORECASE)
    return result

def create_trans_file(title, paragraphs, translations, vocab_list, vocab_trans, sent_list, sent_trans, output_path):
    """生成 trans 格式文件"""
    content = f"TITLE: {title}\n\n"
    
    # 处理原文，标记词汇表单词
    formatted_en = []
    for para in paragraphs:
        highlighted = highlight_vocab_in_text(para, vocab_list)
        formatted_en.append(wrap_english(highlighted))
    
    formatted_zh = []
    for trans in translations:
        formatted_zh.append(wrap_chinese(trans))
    
    content += "ORIGINAL:\n"
    content += '\n'.join(formatted_en)
    content += '\n\n'
    content += "---\n\n"
    content += "EN-CH:\n"
    content += "中英双语：\n\n"
    
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
        content += f"{i+1}. {wrap_english(sent_list[i])}\n\n{wrap_chinese(sent_trans[i])}\n\n"

    with open(output_path, 'w', encoding='utf-8') as f:
        f.write(content)

    print(f"生成文件: {output_path}")

def main():
    if len(sys.argv) < 2:
        print("用法: python translate.py article.txt")
        print("例如: python translate.py solar_system.txt")
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

    translator, tokenizer = load_translator()

    print("\n" + "=" * 50)
    print("翻译整篇文章...")
    start_time = time.time()
    full_translation = translate_batch(translator, tokenizer, paragraphs)
    elapsed = time.time() - start_time
    print(f"翻译耗时: {elapsed:.2f}秒")

    print("\n" + "=" * 50)
    print("提取词汇表...")
    vocab_list = extract_vocabulary(' '.join(paragraphs), 20)
    print(f"词汇数量: {len(vocab_list)}")

    print("翻译词汇表...")
    vocab_trans = []
    for word in tqdm(vocab_list, desc="词汇翻译"):
        trans = translate_text(translator, tokenizer, word)
        vocab_trans.append(trans)

    print("提取精彩句子...")
    sent_list = extract_sentences(' '.join(paragraphs), vocab_list, 15)
    print(f"句子数量: {len(sent_list)}")

    print("翻译精彩句子...")
    sent_trans = []
    for sent in tqdm(sent_list, desc="句子翻译"):
        trans = translate_text(translator, tokenizer, sent)
        sent_trans.append(trans)

    print("\n" + "=" * 50)
    print("生成输出文件...")
    import os
    os.makedirs('output', exist_ok=True)
    output_file = f"output/{input_path.stem}_trans.txt"
    create_trans_file(title, paragraphs, full_translation, vocab_list, vocab_trans, sent_list, sent_trans, output_file)

    cleanup(translator, tokenizer)
    print("\n完成!")

if __name__ == "__main__":
    main()
