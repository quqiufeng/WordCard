#!/usr/bin/env python3
"""
文章导入工具 v2
读取 res/*.txt → 调用 llm.py 生成翻译和词汇表 → 写入 C 数据库
"""
import os
import sys
import re
import argparse
from pathlib import Path

# 添加项目根目录到路径
sys.path.insert(0, str(Path(__file__).parent))

from api import get_db
import llm  # 复用现有的 llm.py

# 停用词表（简化版）
STOP_WORDS = {
    'the', 'a', 'an', 'is', 'are', 'was', 'were', 'be', 'been', 'being',
    'have', 'has', 'had', 'do', 'does', 'did', 'will', 'would', 'could',
    'should', 'may', 'might', 'must', 'shall', 'can', 'need', 'dare',
    'ought', 'used', 'to', 'of', 'in', 'for', 'on', 'with', 'at', 'by',
    'from', 'as', 'into', 'through', 'during', 'before', 'after', 'above',
    'below', 'between', 'under', 'and', 'but', 'or', 'yet', 'so', 'if',
    'because', 'although', 'though', 'while', 'where', 'when', 'that',
    'which', 'who', 'whom', 'whose', 'what', 'this', 'these', 'those',
    'i', 'you', 'he', 'she', 'it', 'we', 'they', 'me', 'him', 'her',
    'us', 'them', 'my', 'your', 'his', 'its', 'our', 'their', 'mine',
    'yours', 'hers', 'ours', 'theirs', 'myself', 'yourself', 'himself',
    'herself', 'itself', 'ourselves', 'yourselves', 'themselves',
    'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight',
    'nine', 'ten', 'first', 'second', 'third', 'last', 'next', 'many',
    'much', 'some', 'any', 'all', 'each', 'every', 'both', 'few',
    'more', 'most', 'other', 'such', 'no', 'not', 'only', 'own', 'same',
    'so', 'than', 'too', 'very', 'just', 'now', 'then', 'here', 'there',
    'up', 'out', 'off', 'over', 'again', 'further', 'once', 'down',
}


def extract_words(text: str) -> dict:
    """从文本中提取单词和频率"""
    words = re.findall(r'\b[a-zA-Z]+\b', text.lower())
    
    freq = {}
    for w in words:
        if w in STOP_WORDS or len(w) < 3:
            continue
        if w.isdigit():
            continue
        freq[w] = freq.get(w, 0) + 1
    
    return freq


def parse_llm_vocab(vocab_text: str) -> list:
    """解析 LLM 输出的词汇表
    格式：1. word|中文释义
    """
    vocab = []
    for line in vocab_text.strip().split('\n'):
        line = line.strip()
        if not line:
            continue
        # 移除数字前缀如 "1."
        line = re.sub(r'^\d+\.\s*', '', line)
        if '|' in line:
            parts = line.split('|', 1)
            word = parts[0].strip()
            meaning = parts[1].strip()
            if word and meaning:
                vocab.append((word, meaning))
    return vocab


def import_article(file_path: str, db_path: str = "data/wordcard.db"):
    """导入单篇文章"""
    db = get_db(db_path)
    
    # 读取文章
    with open(file_path, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    
    title = lines[0].strip() if lines else "Untitled"
    content = ''.join(lines[1:]) if len(lines) > 1 else ''.join(lines)
    
    print(f"Importing: {title}")
    print(f"Content length: {len(content)} chars")
    
    # 先创建 content_source_t 记录
    from api import ContentSource, ctypes
    source = ContentSource()
    source.type = 3  # SOURCE_ARTICLE
    source.name = title.encode('utf-8')[:127]
    source.file_path = file_path.encode('utf-8')[:255]
    source.created_at = int(os.path.getmtime(file_path)) if os.path.exists(file_path) else 0
    
    source_id = db._db and ctypes.CDLL(str(Path(__file__).parent / "src" / "libwordcard.so")).wc_add_source(db._db, ctypes.byref(source))
    if not source_id:
        # 如果创建失败（比如 lib 还没加载），尝试用 api.py 的 add_vocab 的 source_id 参数
        source_id = 0
    
    # 调用 LLM 生成翻译和词汇
    llm_vocab = []
    try:
        print("Calling LLM for translation...")
        raw = llm.generate_content(content)
        if raw:
            sections = llm.parse_content(raw)
            vocab_text = sections.get('vocabulary', '')
            if isinstance(vocab_text, list):
                vocab_text = '\n'.join(vocab_text)
            llm_vocab = parse_llm_vocab(vocab_text)
            print(f"  LLM returned {len(llm_vocab)} vocabulary items")
        else:
            print("  LLM returned empty result, falling back to frequency extraction")
    except Exception as e:
        print(f"  LLM call failed: {e}")
        print("  Falling back to frequency extraction...")
    
    # 如果没有 LLM 结果，回退到频率提取
    if not llm_vocab:
        word_freq = extract_words(content)
        top_words = sorted(word_freq.items(), key=lambda x: x[1], reverse=True)[:30]
        llm_vocab = [(w, f"[auto] freq={f}") for w, f in top_words]
    
    imported = 0
    for word, meaning in llm_vocab[:30]:  # 最多30个词
        # 检查是否已存在
        existing = db.find_vocab(word=word)
        if existing:
            print(f"  Skip existing: {word}")
            continue
        
        vid = db.add_vocab(
            word=word,
            meaning=meaning,
            phonetic="",
            pos="",
            example="",
            example_cn="",
            difficulty=2,
            source_id=source_id
        )
        if vid > 0:
            imported += 1
            print(f"  Added: {word} -> {meaning[:40]}")
    
    db.save()
    print(f"\nImport complete: {imported} words added")
    print(f"Database saved to: {db_path}")
    
    return imported


def import_all_articles(res_dir: str = "res", db_path: str = "data/wordcard.db"):
    """导入目录下所有文章"""
    res_path = Path(res_dir)
    if not res_path.exists():
        print(f"Directory not found: {res_dir}")
        return 0
    
    total = 0
    for txt_file in sorted(res_path.glob("*.txt")):
        print(f"\n{'='*50}")
        count = import_article(str(txt_file), db_path)
        total += count
    
    print(f"\n{'='*50}")
    print(f"Total imported: {total} words from all articles")
    return total


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Import articles into WordCard DB")
    parser.add_argument("files", nargs="*", help="Article files to import")
    parser.add_argument("--all", action="store_true", help="Import all .txt files in res/")
    parser.add_argument("--db", default="data/wordcard.db", help="Database path")
    args = parser.parse_args()
    
    if args.all:
        import_all_articles(db_path=args.db)
    elif args.files:
        for f in args.files:
            import_article(f, args.db)
    else:
        test_file = "res/solar_system.txt"
        if os.path.exists(test_file):
            import_article(test_file, args.db)
        else:
            print("Usage: python import_article.py [--all] [files...]")
            print("       python import_article.py --all  # Import all res/*.txt")
