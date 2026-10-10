#!/usr/bin/env bash
# launch.sh — 桌面图标点击入口：确保单实例运行 WordCard。
# 直接在本会话中运行（继承 pcmanfm-qt 的 DISPLAY/XAUTHORITY 等），
# 避免 systemd 服务环境缺少 X/GPU 上下文导致 GL 创建失败。
# 诊断日志：/tmp/wordcard_launch.log
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
LOG=/tmp/wordcard_launch.log

{
    echo "=== $(date '+%F %T') ==="
    echo "DISPLAY=$DISPLAY XAUTHORITY=${XAUTHORITY:-} XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-}"
    if pgrep -f 'bundle/wordcard' >/dev/null 2>&1; then
        wmctrl -a WordCard 2>/dev/null || true
        echo "already running, bring to front"
        exit 0
    fi
    export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    export DISPLAY="${DISPLAY:-:0}"
    setsid "$HERE/run.sh" >/dev/null 2>&1 < /dev/null &
    echo "started run.sh pid $!"
} >> "$LOG" 2>&1
