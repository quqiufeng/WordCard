#!/usr/bin/env python3
"""
GRE 核心词汇考法精析 - 文本抽取处理器
从 AZW3 解析结果中提取结构化单词卡片
"""
import re
import json
from dataclasses import dataclass, asdict
from typing import List, Optional


@dataclass
class WordEntry:
    word: str
    phonetic: str
    definitions: List[dict]  # [{"pos": "v.", "meaning": "...", "example": "...", "synonyms": "...", "antonyms": "..."}]


def parse_gre_vocab(text: str) -> List[WordEntry]:
    """
    从原始文本解析 GRE 单词条目
    
    格式：
      word［phonetic］
      【考法N】pos. meaning: explanation
      例 example sentence
      近 synonyms
      反 antonyms
    """
    entries = []
    
    # 清理换行符
    text = text.replace('\r', '\n')
    
    # 匹配单词条目：单词 + 全角方括号音标
    # 例：abate［ə'beɪt］
    word_pattern = re.compile(
        r'^\s*([a-zA-Z\-]+)\s*［([^］]+)］\s*$',
        re.MULTILINE
    )
    
    # 找到所有单词位置
    matches = list(word_pattern.finditer(text))
    
    for i, match in enumerate(matches):
        word = match.group(1).strip()
        phonetic = match.group(2).strip()
        
        # 截取当前单词到下一个单词之间的文本
        start = match.end()
        end = matches[i + 1].start() if i + 1 < len(matches) else len(text)
        section = text[start:end]
        
        definitions = []
        
        # 解析考法
        # 【考法1】v. 减轻（程度或者强度）：to reduce in degree or intensity
        kaofa_pattern = re.compile(
            r'【考法\d+】\s*([a-zA-Z]+\.?)\s*(.+?)(?=\n\s*例|$)',
            re.DOTALL
        )
        
        # 更精确的逐行解析
        lines = section.strip().split('\n')
        current_def = None
        
        for line in lines:
            line = line.strip()
            if not line:
                continue
                
            # 考法行
            kaofa_match = re.match(r'【考法\d+】\s*(.+)', line)
            if kaofa_match:
                if current_def:
                    definitions.append(current_def)
                current_def = {
                    "pos": "",
                    "meaning": kaofa_match.group(1).strip(),
                    "example": "",
                    "synonyms": "",
                    "antonyms": ""
                }
                continue
            
            # 例句行
            if line.startswith('例') or line.startswith('例\u3000'):
                if current_def:
                    current_def["example"] = line.lstrip('例').lstrip('\u3000').strip()
                continue
            
            # 近义词
            if line.startswith('近') or line.startswith('近\u3000'):
                if current_def:
                    current_def["synonyms"] = line.lstrip('近').lstrip('\u3000').strip()
                continue
            
            # 反义词
            if line.startswith('反') or line.startswith('反\u3000'):
                if current_def:
                    current_def["antonyms"] = line.lstrip('反').lstrip('\u3000').strip()
                continue
        
        if current_def:
            definitions.append(current_def)
        
        entries.append(WordEntry(
            word=word,
            phonetic=phonetic,
            definitions=definitions
        ))
    
    return entries


def export_plaintext(entries: List[WordEntry], output_path: str):
    """导出为易读纯文本"""
    with open(output_path, 'w', encoding='utf-8') as f:
        f.write("=" * 60 + "\n")
        f.write("GRE 核心词汇考法精析 - 纯文本版\n")
        f.write("=" * 60 + "\n\n")
        
        for entry in entries:
            f.write(f"\n{'─' * 50}\n")
            f.write(f"【{entry.word}】 {entry.phonetic}\n")
            f.write(f"{'─' * 50}\n")
            
            for i, d in enumerate(entry.definitions, 1):
                f.write(f"\n  考法{i}: {d['meaning']}\n")
                if d['example']:
                    f.write(f"  例: {d['example']}\n")
                if d['synonyms']:
                    f.write(f"  近: {d['synonyms']}\n")
                if d['antonyms']:
                    f.write(f"  反: {d['antonyms']}\n")
            
            f.write("\n")
    
    print(f"纯文本已导出: {output_path}")


def export_json(entries: List[WordEntry], output_path: str):
    """导出为 JSON"""
    data = [asdict(e) for e in entries]
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print(f"JSON 已导出: {output_path}")


def export_anki(entries: List[WordEntry], output_path: str):
    """导出为 Anki 制表符分隔格式（正面 | 背面）"""
    with open(output_path, 'w', encoding='utf-8') as f:
        for entry in entries:
            front = f"{entry.word}\n{entry.phonetic}"
            back_parts = []
            for d in entry.definitions:
                back_parts.append(d['meaning'])
                if d['example']:
                    back_parts.append(f"例: {d['example']}")
                if d['synonyms']:
                    back_parts.append(f"近: {d['synonyms']}")
                if d['antonyms']:
                    back_parts.append(f"反: {d['antonyms']}")
            back = "<br><br>".join(back_parts)
            f.write(f"{front}\t{back}\n")
    
    print(f"Anki 格式已导出: {output_path}")


def main():
    from importer import parse_mobi
    import os
    
    book_path = '/root/A00962. GRE核心词汇考法精析 (新东方大愚英语学习丛书).B00GWD2L4W.azw3'
    output_dir = '/opt/WordCard/output'
    os.makedirs(output_dir, exist_ok=True)
    
    print(f"1. 读取: {book_path}")
    result = parse_mobi(book_path)
    text = result['text']
    print(f"   原始文本: {len(text):,} 字符")
    
    print(f"\n2. 解析单词条目...")
    entries = parse_gre_vocab(text)
    print(f"   解析到 {len(entries)} 个单词")
    
    # 显示前 3 个样本
    print(f"\n3. 样本预览:")
    for e in entries[:3]:
        print(f"   {e.word} [{e.phonetic}]")
        for d in e.definitions[:1]:
            print(f"     -> {d['meaning'][:60]}...")
    
    print(f"\n4. 导出...")
    export_plaintext(entries, f"{output_dir}/gre_vocab.txt")
    export_json(entries, f"{output_dir}/gre_vocab.json")
    export_anki(entries, f"{output_dir}/gre_vocab_anki.txt")
    
    print(f"\n完成！输出目录: {output_dir}")


if __name__ == "__main__":
    main()
