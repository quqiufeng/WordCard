#!/usr/bin/env python3
"""章节记忆卡片生成器 - 从数据库读取学习内容生成 PNG 卡片"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(Path(__file__).parent))

from api import WordCardDB

FONT_PATH = "LXGWWenKaiMono-Bold.ttf"
CARD_WIDTH = 780
MARGIN = 40

def load_fonts():
    try:
        return {
            'title': ImageFont.truetype(FONT_PATH, 32),
            'section': ImageFont.truetype(FONT_PATH, 24),
            'text': ImageFont.truetype(FONT_PATH, 22),
            'small': ImageFont.truetype(FONT_PATH, 18),
        }
    except Exception as e:
        print(f"字体加载失败: {e}")
        return None

def is_chinese(text):
    return any('\u4e00' <= c <= '\u9fff' for c in text)

def text_width(text):
    """计算显示宽度：英文=1, 中文=2"""
    w = 0
    for c in text:
        w += 2 if is_chinese(c) else 1
    return w

def wrap_english(text, max_width):
    """英文按单词换行"""
    if not text:
        return []
    words = text.split()
    lines = []
    current = ""
    for word in words:
        if text_width(current) + text_width(word) + 1 <= max_width:
            current += word + " "
        else:
            if current:
                lines.append(current.rstrip())
            current = word + " "
    if current:
        lines.append(current.rstrip())
    return lines

def wrap_chinese(text, max_chars):
    """中文按字符数换行"""
    if not text:
        return []
    return [text[i:i + max_chars] for i in range(0, len(text), max_chars)]

def wrap_auto(text, max_width):
    """自动根据语言选择换行方式"""
    if is_chinese(text):
        return wrap_chinese(text, max_width // 2)
    else:
        return wrap_english(text, max_width)

def generate_chapter_card(chapter_data: dict, output_path: str):
    """生成高信息密度的章节记忆卡片"""
    fonts = load_fonts()
    if not fonts:
        return False
    
    vocab_list = chapter_data.get('vocab', [])
    quiz = chapter_data.get('quiz')
    stats = chapter_data.get('stats', {})
    
    # 计算高度（每个元素分配足够空间）
    y = MARGIN
    
    # 头部区域
    y += 60  # 标题
    y += 40  # 统计信息栏
    y += 20  # 分隔线
    
    # 词汇区域（每个词：单词行 + 释义行 + 例句行 + 间距）
    for v in vocab_list:
        y += 32  # 单词
        if v.get('meaning'):
            y += 28  # 释义
        if v.get('example'):
            y += 50  # 例句（可能2行）
        y += 15  # 间距
    
    # 理解题区域
    if quiz:
        y += 40  # 标题
        y += 60  # 问题（可能2-3行）
        if quiz.get('options'):
            y += 100  # 选项
        y += 30  # 答案
    
    # 底部区域
    y += 60  # 学习提示
    y += MARGIN
    
    # 创建图片
    img = Image.new('RGB', (CARD_WIDTH, int(y)), '#F5F5F5')
    draw = ImageDraw.Draw(img)
    y = MARGIN
    
    # ========== 头部 ==========
    # 书名/章节标题
    title = chapter_data['title']
    draw.text((MARGIN, y), title, font=fonts['title'], fill='#27AE60')
    y += 45
    
    # 统计信息栏
    total = stats.get('total_vocab', len(vocab_list))
    mastered = stats.get('mastered', 0)
    progress = f"本章词汇: {total} 个 | 已掌握: {mastered} 个 | 卡片取前 {len(vocab_list)} 个高频词"
    draw.text((MARGIN, y), progress, font=fonts['small'], fill='#7F8C8D')
    y += 30
    
    # 分隔线
    draw.line((MARGIN, y, CARD_WIDTH - MARGIN, y), fill='#27AE60', width=2)
    y += 20
    
    # ========== 核心生词区 ==========
    draw.text((MARGIN, y), "📚 核心生词（按频率排序）", font=fonts['section'], fill='#34495E')
    y += 35
    
    for i, v in enumerate(vocab_list, 1):
        # 序号 + 英文单词（红色）+ 音标/频率
        freq_info = f"(出现{v.get('freq', 1)}次)" if v.get('freq', 1) > 1 else ""
        word_line = f"{i}. {v['word']} {freq_info}"
        draw.text((MARGIN + 10, y), word_line, font=fonts['text'], fill='#E74C3C')
        y += 32
        
        # 中文释义（灰色）
        meaning = v.get('meaning', '')
        if meaning and meaning != '见原文':
            draw.text((MARGIN + 30, y), f"   → {meaning}", font=fonts['text'], fill='#7F8C8D')
            y += 28
        
        # 原文例句（蓝色，斜体效果用小字号）
        example = v.get('example', '')
        if example:
            # 例句换行
            wrapped = wrap_auto(example, 65)
            for line in wrapped[:2]:  # 最多2行
                draw.text((MARGIN + 30, y), f"   ▶ {line}", font=fonts['small'], fill='#3498DB')
                y += 26
        
        y += 12  # 词间距
    
    # ========== 理解测试区 ==========
    if quiz:
        y += 10
        draw.line((MARGIN, y, CARD_WIDTH - MARGIN, y), fill='#E0E0E0', width=1)
        y += 15
        
        draw.text((MARGIN, y), "🧠 理解测试", font=fonts['section'], fill='#34495E')
        y += 35
        
        # 问题
        q_lines = wrap_auto(quiz['question'], 60)
        for line in q_lines[:3]:  # 最多3行
            draw.text((MARGIN + 10, y), line, font=fonts['text'], fill='#2C3E50')
            y += 30
        
        # 选项
        if quiz.get('options'):
            opts = quiz['options'].split('\n')[:4]
            for opt in opts:
                if opt.strip():
                    draw.text((MARGIN + 20, y), opt.strip()[:70], font=fonts['small'], fill='#555555')
                    y += 26
        
        y += 5
        # 答案（淡色，需要主动看）
        answer = quiz.get('answer', '')
        if answer:
            draw.text((MARGIN + 10, y), f"💡 答案: {answer}  （先思考再看）", 
                     font=fonts['small'], fill='#AAAAAA')
            y += 28
    
    # ========== 底部提示 ==========
    y += 15
    draw.line((MARGIN, y, CARD_WIDTH - MARGIN, y), fill='#E0E0E0', width=1)
    y += 15
    
    tips = [
        "💡 学习建议：",
        "   1. 先通读英文例句，尝试理解单词含义",
        "   2. 对照中文释义验证",
        "   3. 完成理解测试题",
        "   4. 返回阅读原文段落，检验是否流畅",
    ]
    for tip in tips:
        draw.text((MARGIN, y), tip, font=fonts['small'], fill='#27AE60')
        y += 24
    
    # 页脚
    y += 10
    from datetime import datetime
    footer = f"WordCard 精读卡片 | 生成于 {datetime.now().strftime('%Y-%m-%d')} | 掌握后解锁下一章"
    draw.text((MARGIN, y), footer, font=fonts['small'], fill='#AAAAAA')
    
    img.save(output_path, 'PNG')
    print(f"✅ 卡片已生成: {output_path} ({len(vocab_list)} 词)")
    return True

def generate_from_db(chapter_num: int, db_path: str = "data/wordcard.db", output_path: str = None):
    """从数据库读取章节数据，只取最核心的内容生成卡片"""
    db = WordCardDB(db_path)
    
    # 查找书名
    book_title = "精读课程"
    try:
        for i in range(1, 10):
            s = db.find_source_by_id(i)
            if s:
                book_title = s.get('name', '精读课程')
                break
    except:
        pass
    
    # 收集该章节数据
    vocab_list = []
    quiz_data = None
    
    # 扫描数据库找匹配的章节
    for i in range(1, 5000):
        try:
            item = db.find_item(item_id=i)
        except:
            continue
        if not item:
            continue
        
        tags = item.get('tags', '')
        if f'ch{chapter_num}' not in tags:
            continue
        
        if '精读词汇' in tags:
            # 解析 explanation 中的频率信息
            expl = item.get('explanation', '')
            freq = 1
            m = __import__('re').search(r'频率:\s*(\d+)', expl)
            if m:
                freq = int(m.group(1))
            
            # 提取例句
            example = ""
            m2 = __import__('re').search(r'例句:\s*(.+)', expl)
            if m2:
                example = m2.group(1).strip()[:120]
            
            vocab_list.append({
                'word': item['question'],
                'meaning': item['answer'][:60].replace('[Ch.', '').replace('] 见原文语境', '见原文'),
                'example': example,
                'freq': freq
            })
        
        elif '理解题' in tags and not quiz_data:
            quiz_data = {
                'question': item['question'][:150],
                'options': item.get('explanation', '')[:200],
                'answer': item['answer'][:20]
            }
    
    db.close()
    
    # 保留最高频的 10 个词（更多内容，卡片更丰富）
    vocab_list.sort(key=lambda x: -x['freq'])
    vocab_list = vocab_list[:10]
    
    chapter_data = {
        'title': f'{book_title} · Ch.{chapter_num}',
        'vocab': vocab_list,
        'quiz': quiz_data,
        'stats': {
            'total_vocab': len(vocab_list),
            'mastered': 0,
        }
    }
    
    if output_path is None:
        output_path = f"output/ch{chapter_num}_card.png"
    
    Path(output_path).parent.mkdir(parents=True, exist_ok=True)
    return generate_chapter_card(chapter_data, output_path)

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="章节记忆卡片生成器")
    parser.add_argument("--chapter", type=int, default=1, help="章节号")
    parser.add_argument("--output", default=None, help="输出路径")
    args = parser.parse_args()
    
    generate_from_db(args.chapter, "data/wordcard.db", args.output)
