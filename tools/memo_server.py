#!/usr/bin/env python3
"""memo_server.py — 常驻「用法/场景」助记服务（按需生成）。

App 在复习到某个尚无 memo 的词时，向本服务写一行 JSON；服务用本地 LLM
生成一句中文用法描述并回传，App 再写回卡片。结果缓存，重复即时返回。

stdin 每行: {"w":"orbit","ctx":"The satellite orbits the Earth."}
stdout 每行: {"w":"orbit","memo":"..."}
启动后打印: READY
"""

import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
sys.path.insert(0, os.path.join(ROOT, 'tools'))

import bilingual  # noqa: E402
import translate  # noqa: E402


def main():
    cache = bilingual.load_trans_cache()
    try:
        translate.available()  # 确保本地 LLM server 已就绪
    except Exception as e:  # noqa: BLE001
        print(f'ERR {e}', file=sys.stderr, flush=True)
    print('READY', flush=True)

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
        except Exception:  # noqa: BLE001
            continue
        word = req.get('w', '')
        ctx = req.get('ctx', '')
        if not word:
            continue
        key = bilingual.trans_key('memo:' + word.lower())
        memo = cache.get(key, '')
        if not memo:
            try:
                memo = translate.memo(word, ctx)
            except Exception:  # noqa: BLE001
                memo = ''
            if memo:
                cache[key] = memo
                bilingual.append_trans_cache('memo:' + word.lower(), memo)
        print(json.dumps({'w': word, 'memo': memo}, ensure_ascii=False),
              flush=True)


if __name__ == '__main__':
    main()
