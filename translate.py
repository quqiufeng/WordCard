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

MODEL_DIR = "E:/cuda/nllb-200-3.3B-ct2-float16"

EN_WRAP_WORDS = 15
ZH_WRAP_CHARS = 40

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

    print(f"[调试] 原始内容行数: {len(content.split(chr(10)))}")

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
                para_text = ' '.join(current_para)
                word_count = len(para_text.split())
                print(f"[调试] 段落单词数: {word_count}")
                paragraphs.append(para_text)
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

    total = len(texts)
    for i, text in enumerate(texts):
        try:
            result = translate_text(translator, tokenizer, text, source_lang, target_lang)
            all_results.append(result)
        except Exception as e:
            print(f"  翻译错误: {e}")
            all_results.append(text)

        print(f"  翻译进度: {i+1}/{total}", end='\r')

    print(f"  翻译进度: {total}/{total} (100%)")

    return all_results

EN_WRAP = EN_WRAP_WORDS
ZH_WRAP = ZH_WRAP_CHARS

def wrap_english(text, max_words=15):
    """英文按单词数换行"""
    if not text:
        return ""
    words = text.split()
    lines = []
    for i in range(0, len(words), max_words):
        lines.append(' '.join(words[i:i+max_words]))
    return '\n'.join(lines)

def wrap_chinese(text, max_chars=40):
    """中文按汉字数换行"""
    if not text:
        return ""
    lines = []
    for i in range(0, len(text), max_chars):
        lines.append(text[i:i+max_chars])
    return '\n'.join(lines)

def format_translation(original_texts, translation_texts):
    """格式化译文，英文按单词，中文按汉字"""
    formatted_en = []
    for para in original_texts:
        formatted_en.append(wrap_english(para, EN_WRAP))

    formatted_zh = []
    for trans in translation_texts:
        formatted_zh.append(wrap_chinese(trans, ZH_WRAP))

    return '\n'.join(formatted_en), '\n'.join(formatted_zh)

VOCABULARY_MAP = {
    'solar system': '太阳系',
    'planet': '行星',
    'moon': '卫星',
    'asteroid': '小行星',
    'comet': '彗星',
    'gravity': '引力',
    'orbit': '轨道',
    'atmosphere': '大气层',
    'temperature': '温度',
    'surface': '表面',
    'galaxy': '星系',
    'universe': '宇宙',
    'Mercury': '水星',
    'Venus': '金星',
    'Earth': '地球',
    'Mars': '火星',
    'Jupiter': '木星',
    'Saturn': '土星',
    'Uranus': '天王星',
    'Neptune': '海王星',
    'Pluto': '冥王星',
    'terrestrial': '类地行星的',
    'gas giant': '气态巨行星',
    'ice giant': '冰巨行星',
    'dwarf planet': '矮行星',
    'rotation': '自转',
    'fusion': '聚变',
    'elliptical': '椭圆的',
    'asteroid belt': '小行星带',
    'Kuiper Belt': '柯伊伯带',
    'spacecraft': '宇宙飞船',
    'telescope': '望远镜',
    'formation': '形成',
    'collapse': '坍缩',
    'nebula': '星云',
    'protoplanetary': '原行星的',
    'million': '百万',
    'billion': '十亿',
    'century': '世纪',
    'boundary': '边界',
    'classify': '分类',
    'discover': '发现',
    'explore': '探索',
    'fascinating': '迷人的',
    'remarkable': '非凡的',
    'fragility': '脆弱性',
    'resilience': '韧性',
}

def extract_vocabulary(text, max_words=25):
    """从文章中提取词汇"""
    words = text.split()
    found = set()
    result = []
    
    for word in VOCABULARY_MAP.keys():
        word_lower = word.lower()
        for w in words:
            w_clean = w.lower().strip('.,;:!?()[]{}""\'')
            if w_clean == word_lower:
                found.add(word_lower)
                break
    
    for word in found:
        if word in VOCABULARY_MAP:
            result.append((word, VOCABULARY_MAP[word]))
    
    additional = []
    for w in words:
        w_clean = w.lower().strip('.,;:!?()[]{}""\'')
        if len(w_clean) > 5 and w_clean not in found and w_clean not in additional:
            if any(c.isalpha() for c in w_clean):
                additional.append(w_clean)
        if len(additional) >= 5:
            break
    
    for word in additional:
        if word in VOCABULARY_MAP:
            result.append((word, VOCABULARY_MAP[word]))
    
    return result[:max_words]

def extract_sentences(text, max_sents=10):
    """从文章中提取精彩句子"""
    import re
    sentences = []
    
    text_clean = text.replace('!', '.').replace('?', '.')
    
    sents = re.split(r'(?<=[.!?])\s+', text_clean)
    
    keywords = ['solar', 'planet', 'sun', 'Mercury', 'Venus', 'Earth', 'Mars',
                'Jupiter', 'Saturn', 'Uranus', 'Neptune', 'gravity', 'orbit',
                'million', 'billion', 'year', 'formed', 'discovered']
    
    for sent in sents:
        sent = sent.strip()
        if len(sent) > 50 and len(sent) < 200:
            sent_lower = sent.lower()
            if any(kw in sent_lower for kw in keywords):
                if sent not in sentences:
                    sentences.append(sent)
    
    return sentences[:max_sents]

def create_trans_file(title, formatted_en, formatted_zh, original_texts, translation_texts, output_path):
    """生成 trans 格式文件"""
    full_text = ' '.join(original_texts)
    full_trans = ' '.join(translation_texts)
    
    vocab_list = extract_vocabulary(full_text, 25)
    sent_list = extract_sentences(full_text, 10)
    
    content = f"TITLE: {title}\n\n"
    content += "ORIGINAL:\n"
    content += formatted_en
    content += '\n\n'
    content += "TRANSLATION:\n"
    content += formatted_zh
    content += '\n\n'
    content += "---\n\n"
    content += "VOCABULARY:\n"
    for word, meaning in vocab_list:
        content += f"{word}|n.|{meaning}\n"
    content += '\n'
    content += "---\n\n"
    content += "SENTENCES:\n"
    for sent in sent_list:
        content += f"{sent}|翻译\n"

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
    print("生成输出文件...")
    output_file = input_path.stem + '_trans.txt'
    formatted_en, formatted_zh = format_translation(paragraphs, full_translation)
    create_trans_file(title, formatted_en, formatted_zh, paragraphs, full_translation, output_file)

    cleanup(translator, tokenizer)
    print("\n完成!")

if __name__ == "__main__":
    main()
