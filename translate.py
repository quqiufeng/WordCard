#!/usr/bin/env python3
"""
翻译英文文章为中英双语格式
生成 solar_system_trans.txt 格式的输出文件
"""

import warnings
warnings.filterwarnings('ignore')

import ctranslate2
import transformers
import re
import time
import sys
from pathlib import Path

MODEL_DIR = "E:/cuda/nllb-200-3.3B-ct2-float16"

LANG_CODE_MAP = {
    'en': 'eng_Latn',
    'english': 'eng_Latn',
    'zh': 'zho_Hans',
    'chinese': 'zho_Hans',
}

def load_translator():
    """加载 CTranslate2 翻译模型"""
    print(f"加载翻译模型: {MODEL_DIR}")
    translator = ctranslate2.Translator(MODEL_DIR, device="cuda")
    tokenizer = transformers.AutoTokenizer.from_pretrained(MODEL_DIR)
    print(f"设备: {translator.device}\n")
    return translator, tokenizer

def translate_texts(translator, tokenizer, texts, source_lang="eng_Latn", target_lang="zho_Hans", batch_size=16):
    """翻译文本列表"""
    import torch

    all_results = []

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
        print(f"  翻译进度: {progress}/{len(texts)} ({progress*100//len(texts)}%)", end='\r')

    print(f"  翻译进度: {len(texts)}/{len(texts)} (100%)")

    all_results = [r.replace("<unk>", "").strip() for r in all_results]

    return all_results

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
    for line in lines[1:]:
        line = line.strip()
        if line:
            paragraphs.append(line)

    return title, paragraphs

def extract_vocabulary_prompt(article_text):
    """使用提示词提取词汇表"""
    prompt = f"""请从以下英文文章中提取15-20个常用词汇，包括单词、词性和中文翻译。
格式要求：
- 每行一个词汇，格式：英文单词|词性|中文翻译
- 只提取常用词汇，不要生僻词
- 词性使用简写：n.名词 v.动词 adj.形容词 adv.副词 prep.介词 conj.连词

文章内容：
{article_text}

词汇表："""

    return prompt

def extract_sentences_prompt(article_text):
    """使用提示词提取精彩句子"""
    prompt = f"""请从以下英文文章中提取5-8个精彩句子，包括英文原文和中文翻译。
格式要求：
- 每行一个句子，格式：英文句子|中文翻译
- 选择最有学习价值的句子
- 中文翻译要准确流畅

文章内容：
{article_text}

精彩句子："""

    return prompt

def parse_vocabulary(response_text):
    """解析词汇表响应"""
    vocab_list = []
    for line in response_text.strip().split('\n'):
        line = line.strip()
        if '|' in line:
            parts = line.split('|', 2)
            if len(parts) >= 3:
                vocab_list.append({
                    'word': parts[0].strip(),
                    'pos': parts[1].strip(),
                    'meaning': parts[2].strip()
                })
    return vocab_list

def parse_sentences(response_text):
    """解析句子响应"""
    sent_list = []
    for line in response_text.strip().split('\n'):
        line = line.strip()
        if '|' in line:
            parts = line.split('|', 1)
            if len(parts) >= 2:
                sent_list.append({
                    'original': parts[0].strip(),
                    'translation': parts[1].strip()
                })
    return sent_list

def generate_with_prompt(translator, tokenizer, prompt):
    """使用提示词生成结构化内容"""
    results = translate_texts(
        translator, tokenizer,
        [prompt],
        source_lang="eng_Latn",
        target_lang="zho_Hans",
        batch_size=1
    )
    return results[0] if results else ""

def create_trans_file(title, original_paragraphs, translation_text, vocab_list, sent_list, output_path):
    """生成 trans 格式文件"""
    content = f"TITLE: {title}\n\n"
    content += "ORIGINAL:\n"
    content += '\n'.join(original_paragraphs)
    content += '\n\n'
    content += "TRANSLATION:\n"
    content += translation_text
    content += '\n\n'
    content += "---\n\n"
    content += "VOCABULARY:\n"
    for v in vocab_list:
        content += f"{v['word']}|{v['pos']}|{v['meaning']}\n"
    content += '\n'
    content += "---\n\n"
    content += "SENTENCES:\n"
    for s in sent_list:
        content += f"{s['original']}|{s['translation']}\n"

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

    article_text = '\n'.join(paragraphs)

    translator, tokenizer = load_translator()

    print("\n" + "=" * 50)
    print("1. 翻译整篇文章...")
    start_time = time.time()
    full_translation = translate_texts(
        translator, tokenizer,
        paragraphs,
        source_lang="eng_Latn",
        target_lang="zho_Hans",
        batch_size=8
    )
    translation_text = '\n'.join(full_translation)
    elapsed = time.time() - start_time
    print(f"翻译耗时: {elapsed:.2f}秒")

    print("\n" + "=" * 50)
    print("2. 提取词汇表...")
    vocab_prompt = extract_vocabulary_prompt(article_text)
    vocab_response = generate_with_prompt(translator, tokenizer, vocab_prompt)
    vocab_list = parse_vocabulary(vocab_response)
    print(f"提取词汇: {len(vocab_list)} 个")

    print("\n" + "=" * 50)
    print("3. 提取精彩句子...")
    sent_prompt = extract_sentences_prompt(article_text)
    sent_response = generate_with_prompt(translator, tokenizer, sent_prompt)
    sent_list = parse_sentences(sent_response)
    print(f"提取句子: {len(sent_list)} 个")

    print("\n" + "=" * 50)
    print("4. 生成输出文件...")
    output_file = input_path.stem + '_trans.txt'
    create_trans_file(title, paragraphs, translation_text, vocab_list, sent_list, output_file)

    cleanup(translator, tokenizer)
    print("\n完成!")

if __name__ == "__main__":
    main()
