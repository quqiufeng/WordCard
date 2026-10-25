#!/usr/bin/env python3
"""memo_server.py — 常驻「助记 / 段落翻译 / 查词」服务（按需生成）。

App 在复习或双语阅读时，向本服务写一行 JSON；服务用本地 ECDICT 查词、
本地 LLM 生成助记/译文并回传。结果缓存，重复即时返回。

stdin 每行:
  {"w":"orbit","ctx":"The satellite orbits the Earth."}   → {"w":"orbit","memo":"..."}
  {"t":"English paragraph","w":"orbit"(可选)}              → {"t":"...","zh":"..."}
  {"lookup":"orbits"}                                      → {"lookup":"orbits","ph":...,"p":...,"d":...}
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


def _lemma_candidates(word):
    """轻量词形还原候选（不规则变化仍交给 LLM）。"""
    w = word.lower().strip()
    out = [w]
    if len(w) < 3:
        return out
    if w.endswith("'s") or w.endswith('’s'):
        out.append(w[:-2])
    if w.endswith('ies') and len(w) > 4:
        out.append(w[:-3] + 'y')
    if w.endswith('es') and len(w) > 3:
        out.append(w[:-2])
    if w.endswith('s') and len(w) > 2:
        out.append(w[:-1])
    if w.endswith('ied') and len(w) > 4:
        out.append(w[:-3] + 'y')
    if w.endswith('ed') and len(w) > 3:
        out.append(w[:-2])
        out.append(w[:-1])
        if len(w) > 4 and w[-3] == w[-4]:
            out.append(w[:-3])
    if w.endswith('ing') and len(w) > 4:
        out.append(w[:-3])
        out.append(w[:-3] + 'e')
        if len(w) > 5 and w[-4] == w[-5]:
            out.append(w[:-4])
    if w.endswith('ly') and len(w) > 4:
        out.append(w[:-2])
    # 去重、保序
    seen, uniq = set(), []
    for c in out:
        if c and c not in seen:
            seen.add(c)
            uniq.append(c)
    return uniq[:8]


def main():
    cache = bilingual.load_trans_cache()
    lookups = {}
    print('READY', flush=True)

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
        except Exception:  # noqa: BLE001
            continue

        # 查词（阅读页点词）: {"lookup":"orbits"} -> 音标/词性/释义
        lookup_word = str(req.get('lookup') or '').strip()
        if lookup_word:
            key = lookup_word.lower()
            ent = lookups.get(key)
            if ent is None:
                ph = pos = zh = en = base = ''
                cands = _lemma_candidates(lookup_word)
                ecd = bilingual.lookup_many(cands)
                for cand in cands:
                    if cand in ecd:
                        ph, pos, zh, en = ecd[cand]
                        base = cand if cand != key else ''
                        break
                if not zh:
                    try:
                        if translate.available():
                            en, zh, pos = translate.define(lookup_word)
                    except Exception:  # noqa: BLE001
                        pass
                ent = {'ph': ph, 'p': pos, 'd': zh, 'en': en, 'base': base}
                if zh:
                    lookups[key] = ent
            payload = {'lookup': lookup_word}
            payload.update(ent or {'ph': '', 'p': '', 'd': '', 'en': '', 'base': ''})
            print(json.dumps(payload, ensure_ascii=False), flush=True)
            continue

        # 确保本地 LLM 在线（若被关闭则自动拉起）
        try:
            translate.available()
        except Exception:  # noqa: BLE001
            pass

        # 翻译一段文本: {"t":"English...","w":"word"(可选)} -> {"t":..., "zh":...}
        text = req.get('t')
        if text:
            word = req.get('w', '')
            ckey = (word + '\n' + text) if word else text
            key = bilingual.trans_key(ckey)
            zh = cache.get(key, '')
            if not zh:
                try:
                    zh = translate.translate(text, highlight=word or None)
                except Exception:  # noqa: BLE001
                    zh = ''
                if zh:
                    cache[key] = zh
                    bilingual.append_trans_cache(ckey, zh)
            print(json.dumps({'t': text, 'zh': zh}, ensure_ascii=False),
                  flush=True)
            continue

        # 生成助记: {"w":"orbit","ctx":"..."} -> {"w":..., "memo":...}
        word = req.get('w', '')
        ctx = req.get('ctx', '')
        if not word:
            continue
        key = bilingual.trans_key('memo:' + word.lower())
        memo = cache.get(key, '')
        if not memo:
            try:
                translate.available()
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
