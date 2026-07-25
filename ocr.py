"""OCR — text extraction from images and scanned PDFs via Tesseract."""

import os, subprocess, tempfile
from PIL import Image

try:
    import pytesseract
    _has_tesseract = True
except ImportError:
    _has_tesseract = False

LANG = 'eng+chi_sim'

def available():
    if not _has_tesseract:
        return False
    try:
        pytesseract.get_tesseract_version()
        return True
    except Exception:
        return False

def image(image_path, lang=LANG):
    """Extract text from an image file."""
    if not available():
        raise RuntimeError('Tesseract not installed')
    img = Image.open(image_path)
    return pytesseract.image_to_string(img, lang=lang)

def pdf(pdf_path, lang=LANG, dpi=300):
    """Extract text from a scanned PDF via OCR.
    
    Requires: pip install pdf2image (and poppler-utils system package)
    Uses pdftoppm for PDF→image conversion, then Tesseract OCR.
    """
    if not available():
        raise RuntimeError('Tesseract not installed')

    # First try: pdftotext (extracts embedded text, fast)
    text = _pdftotext(pdf_path)
    if text and len(text.strip()) > 50:
        return text

    # Fallback: OCR with pdf2image
    return _ocr_pdf(pdf_path, lang, dpi)

def _pdftotext(pdf_path):
    """Extract embedded text from PDF using pdftotext."""
    try:
        r = subprocess.run(['pdftotext', pdf_path, '-'],
                          capture_output=True, text=True, timeout=30)
        if r.returncode == 0 and r.stdout.strip():
            return r.stdout
    except Exception:
        pass
    return ''

def _ocr_pdf(pdf_path, lang=LANG, dpi=300):
    """OCR a scanned PDF page by page."""
    try:
        from pdf2image import convert_from_path
    except ImportError:
        raise RuntimeError('Need pdf2image: pip install pdf2image')

    images = convert_from_path(pdf_path, dpi=dpi)
    result = []
    for i, img in enumerate(images):
        text = pytesseract.image_to_string(img, lang=lang)
        result.append(f'--- Page {i+1} ---\n{text}')
    return '\n\n'.join(result)
