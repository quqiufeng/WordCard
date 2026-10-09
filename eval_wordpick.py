#!/usr/bin/env python3
"""评估 wordpick 选词质量：Precision@K / Recall@K / NDCG@K + 覆盖率曲线

用法:
  python3 eval_wordpick.py BOOK --gt ground_truth.txt [--k 50]
  python3 eval_wordpick.py BOOK            # 无 GT 时用 zipf 中频段作代理 GT

GT 文件格式: 每行一个词，可选制表符后跟相关度 (2=必学,1=建议,0=可选)
"""
import sys, os, re, math, argparse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import importer, wordpick

def load_gt(path):
    gt = {}
    with open(path, encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split('\t')
            w = parts[0].strip().lower()
            rel = int(parts[1]) if len(parts) > 1 and parts[1].strip() else 1
            if w:
                gt[w] = rel
    return gt

def proxy_gt(words_ctx):
    """无 GT 时：用书内 zipf 中频段(3.0-4.5)的词作代理正样本"""
    gt = {}
    for w, _ctx in words_ctx:
        z = _zipf(w)
        if 3.0 <= z <= 4.5:
            gt[w] = 1
    return gt

_ZIPF = None
def _load_zipf():
    global _ZIPF
    if _ZIPF is not None:
        return _ZIPF
    _ZIPF = {}
    p = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                     'src', 'wordpick', 'en_freq.tsv')
    if os.path.exists(p):
        with open(p, encoding='utf-8') as f:
            for line in f:
                parts = line.rstrip('\n').split('\t')
                if len(parts) == 2:
                    _ZIPF[parts[0]] = float(parts[1])
    return _ZIPF

def _zipf(w):
    t = _load_zipf()
    if w in t:
        return t[w]
    # 简单回退
    for suf in ('s', 'es', 'ed', 'ing', 'ly'):
        if w.endswith(suf) and len(w) > len(suf) + 2:
            b = w[:-len(suf)]
            if b in t:
                return t[b]
    return 2.0

def precision_at_k(pred, gt, k):
    top = pred[:k]
    if not top:
        return 0.0
    return sum(1 for w in top if w in gt) / len(top)

def recall_at_k(pred, gt, k):
    if not gt:
        return 0.0
    return sum(1 for w in pred[:k] if w in gt) / len(gt)

def ndcg_at_k(pred, gt, k):
    dcg = 0.0
    for i, w in enumerate(pred[:k]):
        rel = gt.get(w, 0)
        dcg += (2 ** rel - 1) / math.log2(i + 2)
    idcg = 0.0
    for i, rel in enumerate(sorted(gt.values(), reverse=True)[:k]):
        idcg += (2 ** rel - 1) / math.log2(i + 2)
    return dcg / idcg if idcg > 0 else 0.0

def token_counts(text):
    """全书词频（用于覆盖率曲线）"""
    from collections import Counter
    cnt = Counter(re.findall(r"[a-zA-Z]+(?:'[a-zA-Z]+)?", text.lower()))
    total = sum(cnt.values())
    return cnt, total

def coverage_curve(selected, cnt, total):
    cum = 0
    pts = []
    for i, w in enumerate(selected, 1):
        cum += cnt.get(w, 0)
        pts.append((i, cum / total if total else 0.0))
    return pts

def ascii_curve(points, width=50, height=12):
    if not points:
        return ""
    maxn = points[-1][0]
    vmax = max(v for _, v in points) or 1e-9
    lines = []
    for row in range(height, -1, -1):
        y = row / height
        bar = "".join("█" if points[int(col/width*(len(points)-1))][1] >= y*vmax else " "
                      for col in range(width))
        lines.append(f"{y*vmax*100:5.1f}% |{bar}")
    lines.append("      +" + "-" * width)
    lines.append(f"       1 .. {maxn} 词（y 轴按峰值缩放）")
    return "\n".join(lines)

def run(book, gt_path, k, holdout=False):
    info = importer.extract(book)
    text = info['text']
    cnt, total = token_counts(text)

    if holdout:
        # 留出集：前半选词，后半的中频词作 GT（非循环）
        half = len(text) // 2
        a, b = text[:half], text[half:]
        words_ctx = importer.extract_words(a, max_words=100000)
        gt = proxy_gt(importer.extract_words(b, max_words=100000))
        gt_src = "(留出集: 后半 zipf 中频词)"
    else:
        words_ctx = importer.extract_words(text, max_words=100000)
        gt = load_gt(gt_path) if gt_path else proxy_gt(words_ctx)
        gt_src = gt_path if gt_path else "(代理: zipf 中频段 · 循环验证, 仅冒烟)"

    pred = [w for w, _ in words_ctx][:k]

    print(f"书: {book}")
    print(f"GT: {gt_src}  ({len(gt)} 词)")
    print(f"候选: {len(words_ctx)} 词, 全书 token: {total}")
    print()
    print(f"  P@{k}   = {precision_at_k(pred, gt, k):.3f}")
    print(f"  R@{k}   = {recall_at_k(pred, gt, k):.3f}")
    print(f"  NDCG@{k}= {ndcg_at_k(pred, gt, k):.3f}")
    print()

    # 基线对比（覆盖率曲线）
    import re as _re
    from collections import Counter
    tf_pred = [w for w, _ in sorted(((w, cnt.get(w, 0)) for w, _ in words_ctx),
                                     key=lambda x: -x[1])]
    zipf_pred = [w for w, _ in sorted(words_ctx, key=lambda x: abs(_zipf(x[0]) - 3.8))]

    print("=== 覆盖率曲线（学习 N 词覆盖全书 token %）===")
    for name, sel in [("wordpick", pred), ("TF基线", tf_pred), ("zipf基线", zipf_pred)]:
        cov = coverage_curve(sel[:k], cnt, total)
        print(f"\n[{name}] 末尾覆盖率 = {cov[-1][1]*100:.1f}%" if cov else f"[{name}] N/A")
    print()
    print("[wordpick] 覆盖率增长曲线:")
    print(ascii_curve(coverage_curve(pred, cnt, total)))

if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('book')
    ap.add_argument('--gt', default=None)
    ap.add_argument('--k', type=int, default=50)
    ap.add_argument('--holdout', action='store_true', help='留出集评估(非循环)')
    a = ap.parse_args()
    run(a.book, a.gt, a.k, a.holdout)
