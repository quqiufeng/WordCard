#!/usr/bin/env python3
"""WordCard CLI — 终端复习"""

import sys, os
sys.path.insert(0, os.path.dirname(__file__) or '.')
import engine, importer

def cmd_import(args):
    path = args[0] if args else None
    if not path:
        print('Usage: wordcard import <book.pdf|.mobi|.md>')
        return
    importer.import_book(path)

def cmd_review(args):
    db = engine.WordCardDB.open('data/wordcard.db')
    try:
        uid = 1
        now = engine.WordCardDB.now()
        queue = db.daily_queue(uid, now, 20)
        if not queue:
            print('No items to review today!')
            return
        total = len(queue)
        for idx, (item_id, mode) in enumerate(queue, 1):
            item = db.find_item(item_id=item_id)
            if not item:
                continue
            m = db.get_or_create_mastery(uid, item_id)
            q = item.question.decode('utf-8')
            a = item.answer.decode('utf-8')
            ex = item.explanation.decode('utf-8')
            print(f'\n[{idx}/{total}] {q}')
            if ex:
                print(f'  Context: {ex[:120]}')
            if a:
                print(f'  Answer hint: {a}')
            ans = input('> ').strip()
            if not ans:
                print('  Skipped')
                continue
            correct = ans.lower().strip('.!?') == q.lower().strip('.!?')
            ql = 4 if correct else 1
            db.sm2_update(m, ql)
            db.record_activity(uid, False, correct, 5)
            if correct:
                print(f'  Correct  (q={ql})  Next: {m.interval_days}d')
            else:
                print(f'  Wrong, answer: {q}  Next: {m.interval_days}d')
            db.save()
    finally:
        db.close()

def cmd_stats(args):
    db = engine.WordCardDB.open('data/wordcard.db')
    try:
        uid = 1
        today = engine.WordCardDB.today()
        now = engine.WordCardDB.now()
        due = db.get_due_items(uid, now, 9999)
        new = db.get_new_items(uid, 0, 9999)
        print(f'  Due for review: {len(due)}')
        print(f'  New items available: {len(new)}')
        user = db.find_user(user_id=uid)
        if user:
            print(f'  Daily new limit: {user.daily_new_limit}')
            print(f'  Daily review limit: {user.daily_review_limit}')
        print(f'  Today: {today}')
    finally:
        db.close()

def cmd_card(args):
    """wordcard card <item_id>"""
    if not args:
        print('Usage: wordcard card <item_id>')
        return
    item_id = int(args[0])
    db = engine.WordCardDB.open('data/wordcard.db')
    try:
        item = db.find_item(item_id=item_id)
        if not item:
            print(f'Item {item_id} not found')
            return
        q = item.question.decode('utf-8')
        a = item.answer.decode('utf-8')
        ex = item.explanation.decode('utf-8')
        text = f'Word: {q}\n\n'
        if a: text += f'Definition: {a}\n\n'
        if ex: text += f'Context: {ex}'
        import txt2png
        from txt2png import Canvas
        font = '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc'
        # estimate height
        probe = Canvas(500, 100)
        lines = text.split('\n')
        lh = 28
        h = len(lines) * lh + 80
        c = Canvas(500, h)
        y = 20
        for line in lines:
            a2 = c.ascent(font, 20)
            c.draw_text(font, 20, line, 20, y + a2)
            y += lh
        out = f'output/item_{item_id:04d}.png'
        c.save(out)
        print(f'  Saved: {out}')
    finally:
        db.close()

def cmd_help(args=None):
    print('''WordCard CLI
Usage: wordcard <command> [args]
Commands:
  import <file>   Import ebook (pdf/mobi/md)
  review           Interactive review session
  stats           Show learning statistics
  card <id>       Generate card PNG for item
  help            Show this help
''')

def main():
    cmds = {
        'import': cmd_import,
        'review': cmd_review,
        'stats':  cmd_stats,
        'card':   cmd_card,
        'help':   cmd_help,
    }
    if len(sys.argv) < 2 or sys.argv[1] not in cmds:
        cmd_help()
        return
    cmds[sys.argv[1]](sys.argv[2:])

if __name__ == '__main__':
    main()
