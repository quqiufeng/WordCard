#!/usr/bin/env bash
# gen_bg.sh — 生成词汇卡背景图（参考 /opt/static_comfyui/cpp/sd/backup.sh）
#
# 与 my-agent 的 image.sh 不同：专门出「背景图」，覆盖其默认人像档，
# 强化 无人/无字 负面提示，默认小红书 3:4，直接落盘不发送微信。
#
# 用法:
#   gen_bg.sh [小红书|小红薯|朋友圈|横版] ["提示词"] [--out 路径] [--force]
#   gen_bg.sh --style paper|guochao|grid|ink|plain [尺寸] [--out 路径]
#
# 示例:
#   ./gen_bg.sh                                  # 默认 guochao 背景，小红书尺寸
#   ./gen_bg.sh 朋友圈 "淡雅水墨留白" --out ~/bg.png
#   ./gen_bg.sh --style paper --out output/bg.png
set -uo pipefail

BACKUP="${IMAGE_BACKUP:-/opt/static_comfyui/cpp/sd/backup.sh}"
[ -x "$BACKUP" ] || { echo "backup.sh 不存在: $BACKUP" >&2; exit 1; }

STYLE="guochao"; PRESET="xhs"; PROMPT=""; OUT=""; FORCE=0
W=""; H=""

# 背景提示词预设（均强调 无人/无字/留白）
declare -A STYLE_PROMPT=(
  [paper]="soft cream paper texture background, subtle fiber grain, warm beige, clean minimal, large empty space, flat, no people, no text"
  [guochao]="flat decorative guochao background, pale cream and sage green, symmetric traditional Chinese ornamental border frame, subtle cloud and bamboo line motifs, empty blank center, minimal vector illustration, no people, no text"
  [grid]="minimal fine grid line paper background, pale sage green, clean geometric, large blank center, flat design, no people, no text"
  [ink]="elegant Chinese ink wash light background, very pale, subtle brush strokes at edges, wide empty center, minimalist, no people, no text"
  [plain]="solid soft light green background, sage green, clean seamless plain, no props, no people, no text"
)
NEGATIVE="person, people, human, face, portrait, woman, man, girl, boy, body, skin, hands, \
text, letters, words, chinese characters, watermark, signature, logo, \
photo, photorealistic, realistic, 3d render, blurry, low quality, jpeg artifacts, noise, border artifacts, frame distortion"

args=("$@"); i=0
while [ $i -lt ${#args[@]} ]; do
    a="${args[$i]}"
    case "$a" in
        --style) STYLE="${args[$((i+1))]:-guochao}"; i=$((i+2)); continue ;;
        --out)   OUT="${args[$((i+1))]:-}"; i=$((i+2)); continue ;;
        --force) FORCE=1; i=$((i+1)); continue ;;
        小红书|小红薯|xhs|xiaohongshu|竖版) PRESET="xhs"; i=$((i+1)); continue ;;
        朋友圈|pyq|moments|方图)            PRESET="pyq"; i=$((i+1)); continue ;;
        横版|横图|默认)                     PRESET="wide"; i=$((i+1)); continue ;;
    esac
    if [[ "$a" =~ ^[0-9]+$ ]]; then
        if [ -z "$W" ]; then W="$a"; else H="$a"; fi
    elif [ -z "$PROMPT" ]; then PROMPT="$a"; fi
    i=$((i+1))
done

# 尺寸
case "$PRESET" in
    xhs)  W=1920; H=2560; SNAME="小红书" ;;
    pyq)  W=2048; H=2048; SNAME="朋友圈" ;;
    wide) W="${W:-2560}"; H="${H:-1440}"; SNAME="横版" ;;
esac

# 提示词：用户给定优先，否则用预设
[ -z "$PROMPT" ] && PROMPT="${STYLE_PROMPT[$STYLE]:-${STYLE_PROMPT[guochao]}}"
[ -z "$OUT" ] && OUT="$HOME/bg_$(date +%Y%m%d_%H%M%S).png"

# GPU 显存检查
if command -v nvidia-smi >/dev/null 2>&1; then
    FREE="$(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -d ' ')"
    if [ -n "${FREE:-}" ] && [ "$FREE" -lt 8000 ] && [ "$FORCE" != "1" ]; then
        echo "GPU 显存不足（空闲 ${FREE} MiB），加 --force 强制或稍后再试。" >&2
        exit 3
    fi
fi

LOG="/tmp/gen_bg_$(date +%Y%m%d_%H%M%S).log"
echo "生成背景（$SNAME ${W}x${H}, style=$STYLE）约 3~6 分钟..."
NO_QUALITY_PREFIX=1 SKIP_QUALITY_PREFIX=1 \
  CFG_SCALE="${CFG_SCALE:-4.0}" STEPS="${STEPS:-25}" HIRES_STEPS="${HIRES_STEPS:-35}" \
  NEGATIVE_PROMPT="$NEGATIVE" "$BACKUP" "$PROMPT" "$OUT.tmp.png" "$W" "$H" >"$LOG" 2>&1 || true

# 解析 backup.sh 输出的实际文件路径
IMG=$(sed 's/\x1b\[[0-9;]*m//g' "$LOG" | grep -oE 'File:[[:space:]]+/[^[:space:]]+\.png' | tail -1 | sed -E 's/^File:[[:space:]]+//')
if [ -z "$IMG" ] || [ ! -f "$IMG" ]; then
    IMG=$(sed 's/\x1b\[[0-9;]*m//g' "$LOG" | grep -oE '/[^[:space:]]+\.png' | tac | while read -r p; do [ -f "$p" ] && { echo "$p"; break; }; done)
fi
if [ -z "$IMG" ] || [ ! -f "$IMG" ]; then
    echo "出图失败，日志尾部：" >&2; tail -n 20 "$LOG" >&2; exit 1
fi

mv -f "$IMG" "$OUT"
echo "完成: $OUT  ($(du -h "$OUT" | cut -f1))"
echo "$OUT"
