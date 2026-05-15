#!/usr/bin/env python3
"""
英文全书精读导入系统（双语增强版）

功能：
1. 解析 PDF/MOBI 全书，按章节分块
2. 每章提取核心生词
3. 【双语模式】调用本地 LLM (llama.cpp/Ollama) 生成：
   - 中英双语段落（英文原文 + 中文翻译对照）
   - 中文理解题（基于段落内容，不是词汇题）
4. 渐进式解锁：第1章默认开放，后续章节需掌握前章80%词汇

用法：
    python import_book.py --book book.pdf --title "Book Name" --translate
    
    # 完成后启动学习：
    python api.py
"""
import sys
import re
import random
import json
import requests
from collections import Counter
from pathlib import Path
from typing import List, Dict

sys.path.insert(0, str(Path(__file__).parent))

from api import WordCardDB
from importer import parse_pdf, parse_mobi

# ========================================================================
# 配置
# ========================================================================

LLM_API_URL = "http://localhost:11434/v1/chat/completions"
LLM_MODEL = "Qwen3-8B-Q4_K_M.gguf"

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
    'yours', 'hers', 'ours', 'theirs', 'one', 'two', 'three', 'four',
    'five', 'six', 'seven', 'eight', 'nine', 'ten', 'first', 'second',
    'third', 'last', 'next', 'many', 'much', 'some', 'any', 'all', 'each',
    'every', 'both', 'few', 'more', 'most', 'other', 'such', 'no', 'not',
    'only', 'own', 'same', 'than', 'too', 'very', 'just', 'now', 'then',
    'here', 'there', 'up', 'out', 'off', 'over', 'again', 'further',
    'once', 'down', 'also', 'back', 'still', 'even', 'new', 'like',
    'well', 'way', 'make', 'see', 'know', 'take', 'get', 'go', 'come',
    'think', 'say', 'help', 'show', 'play', 'run', 'move', 'live',
    'believe', 'hold', 'bring', 'happen', 'stand', 'lose', 'pay',
    'meet', 'include', 'continue', 'set', 'learn', 'change', 'lead',
    'understand', 'watch', 'follow', 'stop', 'create', 'speak', 'read',
    'allow', 'add', 'spend', 'grow', 'open', 'walk', 'win', 'offer',
    'remember', 'love', 'consider', 'appear', 'buy', 'wait', 'serve',
    'die', 'send', 'expect', 'build', 'stay', 'fall', 'cut', 'reach',
    'kill', 'remain', 'suggest', 'raise', 'pass', 'sell', 'require',
    'report', 'decide', 'pull', 'figure', 'chapter', 'section', 'page',
    'introduction', 'conclusion', 'summary', 'figure', 'table',
}


# ========================================================================
# LLM 翻译与出题
# ========================================================================

def call_llm(system_prompt: str, user_prompt: str, max_tokens: int = 2048) -> str:
    """调用本地 llama.cpp API"""
    try:
        resp = requests.post(
            LLM_API_URL,
            json={
                "model": LLM_MODEL,
                "messages": [
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": user_prompt}
                ],
                "max_tokens": max_tokens,
                "temperature": 0.3,
                "top_p": 0.9,
            },
            timeout=300
        )
        resp.raise_for_status()
        return resp.json()["choices"][0]["message"]["content"]
    except Exception as e:
        print(f"      ⚠️ LLM 调用失败: {e}")
        return ""


def translate_paragraph(text: str) -> str:
    """将英文段落翻译为中英双语对照格式"""
    system = "你是一个专业的技术文档翻译助手。请将用户提供的英文段落翻译为中文，并输出中英双语对照格式。"
    prompt = f"""请将以下英文段落翻译为中文，输出格式如下：

【英文原文】
（原文）

【中文翻译】
（翻译）

注意：
- 保持技术术语准确
- 翻译要通顺自然
- 不要省略任何内容

英文段落：
{text}
"""
    return call_llm(system, prompt, max_tokens=4096)


