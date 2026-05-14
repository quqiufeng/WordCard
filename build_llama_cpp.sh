#!/bin/bash

# llama.cpp CUDA 编译脚本 (RTX 3080 优化版)
# 支持自动检测 GPU 架构
#
# 【编译优化选项】
#   -DGGML_CUDA_FA=ON           编译时启用 Flash Attention 内核优化
#   -DGGML_CUDA_GRAPHS=ON       启用 CUDA Graphs 加速小 batch 推理 (新版默认 OFF，需显式开启)
#   -DGGML_CUDA_FORCE_MMQ=ON    强制使用 mmq kernels 替代 cuBLAS，消费级显卡小 batch 更快
#   -DGGML_LTO=ON               启用链接时优化，编译更慢但运行可能稍快
#   -DGGML_NATIVE=OFF           禁用 CPU native 优化，避免纯 GPU 推理时干扰
#   -DLLAMA_BUILD_SERVER=ON     编译 API 服务 (llama-server)
#   -DLLAMA_BUILD_EXAMPLES=ON   编译示例程序 (含 llama-llava-cli 多模态工具)
#

echo "=========================================="
echo "llama.cpp CUDA 编译脚本"
echo "=========================================="

# 检查 CUDA
if ! command -v nvcc &> /dev/null; then
    echo "错误: 未找到 nvcc，请先安装 CUDA Toolkit"
    exit 1
fi

echo "检测到 CUDA:"
nvcc --version | grep "release"

# 设置 CUDA 环境变量（兼容 WSL2）
export CUDA_HOME=/usr/local/cuda-12.0
export PATH=$CUDA_HOME/bin:$PATH
export LD_LIBRARY_PATH=$CUDA_HOME/lib64:/usr/lib/wsl/lib:$LD_LIBRARY_PATH

# 克隆或更新 llama.cpp
if [ ! -d "$HOME/llama.cpp" ]; then
    echo ""
    echo "=== 克隆 llama.cpp ==="
    git clone --depth 1 https://github.com/ggerganov/llama.cpp.git $HOME/llama.cpp
fi

cd $HOME/llama.cpp

# 清理并配置
echo ""
echo "=== 配置 CMake ==="
mkdir -p build && cd build
rm -rf *

# 检测 GPU 架构
GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)
GPU_CC=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader | head -1 | tr -d '.')

echo "GPU: $GPU_NAME"
echo "Compute Capability: $GPU_CC"

# 根据 GPU 设置架构
case $GPU_CC in
    86) CUDA_ARCH=86 ;;   # RTX 3080/3090, RTX 30xx
    89) CUDA_ARCH=89 ;;   # RTX 4090/4090D, RTX 40xx
    75) CUDA_ARCH=75 ;;   # RTX 20xx
    80) CUDA_ARCH=80 ;;   # A100
    90) CUDA_ARCH=90 ;;   # H100
    12) CUDA_ARCH=120 ;;  # GB200, B100/B200
    *) CUDA_ARCH=86 ;;    # 默认 RTX 30xx
esac

echo "使用 CUDA_ARCH: $CUDA_ARCH"

cmake .. \
  -DGGML_CUDA=ON \
  -DCMAKE_CUDA_ARCHITECTURES=$CUDA_ARCH \
  -DGGML_CUDA_FA=ON \
  -DGGML_CUDA_GRAPHS=ON \
  -DGGML_CUDA_FORCE_MMQ=ON \
  -DGGML_LTO=ON \
  -DGGML_NATIVE=OFF \
  -DLLAMA_BUILD_SERVER=ON \
  -DLLAMA_BUILD_EXAMPLES=ON

# 编译
echo ""
echo "=== 编译中 (使用 6 线程) ==="
make -j6

# 检查是否成功
if [ -f "$HOME/llama.cpp/build/bin/llama-cli" ]; then
    echo ""
    echo "=========================================="
    echo "✅ 编译成功！"
    echo "=========================================="
    echo "可执行文件: $HOME/llama.cpp/build/bin/llama-cli"
    echo "API 服务:   $HOME/llama.cpp/build/bin/llama-server"
    echo "多模态CLI:  $HOME/llama.cpp/build/bin/llama-llava-cli"
    
    # 检查多模态库
    if [ -f "$HOME/llama.cpp/build/bin/libmtmd.so" ]; then
        echo "多模态库:   $HOME/llama.cpp/build/bin/libmtmd.so ✅"
    else
        echo "⚠️ 多模态库 libmtmd.so 未生成"
    fi
    
    # 测试 GPU
    echo ""
    echo "=== 测试 GPU 支持 ==="
    $HOME/llama.cpp/build/bin/llama-cli --verbose -m /dev/null -n 1 2>&1 | grep -i cuda
else
    echo ""
    echo "❌ 编译失败"
    exit 1
fi
