#!/usr/bin/env python3
"""
GRE 核心词汇考法精析 → WordCard 数据库导入器
"""
import sys
import re
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from api import WordCardDB
from importer import parse_mobi


def parse_gre_vocab(text: str) -> list:
    text = text.replace('\r', '\n')
    entries = []
    word_pattern = re.compile(r'^\s*([a-zA-Z\-]+)\s*［([^］]+)］\s*$', re.MULTILINE)
    matches = list(word_pattern.finditer(text))
    
    for i, match in enumerate(matches):
        word = match.group(1).strip()
        phonetic = match.group(2).strip()
        start = match.end()
        end = matches[i + 1].start() if i + 1 < len(matches) else len(text)
        section = text[start:end]
        
        definitions = []
        lines = section.strip().split('\n')
        current_def = None
        
        for line in lines:
            line = line.strip()
            if not line:
                continue
            kaofa_match = re.match(r'【考法\d+】\s*(.+)', line)
            if kaofa_match:
                if current_def:
                    definitions.append(current_def)
                current_def = {"meaning": "", "example": "", "synonyms": "", "antonyms": ""}
                current_def["meaning"] = kaofa_match.group(1).strip()
                continue
            if line.startswith('例') or line.startswith('例\u3000'):
                if current_def:
                    current_def["example"] = line.lstrip('例').lstrip('\u3000').strip()
                continue
            if line.startswith('近') or line.startswith('近\u3000'):
                if current_def:
                    current_def["synonyms"] = line.lstrip('近').lstrip('\u3000').strip()
                continue
            if line.startswith('反') or line.startswith('反\u3000'):
                if current_def:
                    current_def["antonyms"] = line.lstrip('反').lstrip('\u3000').strip()
                continue
        
        if current_def:
            definitions.append(current_def)
        
        entries.append({"word": word, "phonetic": phonetic, "definitions": definitions})
    
    return entries


def build_explanation(word: dict) -> str:
    parts = [f"音标: {word['phonetic']}", ""]
    for i, d in enumerate(word['definitions'], 1):
        parts.append(f"考法{i}: {d['meaning']}")
        if d['example']:
            parts.append(f"例句: {d['example']}")
        if d['synonyms']:
            parts.append(f"近义: {d['synonyms']}")
        if d['antonyms']:
            parts.append(f"反义: {d['antonyms']}")
        parts.append("")
    return "\n".join(parts)


def build_answer(word: dict) -> str:
    if not word['definitions']:
        return ""
    first = word['definitions'][0]
    meaning = first['meaning']
    if '：' in meaning:
        parts = meaning.split('：', 1)
        return f"{parts[0].strip()}：{parts[1].strip()}"
    return meaning


def build_context_question(word: dict) -> str:
    for d in word['definitions']:
        example = d.get('example', '')
        if word['word'].lower() in example.lower():
            pattern = re.compile(re.escape(word['word']), re.IGNORECASE)
            return pattern.sub('______', example)
    return None


def import_gre_to_db(db_path: str = "data/wordcard.db", azw3_path: str = None):
    if azw3_path is None:
        azw3_path = '/root/A00962. GRE核心词汇考法精析 (新东方大愚英语学习丛书).B00GWD2L4W.azw3'
    
    print("=" * 60)
    print("GRE 核心词汇 → WordCard 数据库导入")
    print("=" * 60)
    
    print(f"\n[1/6] 解析词汇书: {azw3_path}")
    result = parse_mobi(azw3_path)
    words = parse_gre_vocab(result['text'])
    print(f"      共解析 {len(words)} 个单词")
    
    print(f"\n[2/6] 初始化数据库: {db_path}")
    db = WordCardDB(db_path)
    print(f"      数据库就绪")
    
    print(f"\n[3/6] 创建内容源: GRE核心词汇考法精析")
    source_id = db.add_source(
        name="GRE核心词汇考法精析",
        source_type=2,
        file_path=azw3_path
    )
    print(f"      Source ID: {source_id}")
    
    print(f"\n[4/6] 导入基础卡片（单词→释义）...")
    imported = 0
    for word in words:
        db.add_item(
            question=word['word'],
            answer=build_answer(word),
            explanation=build_explanation(word),
            hint=word['phonetic'],
            difficulty=3,
            source_id=source_id,
            category=5,
            tags="gre,vocab,基础卡"
        )
        imported += 1
        if imported % 500 == 0:
            print(f"      ...已导入 {imported} 个")
    print(f"      基础卡片导入完成: {imported} 个")
    
    print(f"\n[5/6] 导入考法卡片（真题语境填空）...")
    context_imported = 0
    for word in words:
        question_text = build_context_question(word)
        if not question_text:
            continue
        explanation = f"正确答案: {word['word']}\n音标: {word['phonetic']}\n\n"
        explanation += build_explanation(word)
        db.add_item(
            question=question_text,
            answer=f"{word['word']} ({word['phonetic']})",
            explanation=explanation,
            hint=word['phonetic'],
            difficulty=4,
            source_id=source_id,
            category=5,
            tags="gre,vocab,语境填空"
        )
        context_imported += 1
        if context_imported % 500 == 0:
            print(f"      ...已导入 {context_imported} 个")
    print(f"      考法卡片导入完成: {context_imported} 个")
    
    print(f"\n[6/6] 保存数据库...")
    db.save()
    db.close()
    
    db_file = Path(db_path)
    if db_file.exists():
        size_mb = db_file.stat().st_size / (1024 * 1024)
        print(f"\n{'='*60}")
        print(f"✅ 导入完成!")
        print(f"{'='*60}")
        print(f"   数据库文件: {db_path}")
        print(f"   文件大小: {size_mb:.1f} MB")
        print(f"   基础卡片: {imported} 个")
        print(f"   考法卡片: {context_imported} 个")
        print(f"   总计: {imported + context_imported} 个学习项")
        print(f"\n📦 迁移说明:")
        print(f"   只需复制 '{db_path}' 这一个文件到其他服务器")
        print(f"   启动: python api.py")
        print(f"   即可直接使用，无需任何额外配置")
        print(f"{'='*60}")
        
        print(f"\n🔍 验证数据库可读性...")
        db2 = WordCardDB(db_path)
        item = db2.find_item(item_id=1)
        if item:
            print(f"   样本卡片:")
            print(f"   Q: {item['question']}")
            print(f"   A: {item['answer'][:60]}...")
        db2.close()
    else:
        print("❌ 数据库保存失败")


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="GRE 词汇导入工具")
    parser.add_argument("--db", default="data/wordcard.db", help="数据库路径")
    parser.add_argument("--book", default=None, help="AZW3 文件路径")
    args = parser.parse_args()
    import_gre_to_db(args.db, args.book)
