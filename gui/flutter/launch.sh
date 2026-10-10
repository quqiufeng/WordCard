#!/usr/bin/env bash
# launch.sh — 桌面图标点击入口：确保单实例运行 WordCard。
# 优先走用户级 systemd 服务（复用/重启同一实例）；服务不可用时回退直接运行。
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

if systemctl --user cat wordcard-app.service >/dev/null 2>&1; then
    systemctl --user restart wordcard-app
else
    exec "$HERE/run.sh"
fi
