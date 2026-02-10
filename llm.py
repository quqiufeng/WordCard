#!/usr/bin/env python3
"""
调用 LM Studio 生成英文学习内容，并解析输出为 article_card.py 期望的格式
"""

import warnings
warnings.filterwarnings('ignore')

import requests
import sys
import os
from pathlib import Path

LLMS_HOST = "http://192.168.124.3:11434/v1"
MODEL = "qwen2.5-7b-instruct"

def generate_content(text):
    """调用 LM Studio 生成所有内容"""
    url = f"{LLMS_HOST}/chat/completions"

    prompt = f"""请阅读以下英文文章，按格式输出4个部分：

【英文原文】
直接输出文章原文，不需要翻译，不需要在段落前加数字序号。

【中英双语】
将文章按段落生成双语格式：每段英文+对应中文翻译。不要在段落前加数字序号。

【英文单词列表】
从文章中提取20个最有用，最值得学习的英文单词（排除常见词如 the, is, and 等）。
格式：1. 单词|中文翻译
2. 英文|中文翻译
...

【精彩句子】
使用上面的单词，生成12个有用的英文长句子，帮助记忆这些单词。
每个句子要完整、有意义、能帮助理解单词含义。
格式：1. 英文长句子
   中文翻译
2. 英文长句子
   中文翻译

要求：
- 单词要真正有用，不要太简单的词
- 句子要完整，能帮助理解单词含义
- 双语翻译要通顺自然

以下是文章：
{text}
"""

    payload = {
        "model": MODEL,
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": 4096,
        "temperature": 0.3
    }

    try:
        response = requests.post(url, json=payload, timeout=300)
        response.raise_for_status()
        result = response.json()
        content = result["choices"][0]["message"]["content"].strip()
        return content
    except Exception as e:
        print(f"错误: {e}")
        return None

def parse_content(content):
    """解析 one_shot 格式的内容"""
    sections = {
        'title': '',
        'original': '',
        'en_ch': '',
        'vocabulary': [],
        'sentences': ''
    }

    current_section = None
    current_content = []

    section_markers = {
        '【英文原文】': 'original',
        '【中英双语】': 'en_ch',
        '【英文单词列表】': 'vocabulary',
        '【精彩句子】': 'sentences'
    }

    for line in content.split('\n'):
        stripped = line.strip()

        if stripped in section_markers:
            if current_section:
                sections[current_section] = '\n'.join(current_content).strip()
            current_section = section_markers[stripped]
            current_content = []
        elif current_section:
            current_content.append(line)

    if current_section:
        sections[current_section] = '\n'.join(current_content).strip()

    return sections

def format_for_article_card(sections, title):
    """转换为 article_card.py 期望的格式"""
    lines = []
    lines.append(f"TITLE: {title}")
    lines.append("---")
    lines.append("ORIGINAL:")
    lines.append(sections.get('original', ''))
    lines.append("---")
    lines.append("EN-CH:")
    lines.append(sections.get('en_ch', ''))
    lines.append("---")
    lines.append("VOCABULARY:")
    vocab = sections.get('vocabulary', [])
    if isinstance(vocab, str):
        vocab = vocab.split('\n')
    for v in vocab:
        v = v.strip()
        if v:
            lines.append(v)
    lines.append("---")
    lines.append("SENTENCES:")
    lines.append(sections.get('sentences', ''))
    return '\n'.join(lines)

def main():
    txt_files = []

    if len(sys.argv) < 1:
        print("用法: python llm.py article.txt [标题]")
        print(f"LM Studio: {LLMS_HOST}")
        print(f"模型: {MODEL}")
        sys.exit(1)

    if len(sys.argv) == 1:
        # 不传参数，扫描 res 目录下所有 txt 文件
        if os.path.exists('res'):
            for f in os.listdir('res'):
                if f.endswith('.txt'):
                    txt_files.append(f"res/{f}")
        if not txt_files:
            print("错误: res 目录下没有 txt 文件")
            sys.exit(1)
        print(f"扫描到 {len(txt_files)} 个文件，将全部处理")
    else:
        # 处理指定的文件
        for arg in sys.argv[1:]:
            if arg.startswith('res/'):
                txt_files.append(arg)
            else:
                txt_files.append(f"res/{arg}")

    os.makedirs('output', exist_ok=True)

    for input_file in txt_files:
        if not os.path.exists(input_file):
            print(f"跳过: 文件不存在 {input_file}")
            continue

        input_path = Path(input_file)
        title = input_path.stem.replace('_', ' ').title()

        print(f"\n读取文章: {input_path.name}")
        with open(input_path, 'r', encoding='utf-8') as f:
            text = f.read()

        print(f"发送提示词到 LM Studio...")
        print(f"模型: {MODEL}")
        print("=" * 50)

        content = generate_content(text)

        if not content:
            print(f"生成失败: {input_path.name}")
            continue

        print("生成完成！")
        print("=" * 50)

        base_name = input_path.stem

        sections = parse_content(content)
        trans_file = f"output/{base_name}_trans.txt"
        formatted = format_for_article_card(sections, title)
        with open(trans_file, 'w', encoding='utf-8') as f:
            f.write(formatted)

        print(f"\n内容统计:")
        print(f"  原文: {len(sections.get('original', ''))} 字符")
        print(f"  双语: {len(sections.get('en_ch', ''))} 字符")
        vocab = sections.get('vocabulary', [])
        if isinstance(vocab, str):
            vocab = vocab.split('\n')
        print(f"  词汇: {len([v for v in vocab if v.strip()])} 个")
        sentences = sections.get('sentences', '')
        sentence_count = len([s for s in sentences.split('\n') if s.strip()])
        print(f"  句子: {sentence_count} 个")

        print(f"\n输出: {trans_file}")

    print(f"\n完成！处理了 {len(txt_files)} 个文件")

if __name__ == "__main__":
    main()
