"""电子书导入 — PDF / MOBI / MD → 提取词汇 → wordcard.db"""

import os, re, sys, time, json
from pathlib import Path

sys.path.insert(0, os.path.dirname(__file__) or '.')
import engine

# ── 英文停用词 ──────────────────────────────────────────────

_STOPWORDS = set("""
themselves himself herself itself ourselves yourself myself
old first four end side moment seemed always though another went good
came go going gone get got take took give gave make made know knew
said say says see saw look looked think thought want wanted well also
still yet ever much many little own thing things man men way ways upon
shall unto thee thou thy hath did does done being having having
""".split())
_STOPWORDS |= set("""
a an the and or but in on at to for of with by from as is are was were
be been being have has had do does did will would shall should may might
can could must need dare ought used about after against among between
through during before above below down up out off over under again
further then once here there where why how all each every both few more
most other some such no nor not only own same so than too very just
because until while i you he she it we they me him his her its our your
them their this that these those what which who whom am
when now one two three time back into never round came day any even said
work get got go going gone come came take took give gave make made know
knew see saw look looked think thought say says said want wanted could
would should who whose like well also just still yet ever every much many
little long own thing things man men way ways make made must upon shall
unto thee thou thy hath did does done being having having
""".split())

# 常用基础词（太简单，不作为学习目标）
_COMMON_WORDS = set("""
animal animals farm day days night time year years life world man men woman
women people thing things way home house work part place case week company
system program question government number point water room mother father
money story fact month right study book eye eyes job word words business
issue side kind head service friend power hour game line end member law
car city community name team minute idea kid body information back parent
face level office door health person art war history party result change
morning reason research girl guy moment air teacher force education foot
boy age policy process music market sense nation plan college interest
death experience effect use class control care field development role
effort rate heart drug show leader light voice wife police mind price
report decision son view relationship town road arm difference value
building action model season society tax director position player record
paper space ground form event official matter center couple site project
activity star table need court production eat food sense state area
picture practice piece land hand high small large great little long
good new first last next early young important public bad able
know think take come want look give use find tell ask work seem feel try
leave call need become mean keep let begin help talk turn start show hear
play run move live believe hold bring happen write provide sit stand lose
pay meet include continue set learn change lead understand watch follow
stop create speak read allow add spend grow open walk win offer remember
love consider appear buy wait serve die send expect build stay fall cut
reach kill remain suggest raise pass sell require report decide pull
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
    if lib:
        ctypes = __import__('ctypes')
        cdll = ctypes.CDLL(lib)
        cdll.pdf_open.argtypes = [ctypes.c_char_p]
        cdll.pdf_open.restype = ctypes.c_void_p
        cdll.pdf_extract_text.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_char_p), ctypes.POINTER(ctypes.c_size_t)]
        cdll.pdf_extract_text.restype = ctypes.c_int
        cdll.pdf_close.argtypes = [ctypes.c_void_p]
        cdll.pdf_close.restype = None
        h = cdll.pdf_open(path.encode('utf-8'))
        if h:
            try:
                text_p = ctypes.c_char_p()
                text_len = ctypes.c_size_t()
                cdll.pdf_extract_text(h, ctypes.byref(text_p), ctypes.byref(text_len))
                text = text_p.value.decode('utf-8', errors='replace') if text_p.value else ''
                if len(text.strip()) > 50:
                    return {'title': Path(path).stem, 'author': '', 'text': text}
            finally:
                cdll.pdf_close(h)

    # Fallback: OCR via /opt/Unlimited-OCR (Baidu SGLang)
    import requests, base64, tempfile, os as _os
    import fitz
    try:
        _sr = requests.get('http://127.0.0.1:10000/health', timeout=2)
        if _sr.status_code == 200:
            doc = fitz.open(path)
            mat = fitz.Matrix(300/72, 300/72)
            texts = []
            for i, page in enumerate(doc):
                png = tempfile.NamedTemporaryFile(suffix='.png', delete=False)
                page.get_pixmap(matrix=mat).save(png.name)
                with open(png.name, 'rb') as f:
                    b64 = base64.b64encode(f.read()).decode()
                _os.unlink(png.name)
                payload = {
                    'model': 'Unlimited-OCR',
                    'messages': [{'role': 'user', 'content': [
                        {'type': 'text', 'text': 'document parsing.'},
                        {'type': 'image_url', 'image_url': {'url': f'data:image/png;base64,{b64}'}}
                    ]}],
                    'temperature': 0,
                }
                r = requests.post('http://127.0.0.1:10000/v1/chat/completions',
                                  json=payload, timeout=300)
                text = r.json()['choices'][0]['message']['content']
                if text.strip():
                    texts.append(f'--- Page {i+1} ---\n{text}')
            doc.close()
            full = '\n\n'.join(texts)
            if full.strip():
                return {'title': Path(path).stem, 'author': '', 'text': full}
    except Exception:
        pass

    raise RuntimeError(f'Cannot extract text from PDF: {path}')

def extract_md(path):
    with open(path, 'r', encoding='utf-8') as f:
        text = f.read()
    return {'title': Path(path).stem, 'author': '', 'text': text}

def extract_epub(path):
    lib = _find_lib('libepubparse.so')
    if not lib:
        raise RuntimeError('libepubparse.so not built; run: cd importer/wrappers && make')
    ctypes = __import__('ctypes')
    cdll = ctypes.CDLL(lib)
    cdll.epub_open.argtypes = [ctypes.c_char_p]
    cdll.epub_open.restype = ctypes.c_void_p
    cdll.epub_extract_text.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_char_p), ctypes.POINTER(ctypes.c_size_t)]
    cdll.epub_extract_text.restype = ctypes.c_int
    cdll.epub_get_metadata.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_size_t, ctypes.c_char_p, ctypes.c_size_t]
    cdll.epub_get_metadata.restype = ctypes.c_int
    cdll.epub_close.argtypes = [ctypes.c_void_p]
    cdll.epub_close.restype = None

    h = cdll.epub_open(path.encode('utf-8'))
    if not h:
        raise RuntimeError(f'Cannot open EPUB: {path}')
    try:
        title = ctypes.create_string_buffer(256)
        author = ctypes.create_string_buffer(256)
        cdll.epub_get_metadata(h, title, 256, author, 256)
        text_p = ctypes.c_char_p()
        text_len = ctypes.c_size_t()
        cdll.epub_extract_text(h, ctypes.byref(text_p), ctypes.byref(text_len))
        text = text_p.value.decode('utf-8', errors='replace') if text_p.value else ''
        return {
            'title': title.value.decode('utf-8', errors='replace') if title.value else Path(path).stem,
            'author': author.value.decode('utf-8', errors='replace') if author.value else '',
            'text': text,
        }
    finally:
        cdll.epub_close(h)

def extract(path, save_text=None):
    """解析电子书。save_text 非空时把完整正文写入该文件。"""
    info = _extract(path)
    if save_text:
        os.makedirs(os.path.dirname(save_text) or '.', exist_ok=True)
        with open(save_text, 'w', encoding='utf-8') as f:
            f.write(f"TITLE: {info['title']}\nAUTHOR: {info['author']}\n\n{info['text']}")
    return info

def _extract(path):
    ext = Path(path).suffix.lower()
    if ext in ('.mobi', '.azw3', '.prc'):
        return extract_mobi(path)
    elif ext == '.epub':
        return extract_epub(path)
    elif ext == '.pdf':
        return extract_pdf(path)
    elif ext == '.md':
        return extract_md(path)
    elif ext == '.txt':
        return extract_md(path)
    else:
        raise ValueError(f'Unsupported format: {ext}')

# ── 提取词汇 ────────────────────────────────────────────────

# 版权页/元数据/URL 常见噪声词
_NOISE_WORDS = set("""
isbn cip www http https com cn org net html xml utf eisbn
bic cipdata xzxcn bfwy cip code isbn978 rights reserved
publishing press group limited corporation inc ltd llc
www bfwy com cn net http https email tel fax
""".split())

_ROMAN_RE = re.compile(r'^[IVXLCDM]{2,}$')

def _is_noise_token(w):
    """判断 token 是否为噪声（缩写/罗马数字/URL/编号）"""
    wl = w.lower()
    if wl in _NOISE_WORDS:
        return True
    # 全大写且长度>=2（缩写/编号，如 ISBN / XZXCN / VIII）
    if len(w) >= 2 and w.isupper():
        return True
    # 罗马数字
    if _ROMAN_RE.match(w):
        return True
    # 无元音且长度>3（多为编码，如 bfwy）
    if len(wl) > 3 and not any(c in wl for c in 'aeiouy'):
        return True
    # 连续相同字符（如 aaaa）
    if len(wl) >= 3 and len(set(wl)) == 1:
        return True
    return False

def _is_prose(sent):
    """粗判句子是否自然语言（过滤版权页/表格/目录等）"""
    if len(sent) > 400:
        return False
    alpha = sum(c.isalpha() or c.isspace() for c in sent)
    if len(sent) and alpha / len(sent) < 0.6:
        return False
    digits = sum(c.isdigit() for c in sent)
    if digits > len(sent) * 0.15:
        return False
    return True

def _clean_text(text):
    """Remove markdown syntax and normalize"""
    text = re.sub(r'#{1,6}\s*', '', text)
    text = re.sub(r'[*_~`]', '', text)
    text = re.sub(r'\[([^\]]+)\]\([^)]+\)', r'\1', text)
    text = re.sub(r'\|.*\|', '', text)
    text = re.sub(r'^[-=]{3,}$', '', text, flags=re.MULTILINE)
    return text

def extract_words(text, max_words=200, min_len=5, sort='difficulty',
                  target_zipf=3.8, mode=0, level=0, known_zipf=5.0, coverage_weight=0.5):
    """提取文本中的英文词汇，返回 [(word, context_sentence), ...]

    优先使用 C++ wordpick（基于通用词频 zipf 的学习价值评分）；
    不可用时回退到纯 Python 启发式。
    sort='difficulty'（默认）：按学习价值降序；
    sort='frequency'：按词频降序，选高频词。
    mode=1 用覆盖率模式；level=1..6 指定 CEFR (A1..C2)。
    """
    # ── C++ wordpick 路径 ──
    try:
        import wordpick as _wp
        if _wp.available() and sort != 'frequency':
            import html as _html
            picked = _wp.select(_html.unescape(text), max_words=max_words,
                                target_zipf=target_zipf, min_len=min_len,
                                mode=mode, level=level, known_zipf=known_zipf,
                                coverage_weight=coverage_weight)
            return [(w, ctx) for (w, ctx, _s, _z, _n, _lv) in picked]
    except Exception:
        pass

    import html as _html
    text = _clean_text(_html.unescape(text))
    sentences = re.split(r'(?<=[.!?])\s+', text)
    freq = {}
    ctx = {}
    lower_seen = set()    # 出现过小写形式的词
    for sent in sentences:
        sent = sent.strip()
        if not sent or not _is_prose(sent):
            continue
        # 去掉 URL 片段
        sent = re.sub(r'\b(?:https?://|www\.)\S+', '', sent)
        words = re.findall(r"[a-zA-Z]+(?:'[a-zA-Z]+)?", sent)
        for w in words:
            wl = w.lower()
            if len(wl) < min_len or len(wl) > 20:
                continue
            if wl in _STOPWORDS or _is_noise_token(w):
                continue
            if wl in _COMMON_WORDS:
                continue
            if w == wl:            # 该词曾以小写出现
                lower_seen.add(wl)
            freq[wl] = freq.get(wl, 0) + 1
            if wl not in ctx:
                c = re.sub(r'\s+', ' ', sent).strip()
                if len(c) > 200:
                    c = c[:200] + '...'
                ctx[wl] = c
    # 专有名词过滤：只以大写形式出现的词（人名/地名/品牌）
    ranked = [w for w in freq if w in lower_seen]
    if sort == 'frequency':
        # 词频降序（高频＝更常用）
        ranked.sort(key=lambda w: (-freq[w], w))
    else:
        # 难度降序：长词优先；同长度时低频优先（更生僻）
        ranked.sort(key=lambda w: (-len(w), freq[w], w))
    return [(wl, ctx[wl]) for wl in ranked[:max_words]]

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
