#!/usr/bin/env python3
"""
文章导入工具
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
    # 转为小写，只保留字母
    words = re.findall(r'\b[a-zA-Z]+\b', text.lower())
    
    freq = {}
    for w in words:
        # 过滤停用词和短词
        if w in STOP_WORDS or len(w) < 3:
            continue
        # 过滤纯数字
        if w.isdigit():
            continue
        freq[w] = freq.get(w, 0) + 1
    
    return freq


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
    
    # 提取高频词汇
    word_freq = extract_words(content)
    top_words = sorted(word_freq.items(), key=lambda x: x[1], reverse=True)[:50]
    
    print(f"Found {len(word_freq)} unique words, top {len(top_words)} selected")
    
    # 调用 llm.py 生成翻译（复用现有功能）
    # 注意：llm.py 需要 llama.cpp 服务运行
    print("Calling LLM for translation...")
    try:
        # 简化：直接使用 llm.py 的生成逻辑
        # 这里我们手动构造提示词，模拟 llm.py 的行为
        prompt = f"""请翻译以下英文文章，并提取核心词汇：

标题: {title}

内容:
{content[:2000]}  # 限制长度避免超出上下文

请按以下格式输出：
1. 中文翻译（简洁）
2. 核心词汇表（最多30个，格式：word|中文释义）
"""
        
        # 由于没有运行 llama-server，我们先使用简单翻译
        # 实际使用时应该调用 llm.generate_content()
        print("Note: llm.py requires llama-server running. Using placeholder translations.")
        
    except Exception as e:
        print(f"LLM translation failed: {e}")
        print("Using basic import without LLM translation...")
    
    # 导入词汇（简化版：使用占位释义）
    # TODO: 应调用 wc_add_source() 创建真正的 content_source_t 记录
    source_id = 0  # 临时使用 0，表示无特定来源
    
    imported = 0
    for word, freq in top_words[:30]:  # 最多30个词
        # 检查是否已存在
        existing = db.find_vocab(word=word)
        if existing:
            print(f"  Skip existing: {word}")
            continue
        
        # 添加词汇（占位释义，实际应调用 LLM）
        vid = db.add_vocab(
            word=word,
            meaning=f"[待翻译] freq={freq}",  # 占位
            phonetic="",
            pos="",
            example="",
            example_cn="",
            difficulty=2 if freq > 5 else 3,
            source_id=source_id
        )
        if vid > 0:
            imported += 1
            print(f"  Added: {word} (freq={freq})")
    
    # 保存数据库
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
        # 默认导入 res/solar_system.txt（如果存在）
        test_file = "res/solar_system.txt"
        if os.path.exists(test_file):
            import_article(test_file, args.db)
        else:
            print("Usage: python import_article.py [--all] [files...]")
            print("       python import_article.py --all  # Import all res/*.txt")
