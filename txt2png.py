import ctypes, os
from ctypes import c_char_p, c_int, c_double, c_uint32, c_size_t, c_void_p, POINTER, byref, Structure

_lib = None

def _load():
    global _lib
    if _lib is not None: return _lib
    for d in ('src/libtxt2png.so',):
        p = os.path.join(os.path.dirname(__file__), d)
        if os.path.exists(p):
            _lib = ctypes.CDLL(p)
            return _lib
    raise RuntimeError('libtxt2png.so not found')

class Style(Structure):
    _fields_ = [
        ('font_size', c_double), ('width', c_int), ('height', c_int),
        ('margin', c_int), ('leading', c_double), ('tolerance', c_double),
        ('fg_color', c_uint32), ('bg_color', c_uint32),
        ('nohyphen', c_int), ('hyphen_dict_path', c_char_p),
    ]

def make_style(font_size=24, width=600, height=0, margin=20, leading=1.4,
               tolerance=200, fg_color=0x000000, bg_color=0xFFFFFF, nohyphen=False):
    return Style(float(font_size), width, height, margin, float(leading),
                 float(tolerance), fg_color, bg_color, int(nohyphen), None)

def render_file(text, font_path, style, output_path):
    lib = _load()
    lib.txt2png_bridge_render_file.argtypes = [c_char_p, c_char_p, POINTER(Style), c_char_p]
    lib.txt2png_bridge_render_file.restype = c_int
    r = lib.txt2png_bridge_render_file(text.encode('utf-8'), font_path.encode('utf-8'),
                                        byref(style), output_path.encode('utf-8'))
    if r != 0: raise RuntimeError(f'render_file failed: {r}')

def render_mem(text, font_path, style):
    lib = _load()
    lib.txt2png_bridge_render_mem.argtypes = [c_char_p, c_char_p, POINTER(Style), POINTER(c_size_t)]
    lib.txt2png_bridge_render_mem.restype = POINTER(ctypes.c_ubyte)
    lib.txt2png_bridge_free.argtypes = [POINTER(ctypes.c_ubyte)]
    lib.txt2png_bridge_free.restype = None
    out_size = c_size_t(0)
    buf = lib.txt2png_bridge_render_mem(text.encode('utf-8'), font_path.encode('utf-8'),
                                         byref(style), byref(out_size))
    if not buf: raise RuntimeError('render_mem failed')
    data = bytes(ctypes.cast(buf, POINTER(ctypes.c_ubyte * out_size.value)).contents)
    lib.txt2png_bridge_free(buf)
    return data

class Canvas:
    def __init__(self, width, height, bg_color=0xF5F5F5):
        lib = _load()
        for name, argtypes, restype in [
            ('txt2png_canvas_create', [c_int, c_int, c_uint32], c_void_p),
            ('txt2png_canvas_destroy', [c_void_p], None),
            ('txt2png_canvas_draw_text', [c_void_p, c_char_p, c_double, c_char_p, c_int, c_int, c_uint32], c_int),
            ('txt2png_canvas_measure', [c_void_p, c_char_p, c_double, c_char_p], c_int),
            ('txt2png_canvas_save', [c_void_p, c_char_p], c_int),
            ('txt2png_canvas_height', [c_void_p], c_int),
            ('txt2png_canvas_ascent', [c_void_p, c_char_p, c_double], c_int),
        ]:
            f = getattr(lib, name)
            f.argtypes = argtypes
            f.restype = restype
        self._lib = lib
        self._handle = lib.txt2png_canvas_create(width, height, bg_color)
        if not self._handle:
            raise RuntimeError('canvas_create failed')

    def __del__(self):
        if hasattr(self, '_lib') and getattr(self, '_handle', None):
            self._lib.txt2png_canvas_destroy(self._handle)

    def draw_text(self, font_path, font_size, text, x, y, color=0x000000):
        return self._lib.txt2png_canvas_draw_text(
            self._handle, font_path.encode('utf-8'), font_size,
            text.encode('utf-8'), x, y, color)

    def measure(self, font_path, font_size, text):
        return self._lib.txt2png_canvas_measure(
            self._handle, font_path.encode('utf-8'), font_size,
            text.encode('utf-8'))

    def ascent(self, font_path, font_size):
        return self._lib.txt2png_canvas_ascent(
            self._handle, font_path.encode('utf-8'), font_size)

    def save(self, path):
        r = self._lib.txt2png_canvas_save(self._handle, path.encode('utf-8'))
        if r != 0: raise RuntimeError(f'canvas_save failed: {r}')

    @property
    def height(self):
        return self._lib.txt2png_canvas_height(self._handle)