def generate_chinese_quiz(text: str) -> List[Dict]:
    """基于英文段落生成中文理解题（不是词汇题，是真正的理解题）"""
    system = "你是一个阅读理解出题专家。请根据提供的英文段落，出 2 道中文理解选择题。"
    prompt = f"""请阅读以下英文段落，然后出 2 道中文理解选择题。

要求：
1. 题目必须用中文
2. 每题有 4 个选项（A/B/C/D）
3. 考查的是对段落内容的理解，不是词汇
4. 输出格式严格如下：

---
Q1: [中文问题]
A) [选项]
B) [选项]
C) [选项]
D) [选项]
答案: [A/B/C/D]
解析: [为什么选这个]
---
Q2: [中文问题]
A) [选项]
B) [选项]
C) [选项]
D) [选项]
答案: [A/B/C/D]
解析: [为什么选这个]
---

英文段落：
{text}
"""
    result = call_llm(system, prompt, max_tokens=2048)
    quizzes = []
    
    # 简单解析 LLM 输出
    blocks = result.split("---")
    for block in blocks:
        if "Q" in block and "答案:" in block:
            lines = [l.strip() for l in block.strip().split("\n") if l.strip()]
            question = ""
            options = []
            answer = ""
            explanation = ""
            
            for line in lines:
                if line.startswith("Q") and ":" in line:
                    question = line.split(":", 1)[1].strip()
                elif line.startswith(("A)", "B)", "C)", "D)")):
                    options.append(line)
                elif line.startswith("答案:"):
                    answer = line.split(":", 1)[1].strip()
                elif line.startswith("解析:"):
                    explanation = line.split(":", 1)[1].strip()
            
            if question and options:
                quizzes.append({
                    "question": question,
                    "options": "\n".join(options),
                    "answer": answer,
                    "explanation": explanation,
                })
    
    return quizzes


# ========================================================================
# 全书解析（与之前版本相同）
# ========================================================================

class BookChapter:
    def __init__(self, number: int, title: str, text: str, start_page: int = 0):
        self.number = number
        self.title = title
        self.text = text
        self.start_page = start_page
        self.words = []
        self.bilingual_text = ""
        self.quizzes = []


