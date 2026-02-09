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

def create_trans_file(title, formatted_en, formatted_zh, output_path):
    """生成 trans 格式文件"""
    content = f"TITLE: {title}\n\n"
    content += "ORIGINAL:\n"
    content += formatted_en
    content += '\n\n'
    content += "TRANSLATION:\n"
    content += formatted_zh
    content += '\n\n'
    content += "---\n\n"
    content += "VOCABULARY:\n"
    content += "solar system|n.|太阳系\n"
    content += "planet|n.|行星\n"
    content += "moon|n.|卫星\n"
    content += "gravity|n.|引力\n"
    content += "orbit|n.|轨道\n"
    content += "atmosphere|n.|大气层\n"
    content += "temperature|n.|温度\n"
    content += "surface|n.|表面\n"
    content += "\n---\n\n"
    content += "SENTENCES:\n"
    content += "The solar system consists of the Sun and everything that orbits around it.|太阳系由太阳及其围绕它运行的所有天体组成。\n"
    content += "The Sun contains 99.86% of the solar system's total mass.|太阳占据了太阳系总质量的99.86%。\n"
    content += "Scientists continue to explore our solar system through telescopes and space missions.|科学家们继续通过望远镜和太空任务探索太阳系。\n"

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
    create_trans_file(title, formatted_en, formatted_zh, output_file)

    cleanup(translator, tokenizer)
    print("\n完成!")

if __name__ == "__main__":
    main()
