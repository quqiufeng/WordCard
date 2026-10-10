#!/usr/bin/env python3
"""ocr_image.py — 用 PP-OCRv4 (libocr_simple.so) 识别图片里的文字，输出文本行。

参考 /opt/my-agent 的 OCR 集成（同一 PP-OCRv4 模型）。识别结果按行输出到
--out 文件（避免 stdout 噪声污染），供 App 解析成单词/词组后导入任务。

用法:
    python3 tools/ocr_image.py <image.png> [--out text.txt]

环境变量: WC_OCR_DET / WC_OCR_REC / WC_OCR_DICT / WC_OCR_LIB
说明: 需要 libonnxruntime.so.1 (VERS_1.26.0)，运行时请把其目录加入 LD_LIBRARY_PATH。
"""

import argparse
import ctypes
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

LIB = os.environ.get('WC_OCR_LIB',
                     os.path.join(ROOT, 'voice', 'libs', 'libocr_simple.so'))
DET = os.environ.get('WC_OCR_DET', os.path.join(ROOT, 'models', 'ocr',
                     'ch_PP-OCRv4_det_infer.onnx'))
REC = os.environ.get('WC_OCR_REC', os.path.join(ROOT, 'models', 'ocr',
                     'ch_PP-OCRv4_rec_infer.onnx'))
DICT = os.environ.get('WC_OCR_DICT', os.path.join(ROOT, 'models', 'ocr',
                       'ppocr_keys_v1.txt'))


def _to_lines(boxes):
    boxes.sort(key=lambda b: (b.get('y', 0), b.get('x', 0)))
    lines = []
    cur_y = None
    cur = []
    for b in boxes:
        y = b.get('y', 0)
        if cur_y is None or abs(y - cur_y) <= 12:
            cur.append(b)
            cur_y = y if cur_y is None else cur_y
        else:
            lines.append(' '.join(x.get('text', '') for x in
                                  sorted(cur, key=lambda z: z.get('x', 0))))
            cur = [b]
            cur_y = y
    if cur:
        lines.append(' '.join(x.get('text', '') for x in
                              sorted(cur, key=lambda z: z.get('x', 0))))
    return [l for l in lines if l.strip()]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('image')
    ap.add_argument('--out', help='识别文本写入该文件')
    args = ap.parse_args()

    for p in (LIB, DET, REC, DICT):
        if not os.path.exists(p):
            print(f'ERR missing: {p}', file=sys.stderr)
            return 2

    lib = ctypes.CDLL(LIB)
    lib.ocr_simple_create.restype = ctypes.c_void_p
    lib.ocr_simple_create.argtypes = [ctypes.c_char_p] * 3
    lib.ocr_simple_run.restype = ctypes.c_char_p
    lib.ocr_simple_run.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
    lib.ocr_simple_destroy.argtypes = [ctypes.c_void_p]

    h = lib.ocr_simple_create(DET.encode(), REC.encode(), DICT.encode())
    if not h:
        print('ERR create failed', file=sys.stderr)
        return 3
    try:
        out = lib.ocr_simple_run(h, args.image.encode())
        text = ''
        if out:
            try:
                boxes = json.loads(out.decode('utf-8', 'replace'))
                text = '\n'.join(_to_lines(boxes))
            except Exception:  # noqa: BLE001
                text = out.decode('utf-8', 'replace')
    finally:
        lib.ocr_simple_destroy(h)

    if args.out:
        with open(args.out, 'w', encoding='utf-8') as f:
            f.write(text)
    else:
        sys.stdout.write(text)
    return 0


if __name__ == '__main__':
    sys.exit(main())
