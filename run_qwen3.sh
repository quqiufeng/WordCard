#!/bin/bash
set -euo pipefail
#
# =============================================================
# Qwen3-8B (llama.cpp) API 启动脚本 - 本地翻译服务
# =============================================================
#
# 【模型信息】
# 模型: Qwen3-8B-Q5_K_M.gguf
# 框架: llama.cpp
# 显存占用: ~8.0GB (RTX 3080 10GB)
# 上下文: 128K (131072 tokens)
# KV量化: q4_0 (--cache-type-k q4_0 --cache-type-v q4_0)
#
# 【最新实测性能】2026-04-20 RTX 3080 10GB (Q5_K_S, BATCH=1024, CTX=128K)
#   快速排序: 66.2, 线程安全: 82.0, 二分查找: 81.0, 数据库索引: 66.3
#   Python性能优化: 83.3, 归并排序: 64.6, HTTP/HTTPS: 80.0, LRU缓存: 82.5
#   堆排序: 66.8, Dijkstra算法: 82.7, 一致性哈希: 66.7, 令牌桶: 82.5
#   阻塞队列: 82.4, 红黑树: 66.7, B+树: 82.6, A*算法: 82.7
#   KMP算法: 66.8, 布隆过滤器: 82.8, 跳表: 66.0, 并查集: 81.7
#   线段树: 82.2, 字典树: 65.2
#   平均约: 75.0 tok/s (test_api.py, max_tokens=1024, 显存: ~8136MiB)
#
# 【历史对照数据】
#   [2026-04-20 Q5_K_S 优化后] 平均约: 75.0 tok/s (当前基准)
#   [2026-04-16 Q5_K_S, BATCH=1024, CTX=128K] 平均约: 72.6 tok/s
#   [2026-04-16 Q4_K_M, BATCH=1024, CTX=128K] 平均约: 77.4 tok/s
#   [编译优化选项] GGML_CUDA_FA=ON, GGML_CUDA_GRAPHS=ON, GGML_CUDA_FORCE_MMQ=ON
#
# 【优化策略】(参考 4090D 脚本优化)
# 1. 上下文固定 128K (强制要求)
# 2. batch size 从 512 提升到 1024 (单人使用无需 2048，避免 128K 下显存吃紧)
# 3. ubatch size 同步提升到 1024
# 4. 使用 q4_0 KV cache 控制显存 (10GB 显存必须保留)
# 5. GPU 层数 33 (全部加载)
# 6. 启用 Flash Attention
# 7. 增加 --prio 2 (高优先级)
# 8. 增加 --no-warmup (跳过启动 warmup，大幅缩短启动时间)
# 9. 增加 --parallel 1 --slots 1 (减少 slot 开销)
# 10. 温度从 0.6 降到 0.4 (与 4090D 保持一致)
# 11. 增加 --cpu-strict 1 --prio-batch 2 --poll 0 (CPU 亲和性优化)
# 12. 增加 --no-host --direct-io (GPU 直接访问优化)
#
# 【启动方式】
#   cd /home/dministrator/WordCard
#   setsid ./run_qwen3.sh > /tmp/qwen3_8b.log 2>&1 &
#   echo $!  # 记录PID
#
# 【查看日志】
#   tail -f /tmp/qwen3_8b.log
#
# 【停止服务】
#   pkill -f llama-server
#
# 【测试API】
#   curl http://localhost:11434/v1/models
#   curl -s http://localhost:11434/v1/chat/completions \
#     -H "Content-Type: application/json" \
#     -d '{"model": "Qwen3-8B-Q5_K_M.gguf", "messages": [{"role": "user", "content": "你好"}], "max_tokens": 50}'
#
# =============================================================

# 快速环境检查
if ! command -v nvidia-smi &> /dev/null; then
    echo "警告: nvidia-smi 未找到, 请确认 CUDA 驱动已安装"
fi
if [[ ! -x "$HOME/llama.cpp/build/bin/llama-server" ]]; then
    echo "错误: $HOME/llama.cpp/build/bin/llama-server 不存在或不可执行"
    exit 1
fi

export LD_LIBRARY_PATH=/usr/lib/wsl/lib:${LD_LIBRARY_PATH:-}

# 3080 10GB 显存优化参数
MODEL_DIR="/opt/image/Qwen3-8B-Q5_K_M.gguf"
LLAMA_SERVER="$HOME/llama.cpp/build/bin/llama-server"

NGL=33              # GPU层数 (全部加载)
CTX=131072          # 上下文 128K (强制要求)
BATCH=1024          # batch size (128K 下 1024 最佳，512 后半段性能暴跌)
UBATCH=1024         # micro batch size
THREADS=8           # CPU线程数 (3080 为 8C16T，8 线程较稳)

PORT=11434

echo "=============================="
echo "启动 Qwen3-8B Q5_K_M (llama.cpp) API 服务"
echo "地址: http://0.0.0.0:$PORT"
echo "模型: Qwen3-8B-Q5_K_M.gguf"
echo "上下文: $CTX"
echo "GPU层数: $NGL"
echo "Batch Size: $BATCH"
echo "uBatch Size: $UBATCH"
echo "Threads: $THREADS"
echo "目标: 75+ tok/s"
echo "=============================="
echo ""

$LLAMA_SERVER \
  -m "$MODEL_DIR" \
  --host 0.0.0.0 \
  --port $PORT \
  -ngl $NGL \
  -c $CTX \
  --batch-size $BATCH \
  --ubatch-size $UBATCH \
  --flash-attn on \
  --threads $THREADS \
  --threads-batch $THREADS \
  --prio 2 \
  --prio-batch 2 \
  --cpu-strict 1 \
  --poll 0 \
  --no-host \
  --direct-io \
  --no-mmap \
  --mlock \
  --no-warmup \
  -np 1 \
  --temp 0.4 \
  --top-p 0.95 \
  --top-k 20 \
  --min-p 0.00 \
  --cache-type-k q4_0 \
  --cache-type-v q4_0 \
  --kv-offload \
  --metrics

# 注意: 使用模型内置的chat template，不指定自定义模板
