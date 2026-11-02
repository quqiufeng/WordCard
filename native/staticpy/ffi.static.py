# StaticPy FFI 统一定义（所有 native POC 共用）
# 编译时由 build.sh 自动 prepend；业务脚本里不再重复写 extern fn。

# wc_static / wc_native
extern fn wc_static_version() -> str from "wc_static"
extern fn wc_static_summary(db_path: str) -> str from "wc_static"
extern fn wc_static_dump(db_path: str, out_path: str) -> int from "wc_static"
extern fn wc_static_add_item(db_path: str, q: str, a: str, tags: str) -> int from "wc_static"
extern fn wc_static_review(db_path: str, user_id: int, item_id: int, quality: int) -> int from "wc_static"

# voice
extern fn voice_static_tts(text: str, out_path: str, sid: str) -> int from "voice_static"
extern fn voice_static_asr(wav: str, lang: str) -> str from "voice_static"
extern fn voice_static_play(wav: str) -> int from "voice_static"
extern fn voice_static_convert(input_path: str, output_path: str, rate: int) -> int from "voice_static"
extern fn voice_static_record(out: str, seconds: int, rate: int, device: str) -> int from "voice_static"
extern fn voice_static_wav_info(wav: str) -> str from "voice_static"

# text / wordpick / paragraph render
extern fn wc_wordpick_tsv(freq: str, text: str, out: str, max_words: int) -> int from "wc_text_static"
extern fn wc_render_png(text: str, font: str, out: str) -> int from "wc_text_static"

# cli
extern fn wc_cli_version() -> str from "wc_cli"
extern fn wc_cli_stats(db_path: str) -> str from "wc_cli"
extern fn wc_cli_dump(db_path: str, out_path: str) -> int from "wc_cli"
extern fn wc_cli_add(db_path: str, q: str, a: str, tags: str) -> int from "wc_cli"
extern fn wc_cli_review(db_path: str, user_id: int, item_id: int, quality: int) -> int from "wc_cli"

# card canvas
extern fn wc_canvas_create(w: int, h: int, bg: int) -> ptr from "wc_card"
extern fn wc_canvas_destroy(c: ptr) -> int from "wc_card"
extern fn wc_canvas_text(c: ptr, font: str, fs: int, text: str, x: int, y: int, color: int) -> int from "wc_card"
extern fn wc_canvas_measure(c: ptr, font: str, fs: int, text: str) -> int from "wc_card"
extern fn wc_canvas_line(c: ptr, x1: int, y1: int, x2: int, y2: int, color: int, width: int) -> int from "wc_card"
extern fn wc_canvas_rect(c: ptr, x: int, y: int, w: int, h: int, color: int, filled: int) -> int from "wc_card"
extern fn wc_canvas_save(c: ptr, path: str) -> int from "wc_card"
