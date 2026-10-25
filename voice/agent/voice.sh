#!/usr/bin/env bash
# voice.sh — 本地语音入口（say / listen / once / test）
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
cmd="${1:-}"; shift || true
case "$cmd" in
  say)    exec "$DIR/say.sh" "$@" ;;
  listen) exec "$DIR/listen.sh" "$@" ;;
  once)   exec "$DIR/listen.sh" --once --no-forward "$@" ;;
  test)   exec "$DIR/say.sh" "${*:-你好，语音模块自检正常。}" ;;
  *) echo "用法: voice.sh {say <文本>|listen|once|test}" >&2; exit 2 ;;
esac
