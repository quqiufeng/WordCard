#!/usr/bin/env bash
# llama_terminal.sh — 在终端窗口中前台运行 llama-server（可由用户手动停止）
#
# 用法（由 translate.py 自动调用）:
#   llama_terminal.sh <watch_pid>
#
# 行为：
#   · 输出的日志直接显示在终端窗口；
#   · Ctrl+C / 关闭窗口 → 停止 llama-server；
#   · <watch_pid>（WordCard 进程）退出 → 自动停止 llama-server；
#   · 把 shell PID 写入 $WC_LLAMA_PIDFILE，供 tools/llama_ctl.py stop 使用。
set -u

watch_pid="${1:-}"
bin="${LLAMA_SERVER:-/opt/llama.cpp/build/bin/llama-server}"
model="${WC_LLM_MODEL:-/data/models/Hunyuan-MT-7B-Q4_K_M.gguf}"
host="${WC_LLM_HOST:-127.0.0.1}"
port="${WC_LLM_PORT:-8081}"
ngl="${WC_LLM_GPU_LAYERS:-99}"
ctx="${WC_LLM_CTX:-4096}"
pidfile="${WC_LLAMA_PIDFILE:-/tmp/wordcard_llama.pid}"

printf '\033]0;llama-server · 翻译模型\007'
echo "── llama-server · 翻译模型 ─────────────────────────────"
echo "model : $model"
echo "url   : http://$host:$port"
echo "stop  : Ctrl+C 或关闭此窗口；WordCard 退出时也会自动停止"
echo "────────────────────────────────────────────────────────"
echo

echo "$$" > "$pidfile"
lpid=""
trap 'echo; echo "[WordCard] 正在停止 llama-server ..."; [ -n "$lpid" ] && kill "$lpid" 2>/dev/null; [ -n "$lpid" ] && wait "$lpid" 2>/dev/null; rm -f "$pidfile"; exit 0' INT TERM HUP

"$bin" -m "$model" -ngl "$ngl" -c "$ctx" --host "$host" --port "$port" &
lpid=$!

stopped_by_app=0
while kill -0 "$lpid" 2>/dev/null; do
    if [ -n "$watch_pid" ] && [ "$watch_pid" -gt 1 ] 2>/dev/null; then
        if ! kill -0 "$watch_pid" 2>/dev/null; then
            echo
            echo "[WordCard] 应用已退出，正在停止 llama-server ..."
            stopped_by_app=1
            kill "$lpid" 2>/dev/null
            break
        fi
    fi
    sleep 1
done

wait "$lpid" 2>/dev/null
rc=$?
rm -f "$pidfile"
echo
echo "[llama-server exited: $rc]"

# 异常退出且 WordCard 还在运行时，保留窗口方便看报错
if [ "$rc" -ne 0 ] && [ "$stopped_by_app" -eq 0 ] \
    && [ -n "$watch_pid" ] && kill -0 "$watch_pid" 2>/dev/null; then
    read -r -p "按 Enter 关闭窗口 ..." _ || true
fi
