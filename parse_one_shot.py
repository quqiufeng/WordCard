#!/usr/bin/env python3
"""
解析 ollama_one_shot.py 生成的输出，转换为 article_card.py 期望的格式
"""

import sys
import os
from pathlib import Path

def parse_one_shot(txt_file):
    """解析 one_shot 格式的文件"""
    with open(txt_file, 'r', encoding='utf-8') as f:
        content = f.read()

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

def format_for_article_card(sections, title="英文学习卡片"):
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
    if len(sys.argv) < 2:
        print("用法: python parse_one_shot.py input.txt [output.txt]")
        print("例如: python parse_one_shot.py output/solar_system_one_shot.txt output/solar_system_parsed.txt")
        sys.exit(1)

    input_file = sys.argv[1]
    output_file = sys.argv[2] if len(sys.argv) > 2 else None

    if not os.path.exists(input_file):
        print(f"错误: 文件不存在 {input_file}")
        sys.exit(1)

    print(f"解析: {input_file}")
    sections = parse_one_shot(input_file)

    print(f"  原文: {len(sections.get('original', ''))} 字符")
    print(f"  双语: {len(sections.get('en_ch', ''))} 字符")
    vocab = sections.get('vocabulary', [])
    if isinstance(vocab, str):
        vocab = vocab.split('\n')
    print(f"  词汇: {len([v for v in vocab if v.strip()])} 个")
    sentences = sections.get('sentences', '')
    sentence_count = len([s for s in sentences.split('\n') if s.strip()])
    print(f"  句子: {sentence_count} 个")

    formatted = format_for_article_card(sections)

    if output_file:
        with open(output_file, 'w', encoding='utf-8') as f:
            f.write(formatted)
        print(f"输出: {output_file}")
    else:
        print("\n" + "=" * 50)
        print(formatted)

if __name__ == "__main__":
    main()
