#!/usr/bin/env python3
"""deepseek_chat.py — 一次性 DeepSeek 对话调用（独立进程，避免长驻进程网络状态问题）。

stdin:  {"messages":[...],"max_tokens":500,"temperature":0.7,"json_mode":true}
stdout: {"ok":true,"text":"..."} 或 {"ok":false,"error":"..."}
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

import translate  # noqa: E402


def main():
    try:
        req = json.load(sys.stdin)
        text = translate.chat_deepseek(
            req.get('messages') or [],
            max_tokens=int(req.get('max_tokens') or 500),
            temperature=float(req.get('temperature', 0.7)),
            json_mode=bool(req.get('json_mode')),
        )
        print(json.dumps({'ok': True, 'text': text}, ensure_ascii=False))
    except Exception as e:  # noqa: BLE001
        print(json.dumps({'ok': False, 'error': str(e)}, ensure_ascii=False))


if __name__ == '__main__':
    main()
