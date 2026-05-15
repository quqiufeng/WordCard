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

def generate_chapter_card(chapter_data: dict, output_path: str):
    fonts = load_fonts()
    if not fonts:
        return False
    
    # 计算高度
    y = MARGIN + 50
    vocab_count = len(chapter_data.get('vocab', []))
    y += vocab_count * 70
    
    if chapter_data.get('quiz'):
        y += 200
    
    y += MARGIN
    
    # 创建图片
    img = Image.new('RGB', (CARD_WIDTH, y), '#F5F5F5')
    draw = ImageDraw.Draw(img)
    y = MARGIN
    
    # 标题
    draw.text((MARGIN, y), f"WordCard - {chapter_data['title']}", 
             font=fonts['section'], fill='#27AE60')
    y += 50
    
    # 生词
    draw.text((MARGIN, y), "核心生词", font=fonts['section'], fill='#34495E')
    y += 35
    
    for v in chapter_data.get('vocab', []):
        draw.text((MARGIN + 10, y), v['word'], font=fonts['text'], fill='#E74C3C')
        draw.text((MARGIN + 200, y), v.get('meaning', ''), font=fonts['text'], fill='#7F8C8D')
        y += 35
        if v.get('example'):
            draw.text((MARGIN + 20, y), v['example'][:100], font=fonts['small'], fill='#3498DB')
            y += 35
    
    # 理解题
    quiz = chapter_data.get('quiz')
    if quiz:
        y += 20
        draw.text((MARGIN, y), "理解测试", font=fonts['section'], fill='#34495E')
        y += 35
        draw.text((MARGIN + 10, y), quiz['question'][:100], font=fonts['text'], fill='#2C3E50')
        y += 35
    
    img.save(output_path, 'PNG')
    print(f"✅ 卡片已生成: {output_path}")
    return True

def generate_from_db(chapter_num: int, db_path: str = "data/wordcard.db", output_path: str = None):
    """从数据库读取章节数据生成卡片"""
    db = WordCardDB(db_path)
    
    # 查找章节标题
    source = None
    for i in range(1, 100):
        try:
            s = db.find_source_by_id(i)
            if s:
                source = s
                break
        except:
            pass
    
    book_title = source['name'] if source else "Unknown Book"
    
    # 收集该章节的词汇和理解题
    vocab_list = []
    quiz_data = None
    
    # 简化：遍历前500个item，找匹配的tags
    for i in range(1, 500):
        item = db.find_item(item_id=i)
        if not item:
            continue
        tags = item.get('tags', '')
        if f'ch{chapter_num}' not in tags:
            continue
        
        if '精读词汇' in tags:
            vocab_list.append({
                'word': item['question'],
                'meaning': item['answer'][:60],
                'example': item.get('explanation', '')[:150]
            })
        elif '理解题' in tags or '中文理解题' in tags:
            quiz_data = {
                'question': item['question'],
                'options': item.get('explanation', '')[:200],
                'answer': item['answer']
            }
    
    db.close()
    
    chapter_data = {
        'title': f'{book_title} - Ch.{chapter_num}',
        'vocab': vocab_list[:6],  # 最多6个词
        'quiz': quiz_data
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
    
    generate_from_db(args.chapter, args.output)
