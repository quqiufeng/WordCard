#!/bin/bash
# run_tests.sh — WordCard GUI 自动化测试运行器
# 支持：直接运行 / Xvfb 虚拟显示 / 远程显示
#
# 用法：
#   ./run_tests.sh                  # 在当前显示器运行
#   DISPLAY=:99 ./run_tests.sh       # 指定显示器
#   HEADLESS=1 ./run_tests.sh       # 自动启动 Xvfb 虚拟显示
#
# AI 集成：
#   AI 生成 Lua 测试脚本 → 放入 lua/ 目录 → 运行此脚本
#   结果输出为 JSON，AI 可直接解析

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# 如果设置了 HEADLESS，自动启动虚拟显示
if [ -n "$HEADLESS" ]; then
    if ! command -v Xvfb &>/dev/null; then
        echo "[WARN] Xvfb not installed. Installing..."
        sudo apt-get install -y xvfb 2>/dev/null || {
            echo "[ERROR] Cannot install Xvfb. Run with a real display."
            exit 1
        }
    fi
    export DISPLAY="${DISPLAY:-:99}"
    # 启动 Xvfb（如果未运行）
    if ! xdpyinfo -display "$DISPLAY" &>/dev/null 2>&1; then
        Xvfb "$DISPLAY" -screen 0 1280x720x24 &
        XVFB_PID=$!
        sleep 1
        echo "[OK] Xvfb started on $DISPLAY (PID $XVFB_PID)"
    fi
fi

# 检查显示可用
if ! xdpyinfo &>/dev/null 2>&1; then
    echo "[ERROR] No display available. Use HEADLESS=1 or set DISPLAY."
    exit 1
fi

echo "[INFO] Display: $DISPLAY"

# 运行测试
echo ""
echo "============================================"
echo " WordCard GUI Test Suite"
echo "============================================"
echo ""

TEST_SCRIPT="${1:-lua/test_study_flow.lua}"
if [ ! -f "$TEST_SCRIPT" ]; then
    echo "[ERROR] Test script not found: $TEST_SCRIPT"
    exit 1
fi

echo "[RUN] $TEST_SCRIPT"
echo ""

# 直接运行 Lua 测试（不需要 Rust GUI，只测试 Lua FFI 层）
# 注意：这个测试不需要窗口，只验证 API 调用
luajit "$TEST_SCRIPT"
EXIT_CODE=$?

echo ""
if [ $EXIT_CODE -eq 0 ]; then
    echo "[PASS] All tests passed"
else
    echo "[FAIL] Some tests failed (exit code $EXIT_CODE)"
fi

# 清理 Xvfb
if [ -n "${XVFB_PID:-}" ]; then
    kill "$XVFB_PID" 2>/dev/null || true
fi

exit $EXIT_CODE
