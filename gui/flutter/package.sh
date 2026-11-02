#!/usr/bin/env bash
# package.sh — 构建并打包 WordCard Linux x64 运行目录
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
NAME="wordcard-linux-x64"
DIST="$ROOT/dist"
STAGE="$DIST/$NAME"
ARCHIVE="$DIST/$NAME.tar.gz"

"$HERE/build.sh"

rm -rf "$STAGE" "$ARCHIVE"
mkdir -p "$STAGE" "$STAGE/src" "$STAGE/data" "$STAGE/native/staticpy" \
    "$STAGE/voice" "$STAGE/importer" "$STAGE/models"

cp -a "$HERE/build/linux/x64/release/bundle" "$STAGE/bundle"
cp -a "$ROOT/src"/*.so "$STAGE/src/"
cp -a "$ROOT/libs" "$STAGE/libs"
cp -a "$ROOT/voice/libs" "$STAGE/voice/libs"
cp -a "$ROOT/importer/libs" "$STAGE/importer/libs"
cp -a "$ROOT/models/ocr" "$STAGE/models/ocr"
cp -a "$ROOT/res" "$STAGE/res"
cp -a "$ROOT/data/wordlists" "$STAGE/data/wordlists"

for f in "$ROOT"/*.ttf "$ROOT"/*.pkl; do
    [ -f "$f" ] && cp -a "$f" "$STAGE/"
done

for d in define translate ocr voice ebook_json card_txt text card_cn; do
    mkdir -p "$STAGE/native/staticpy/$d"
    cp -a "$ROOT/native/staticpy/$d"/wc_* "$STAGE/native/staticpy/$d/" 2>/dev/null || true
    cp -a "$ROOT/native/staticpy/$d"/lib*.so "$STAGE/native/staticpy/$d/" 2>/dev/null || true
done

cat > "$STAGE/run-wordcard.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"
export WORDCARD_ROOT="$HERE"
export WORDCARD_FONT="$HERE/LXGWWenKai-Regular.ttf"
export LD_LIBRARY_PATH="$HERE/src:$HERE/libs:$HERE/voice/libs:$HERE/importer/libs:${LD_LIBRARY_PATH:-}"
exec "$HERE/bundle/wordcard" "$@"
SH
chmod +x "$STAGE/run-wordcard.sh"

cat > "$STAGE/README.txt" <<'TXT'
WordCard Linux x64

启动:
  ./run-wordcard.sh

依赖:
  - 系统 GTK/ALSA/OpenCV
  - OCR 需要 onnxruntime 1.26（默认 /data/venv/onnxruntime-linux-x64-gpu-1.26.0/lib，可用 WC_ORT_LIB 覆盖）
  - 本地翻译模型默认 /data/models/Hunyuan-MT-7B-Q4_K_M.gguf，可用 WC_LLM_MODEL 覆盖
TXT

tar -C "$DIST" -czf "$ARCHIVE" "$NAME"
sha256sum "$ARCHIVE" > "$ARCHIVE.sha256"
echo "打包完成: $ARCHIVE"
du -h "$ARCHIVE" "$ARCHIVE.sha256"
