#!/usr/bin/env bash
# launch.sh — 桌面图标点击入口：确保单实例运行 WordCard。
# 优先走用户级 systemd 服务（复用/重启同一实例）；服务不可用或失败时回退直接运行。
# 诊断日志：/tmp/wordcard_launch.log
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
LOG=/tmp/wordcard_launch.log

{
    echo "=== $(date '+%F %T') ==="
    echo "DISPLAY=$DISPLAY XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-} DBUS=${DBUS_SESSION_BUS_ADDRESS:-}"
    if systemctl --user cat wordcard-app.service >/dev/null 2>&1; then
        if systemctl --user restart wordcard-app; then
            echo "restarted wordcard-app.service"
            exit 0
        fi
        echo "systemctl restart failed, falling back to run.sh"
    else
        echo "no user unit, falling back to run.sh"
    fi
    setsid "$HERE/run.sh" >/dev/null 2>&1 < /dev/null &
    echo "started run.sh (pid $!)"
} >> "$LOG" 2>&1
