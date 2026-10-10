#!/usr/bin/env python3
"""define_words.py — 为一批单词查释义（供 App 粘贴导入用）。

从 stdin 逐行读单词，输出逐行 JSON：
    {"w":"abandon","ph":"...","p":"vt.","d":"放弃, 抛弃"}
释义优先离线查 ECDICT，未收录的用本地 LLM 兜底（若可用）。

用法: printf 'abandon\norbit\n' | python3 tools/define_words.py
"""

import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
sys.path.insert(0, os.path.join(ROOT, 'tools'))

import bilingual  # noqa: E402


def main():
    words = [l.strip() for l in sys.stdin if l.strip()]
    if not words:
        return
    ecd = bilingual.lookup_many(words)
    need = [w for w in words if w.lower() not in ecd]

    llm = None
    if need:
        try:
            import translate
            if translate.available():
                llm = translate
        except Exception:  # noqa: BLE001
            llm = None

    for w in words:
        wl = w.lower()
        ph = pos = zh = ''
        if wl in ecd:
            ph, pos, zh, _en = ecd[wl]
        elif llm is not None:
            try:
                _en, zh, pos = llm.define(w)
            except Exception:  # noqa: BLE001
                pass
        print(json.dumps({'w': w, 'ph': ph, 'p': pos, 'd': zh},
                         ensure_ascii=False), flush=True)


if __name__ == '__main__':
    main()
