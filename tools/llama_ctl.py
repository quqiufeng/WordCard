#!/usr/bin/env python3
"""llama_ctl.py — 手动控制 WordCard 的翻译模型（终端里的 llama-server）。

用法:
    python3 tools/llama_ctl.py start    # 在终端窗口启动（已在线则跳过）
    python3 tools/llama_ctl.py stop     # 停止并释放显存
    python3 tools/llama_ctl.py status   # JSON 状态
"""

import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

import translate  # noqa: E402


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else 'status'
    if cmd == 'start':
        print(json.dumps({'ok': translate.ensure_server()},
                         ensure_ascii=False))
    elif cmd == 'stop':
        print(json.dumps({'ok': translate.stop_server()},
                         ensure_ascii=False))
    elif cmd == 'status':
        print(json.dumps(translate.server_status(), ensure_ascii=False))
    else:
        print(__doc__, file=sys.stderr)
        sys.exit(2)


if __name__ == '__main__':
    main()
