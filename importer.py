"""电子书导入 — PDF / MOBI / MD → 提取词汇 → wordcard.db"""

import os, re, sys, time, json
from pathlib import Path

sys.path.insert(0, os.path.dirname(__file__) or '.')
import engine

# ── 英文停用词 ──────────────────────────────────────────────

_STOPWORDS = set("""
a an the and or but in on at to for of with by from as is are was were
be been being have has had do does did will would shall should may might
can could must need dare ought used about after against among between
through during before above below down up out off over under again
further then once here there where why how all each every both few more
most other some such no nor not only own same so than too very just
because until while i you he she it we they me him his her its our your
them their this that these those what which who whom am
""".split())

# ── 导入路径 ────────────────────────────────────────────────

def _find_lib(name):
    d = os.path.dirname(os.path.abspath(__file__))
    for p in [
        os.path.join(d, 'importer', 'libs', name),
        os.path.join(d, 'importer', 'wrappers', '..', 'libs', name),
    ]:
        if os.path.exists(p):
            return p
    return None

# ── 文本提取 ────────────────────────────────────────────────

def extract_mobi(path):
    lib = _find_lib('libmobiparse.so')
    if not lib:
        raise RuntimeError('libmobiparse.so not built; run: cd importer/wrappers && make')
    ctypes = __import__('ctypes')
    cdll = ctypes.CDLL(lib)
    cdll.mobi_open.argtypes = [ctypes.c_char_p]
    cdll.mobi_open.restype = ctypes.c_void_p
    cdll.mobi_extract_text.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_char_p), ctypes.POINTER(ctypes.c_size_t)]
    cdll.mobi_extract_text.restype = ctypes.c_int
    cdll.mobi_get_metadata.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_size_t, ctypes.c_char_p, ctypes.c_size_t]
    cdll.mobi_get_metadata.restype = ctypes.c_int
    cdll.mobi_close.argtypes = [ctypes.c_void_p]
    cdll.mobi_close.restype = None

    h = cdll.mobi_open(path.encode('utf-8'))
    if not h:
        raise RuntimeError(f'Cannot open MOBI: {path}')
    try:
        title = ctypes.create_string_buffer(256)
        author = ctypes.create_string_buffer(256)
        cdll.mobi_get_metadata(h, title, 256, author, 256)
        text_p = ctypes.c_char_p()
        text_len = ctypes.c_size_t()
        cdll.mobi_extract_text(h, ctypes.byref(text_p), ctypes.byref(text_len))
        text = text_p.value.decode('utf-8', errors='replace') if text_p.value else ''
        return {
            'title': title.value.decode('utf-8', errors='replace') if title.value else Path(path).stem,
            'author': author.value.decode('utf-8', errors='replace') if author.value else '',
            'text': text,
        }
    finally:
        cdll.mobi_close(h)

def extract_pdf(path):
    lib = _find_lib('libpdfparse.so')
    if not lib:
        raise RuntimeError('libpdfparse.so not built; run: cd importer/wrappers && make')
    ctypes = __import__('ctypes')
    cdll = ctypes.CDLL(lib)
    cdll.pdf_open.argtypes = [ctypes.c_char_p]
    cdll.pdf_open.restype = ctypes.c_void_p
    cdll.pdf_extract_text.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_char_p), ctypes.POINTER(ctypes.c_size_t)]
    cdll.pdf_extract_text.restype = ctypes.c_int
    cdll.pdf_close.argtypes = [ctypes.c_void_p]
    cdll.pdf_close.restype = None

    h = cdll.pdf_open(path.encode('utf-8'))
    if not h:
        raise RuntimeError(f'Cannot open PDF: {path}')
    try:
        text_p = ctypes.c_char_p()
        text_len = ctypes.c_size_t()
        cdll.pdf_extract_text(h, ctypes.byref(text_p), ctypes.byref(text_len))
        text = text_p.value.decode('utf-8', errors='replace') if text_p.value else ''
        return {'title': Path(path).stem, 'author': '', 'text': text}
    finally:
        cdll.pdf_close(h)

def extract_md(path):
    with open(path, 'r', encoding='utf-8') as f:
        text = f.read()
    return {'title': Path(path).stem, 'author': '', 'text': text}

def extract(path):
    ext = Path(path).suffix.lower()
    if ext in ('.mobi', '.azw3', '.prc'):
        return extract_mobi(path)
    elif ext == '.pdf':
        return extract_pdf(path)
    elif ext == '.md':
        return extract_md(path)
    elif ext == '.txt':
        return extract_md(path)
    else:
        raise ValueError(f'Unsupported format: {ext}')

# ── 提取词汇 ────────────────────────────────────────────────

def _clean_text(text):
    """Remove markdown syntax and normalize"""
    text = re.sub(r'#{1,6}\s*', '', text)
    text = re.sub(r'[*_~`]', '', text)
    text = re.sub(r'\[([^\]]+)\]\([^)]+\)', r'\1', text)
    text = re.sub(r'\|.*\|', '', text)
    text = re.sub(r'^[-=]{3,}$', '', text, flags=re.MULTILINE)
    return text

def extract_words(text, max_words=200):
    """提取文本中的英文词汇，返回 [(word, context_sentence), ...]"""
    text = _clean_text(text)
    sentences = re.split(r'(?<=[.!?])\s+', text)
    word_set = {}
    for sent in sentences:
        sent = sent.strip()
        if not sent:
            continue
        words = re.findall(r"[a-zA-Z]+(?:'[a-zA-Z]+)?", sent)
        for w in words:
            wl = w.lower()
            if len(wl) < 3 or len(wl) > 20:
                continue
            if wl in _STOPWORDS:
                continue
            if wl not in word_set and len(word_set) < max_words:
                context = sent.strip()
                if len(context) > 200:
                    context = context[:200] + '...'
                word_set[wl] = (w, context)
    result = list(word_set.values())
    result.sort(key=lambda x: len(x[0]), reverse=True)
    return result

# ── 导入流程 ────────────────────────────────────────────────

def import_book(book_path, db_path='data/wordcard.db', user_id=1, max_words=200):
    print(f'Importing: {book_path}')
    info = extract(book_path)
    title = info['title']
    text = info['text']
    print(f'  Title: {title}')
    print(f'  Text length: {len(text)} chars')

    words = extract_words(text, max_words)
    print(f'  Found {len(words)} unique words')

    db = engine.WordCardDB.open(db_path)
    try:
        src_id = 0
        added = 0
        for word, context in words:
            item_id = db.add_item(
                question=word,
                answer='',
                explanation=context,
                source_id=src_id,
                tags=f'book:{title}',
            )
            if item_id:
                added += 1

        db.save()
        print(f'  Added {added} items to database')
        return added
    finally:
        db.close()