def split_into_chapters(text: str, page_break_marker: str = "--- Page Break ---") -> List[BookChapter]:
    """
    智能分章：支持 PDF (有页码分隔) 和 MOBI (纯文本流) 两种格式。
    
    MOBI 特征：
    - 无页码分隔符，纯换行文本流
    - 章节标题格式多样：Chapter 1 / PART I / 1 TITLE / 全大写标题
    - 前面常有目录区域重复标题
    """
    
    # ========================================================================
    # PDF 格式：有页码分隔符
    # ========================================================================
    if page_break_marker in text:
        pages = text.split(page_break_marker)
        chapters = []
        current_text = []
        chapter_num = 1
        chapter_title = "Introduction"
        start_page = 1
        
        chapter_pattern = re.compile(r'(?:Chapter|CHAPTER|Part|PART)\s+(\d+|One|Two|Three|Four|Five|Six|Seven|Eight|Nine|Ten|I|II|III|IV|V|VI|VII|VIII|IX|X)[\s:.-]*(.*)', re.IGNORECASE)
        
        for i, page in enumerate(pages):
            match = chapter_pattern.search(page)
            if match and i > 0 and len(current_text) > 5:
                chapters.append(BookChapter(chapter_num, chapter_title, "\n".join(current_text), start_page))
                chapter_num += 1
                chapter_title = match.group(0)
                start_page = i + 1
                current_text = [page]
            else:
                current_text.append(page)
        
        if current_text:
            chapters.append(BookChapter(chapter_num, chapter_title, "\n".join(current_text), start_page))
        
        # 如果没检测到章节，按每10页聚合
        if len(chapters) <= 1 and len(pages) > 10:
            chapters = []
            for i in range(0, len(pages), 10):
                chapters.append(BookChapter(len(chapters)+1, f"Part {len(chapters)+1}", "\n".join(pages[i:i+10]), i+1))
        
        return chapters
    
    # ========================================================================
    # MOBI/AZW3 格式：纯文本流
    # ========================================================================
    
    lines = text.split('\n')
    total_lines = len(lines)
    
    if total_lines < 50:
        return [BookChapter(1, "Content", text, 1)]
    
    # 检测目录区域结束位置
    # 特征：连续多行出现 "Chapter X: ...描述..." 格式
    toc_end = 0
    chapter_summary_pattern = re.compile(r'^Chapter\s+\d+[:.\s]', re.IGNORECASE)
    summary_count = 0
    for i, line in enumerate(lines[:min(500, total_lines)]):
        if chapter_summary_pattern.match(line.strip()):
            summary_count += 1
            if summary_count >= 3:
                toc_end = i + 1
    
    # 如果检测到目录，从目录结束后开始搜索正文标题
    search_start = toc_end if toc_end > 100 else 0
    
    # ========================================================================
    # 阶段 1: 检测章节标题位置（优先 Chapter X，其次 PART/数字标题）
    # ========================================================================
    
    chapter_positions = []  # (line_idx, title_text)
    
    # 模式 A: "Chapter X: Title"（最优先）
    for i in range(search_start, total_lines):
        line = lines[i].strip()
        if not line:
            continue
        m = re.match(r'^Chapter\s+(\d+)[:.\s-]+\s*(.+)', line, re.IGNORECASE)
        if m and len(m.group(2)) > 3:
            chapter_positions.append((i, m.group(2).strip()))
    
    # 如果没找到 Chapter X，尝试 "数字 + 大写标题"（如 "1 DATA ENGINEERING BASICS"）
    if len(chapter_positions) < 2:
        for i in range(search_start, total_lines):
            line = lines[i].strip()
            if not line or len(line) > 60:
                continue
            m = re.match(r'^(\d+)\s+([A-Z][A-Z\s&]{5,50})$', line)
            if m:
                chapter_positions.append((i, m.group(2).strip()))
    
    # ========================================================================
    # 阶段 2: 去重（跳过目录中的重复）
    # ========================================================================
    
    deduped = []
    seen = {}
    for pos, title in chapter_positions:
        key = title.lower()
        if key in seen:
            # 如果同一个标题之前出现过，且间隔 > 30 行，替换为后面的（正文）
            if pos - seen[key] > 30:
                for j, (p, t) in enumerate(deduped):
                    if t.lower() == key:
                        deduped[j] = (pos, title)
                        break
        else:
            seen[key] = pos
            deduped.append((pos, title))
    
    # ========================================================================
    # 阶段 3: 构建章节
    # ========================================================================
    
    chapters = []
    
    if len(deduped) >= 2:
        for i, (pos, title) in enumerate(deduped):
            if i + 1 < len(deduped):
                end_pos = deduped[i + 1][0]
            else:
                end_pos = total_lines
            
            chapter_text = '\n'.join(lines[pos:end_pos])
            if len(chapter_text) > 500:  # 至少 500 字符才认为是有效章节
                chapters.append(BookChapter(
                    number=len(chapters) + 1,
                    title=title,
                    text=chapter_text,
                    start_page=pos
                ))
    
    # ========================================================================
    # 阶段 4: 如果分章失败或太少，按固定长度分块
    # ========================================================================
    
    if len(chapters) < 2:
        print("      标题检测不足，改用固定长度分块...")
        chapters = []
        chunk_lines = 300
        for i in range(0, total_lines, chunk_lines):
            chunk = lines[i:i + chunk_lines]
            title = f"Section {len(chapters) + 1}"
            for line in chunk[:5]:
                line = line.strip()
                if line and 10 < len(line) < 50 and line[0].isupper():
                    title = line
                    break
            chapters.append(BookChapter(
                number=len(chapters) + 1,
                title=title,
                text='\n'.join(chunk),
                start_page=i
            ))
    
    return chapters


def extract_vocab(text: str, known_words: set, max_words: int = 25) -> List[Dict]:
    words = re.findall(r'\b[a-zA-Z]+\b', text.lower())
    freq = Counter(words)
    candidates = [(w, c) for w, c in freq.most_common() if w not in STOP_WORDS and len(w) >= 4 and w not in known_words]
    
    sentences = re.split(r'[.!?]\s+', text)
    result = []
    
    for word, count in candidates[:max_words]:
        example = ""
        for sent in sentences:
            if word in sent.lower() and 20 < len(sent) < 200:
                example = sent.strip()
                break
        result.append({"word": word, "frequency": count, "example": example})
    
    return result


def extract_key_paragraph(text: str, max_chars: int = 1500) -> str:
    """提取章节中最有信息量的段落用于翻译"""
    paragraphs = [p.strip() for p in text.split('\n') if len(p.strip()) > 100]
    if not paragraphs:
        return text[:max_chars]
    
    # 优先选包含技术术语、定义、因果关系的段落
    info_paras = []
    for p in paragraphs:
        score = 0
        if any(kw in p.lower() for kw in ['because', 'therefore', 'however', 'defined', 'called', 'refers', 'means', 'is a']):
            score += 3
        if re.search(r'\b\w+(?:tion|ment|ness|ity|ism|ology)\b', p):
            score += 2
        if len(p) > 300:
            score += 1
        info_paras.append((score, p))
    
    info_paras.sort(key=lambda x: -x[0])
    
    selected = []
    total_len = 0
    for score, p in info_paras[:5]:
        if total_len + len(p) > max_chars:
            break
        selected.append(p)
        total_len += len(p)
    
    return "\n\n".join(selected)


# ========================================================================
# 主导入流程
# ========================================================================

def import_book(book_path: str, db_path: str = "data/wordcard.db", title: str = None, translate: bool = False):
    print("=" * 60)
    print("📚 全书精读导入系统" + ("（双语增强版）" if translate else ""))
    print("=" * 60)
    
    # 1. 解析
    print(f"\n[1/6] 解析电子书: {book_path}")
    ext = Path(book_path).suffix.lower()
    if ext in ('.mobi', '.azw', '.azw3'):
        result = parse_mobi(book_path)
    else:
        result = parse_pdf(book_path)
    
    full_text = result.get("text", "")
    page_count = result.get("page_count", 0)
    print(f"      总页数: {page_count}")
    print(f"      总字符: {len(full_text):,}")
    
    # 2. 分章
    print(f"\n[2/6] 分章节...")
    chapters = split_into_chapters(full_text)
    print(f"      共 {len(chapters)} 个章节")
    
    # 3. 数据库
    print(f"\n[3/6] 初始化数据库: {db_path}")
    db = WordCardDB(db_path)
    
    book_title = title or Path(book_path).stem
    source_id = db.add_source(name=book_title, source_type=1, file_path=book_path)
    print(f"      Source ID: {source_id}")
    
    # 4. 逐章处理
    print(f"\n[4/6] 逐章处理...")
    if translate:
        print("      🌐 双语模式开启：将调用本地 LLM 生成翻译和理解题")
    
    known_words = set()
    total_vocab = 0
    total_quiz = 0
    
    for idx, ch in enumerate(chapters):
        print(f"\n      处理 Ch.{ch.number}: {ch.title[:40]}")
        
        # 提取词汇
        vocab = extract_vocab(ch.text, known_words, max_words=20)
        ch.words = vocab
        
        # 导入词汇卡
        for v in vocab:
            expl = f"频率: {v['frequency']} 次"
            if v['example']:
                expl += f"\n例句: {v['example']}"
            db.add_item(
                question=v['word'],
                answer="见原文语境",
                explanation=expl,
                hint=f"Ch.{ch.number}",
                difficulty=3, source_id=source_id, category=1,
                tags=f"book,{book_title},ch{ch.number},精读词汇"
            )
            total_vocab += 1
            known_words.add(v['word'])
        
        # 【双语模式】翻译 + 出中文理解题
        if translate:
            key_para = extract_key_paragraph(ch.text, max_chars=1200)
            if key_para:
                print(f"      → 调用 LLM 翻译关键段落...")
                ch.bilingual_text = translate_paragraph(key_para)
                
                if ch.bilingual_text:
                    print(f"      → 调用 LLM 生成中文理解题...")
                    ch.quizzes = generate_chinese_quiz(key_para)
                    
                    # 导入双语阅读卡
                    db.add_item(
                        question=f"【Ch.{ch.number} 双语阅读】{ch.title[:30]}",
                        answer="见详解",
                        explanation=ch.bilingual_text[:1023],
                        hint="中英对照阅读",
                        difficulty=3, source_id=source_id, category=1,
                        tags=f"book,{book_title},ch{ch.number},双语阅读"
                    )
                    
                    # 导入中文理解题
                    for q in ch.quizzes:
                        db.add_item(
                            question=q['question'],
                            answer=f"正确答案: {q['answer']}",
                            explanation=f"{q['options']}\n\n解析: {q['explanation']}",
                            hint=f"Ch.{ch.number} 理解题",
                            difficulty=4, source_id=source_id, category=1,
                            tags=f"book,{book_title},ch{ch.number},中文理解题"
                        )
                        total_quiz += 1
        else:
            # 纯英文理解题（填空）
            sentences = [s.strip() for s in re.split(r'[.!?]\s+', ch.text) if len(s.strip()) > 50]
            info_sents = [s for s in sentences if any(kw in s.lower() for kw in ['because', 'therefore', 'however', 'defined', 'called'])]
            if info_sents:
                sent = random.choice(info_sents[:10])
                words = re.findall(r'\b[a-zA-Z]{6,}\b', sent)
                if words:
                    target = random.choice(words)
                    blanked = sent.replace(target, "______", 1)
                    db.add_item(
                        question=blanked,
                        answer=target,
                        explanation=f"原文: {sent}",
                        hint=f"Ch.{ch.number}",
                        difficulty=4, source_id=source_id, category=1,
                        tags=f"book,{book_title},ch{ch.number},理解题"
                    )
                    total_quiz += 1
        
        print(f"      → 词汇 {len(vocab)} 个" + (f", 中文理解题 {len(ch.quizzes)} 道" if translate else f", 理解题 +1"))
        
        # 每5章保存一次，避免内存累积
        if idx % 5 == 0:
            db.save()
    
    # 5. 保存
    print(f"\n[5/6] 保存数据库...")
    db.save()
    db.close()
    
    # 6. 报告
    print(f"\n{'='*60}")
    print(f"✅ 导入完成: {book_title}")
    print(f"{'='*60}")
    print(f"   章节数: {len(chapters)}")
    print(f"   词汇卡: {total_vocab} 个")
    print(f"   理解题: {total_quiz} 道")
    if translate:
        print(f"   双语阅读段落: {len(chapters)} 个")
    print(f"   数据库: {db_path}")
    print(f"\n📖 学习流程:")
    print(f"   1. python api.py")
    print(f"   2. 访问 http://localhost:8000/docs")
    if translate:
        print(f"   3. 每日队列: 词汇 → 双语阅读 → 中文理解题")
        print(f"   4. 先看中英对照，再做题检验理解")
    else:
        print(f"   3. 每日队列: 词汇 → 理解题 → 阅读原文")
    print(f"{'='*60}")


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="英文全书精读导入")
    parser.add_argument("--book", required=True, help="电子书路径 (PDF/MOBI/AZW3)")
    parser.add_argument("--db", default="data/wordcard.db", help="数据库路径")
    parser.add_argument("--title", default=None, help="书名")
    parser.add_argument("--translate", action="store_true", help="启用中英双语模式（需要本地 LLM 服务 localhost:11434）")
    args = parser.parse_args()
    
    import_book(args.book, args.db, args.title, args.translate)
