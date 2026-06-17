# WordCard v4.0 — 纯 C 间隔重复引擎 + GPU 学习界面

> 从 SM-2 记忆引擎到带 GPU 加速界面的完整学习系统
>
> **技术栈**：C (SM-2 + KV Cache) → C ABI 桥 → LuaJIT 业务逻辑 → Rust/GPUI GPU 渲染

---

## 项目定位

WordCard 是一个**纯 C 核心 + GPU 加速界面**的通用间隔重复学习系统：

- **C 语言内存数据库**：零依赖、零配置、结构体直写磁盘
- **SM-2 间隔重复算法**：标准 SuperMemo-2，与 Anki 行为一致
- **6 维度掌握度**：识别/回忆/拼写/听辨/发音/应用
- **KV Cache 知识存储**：层级命名空间 + 多维搜索 + 向量嵌入
- **GPU 加速 GUI**：Rust/GPUI 渲染引擎 + LuaJIT FFI 业务逻辑
- **25+ Rust 学习组件**：WordCard、ChoiceQuiz、FillBlank、SpellingPractice 等
- **8 种学习模式**：闪卡/选择/填空/默写/听辨/表达/配对/速闪

---

## 架构

```
┌─────────────────────────────────────────────────────────────┐
│                  Lua 业务逻辑层 (gui/lua/)                    │
│  main.lua — 学习流程：加载队列 → 翻转 → 作答 → SM-2 更新    │
│  gui.lua   — FFI 绑定：set_queue / flip_card / submit_answer│
├─────────────────────────────────────────────────────────────┤
│               C ABI 桥接层 (gui/cbridge/)                    │
│  gui_tick.c   — 60fps 定时器驱动 Lua 协程                   │
│  lua_engine.c — wordcard.* / cache.* 注册到 Lua 全局        │
├──────────────────┬──────────────────────────────────────────┤
│  libwordcard.so  │  libcache.so                              │
│  (SM-2 学习引擎) │  (KV Cache 知识存储)                      │
│                  │                                           │
│  · item_entry_t  │  · 层级命名空间 /coding/cpp/              │
│  · SM-2 算法     │  · 前缀/正则/模糊/标签/向量搜索           │
│  · 6 维度掌握度  │  · HNSW 近似最近邻                        │
│  · 智能推荐算法  │  · mmap 零拷贝持久化                       │
│  · 哈希索引      │  · TCP/HTTP 远程服务                      │
└────────┬─────────┴────────┬─────────────────────────────────┘
         │                  │
         ▼                  ▼
┌─────────────────────────────────────────────────────────────┐
│               Rust/GPUI GPU 渲染引擎                         │
│  libwordcard_gui.so — 25 个学习组件 + 布局 + 交互            │
│  依赖: gpui (Zed 编辑器 GPU 框架) + gpui-component          │
│  渲染: 原生 GPU (OpenGL/Vulkan), 60fps                      │
└─────────────────────────────────────────────────────────────┘
```

---

## 快速开始

### 1. 编译 C 核心库

```bash
cd src
make clean && make          # 生成 libwordcard.so + libcache.so
make test                    # 学习引擎 11 个测试
make test_cache              # KV Cache 10 个测试
```

### 2. 编译 Rust GUI

```bash
# 需要 Rust 工具链
cd gui/gpui
cargo build --release
# 生成 gui/gpui/target/release/libwordcard_gui.so (41MB)
```

### 3. 运行 (桌面环境)

```bash
cd gui
gcc -rdynamic -o test_gui test_gui.c -ldl -lpthread -lm
LD_LIBRARY_PATH=gpui/target/release:../src ./test_gui
```

---

## 项目结构

```
WordCard/
├── src/                          # C 核心库
│   ├── wordcard.h / wordcard.c  # SM-2 间隔重复引擎
│   ├── modes.c                  # 智能推荐算法
│   ├── cache.h                  # KV Cache API
│   ├── pool.h                   # 独立内存池（解耦自 my_db）
│   ├── mmap.c / metrics.c       # 基础设施
│   ├── cache/                   # 14 个源文件
│   │   ├── cache.c              # 核心 CRUD + 热点缓存
│   │   ├── hnsw.c               # HNSW 近似最近邻
│   │   ├── search.c             # 前缀/正则/模糊/标签搜索
│   │   ├── namespace.c          # 层级命名空间
│   │   ├── skip_list.c          # 跳表（大数据加速）
│   │   ├── server.c             # TCP 文本协议服务
│   │   └── ...
│   ├── test_sm2.c               # 学习引擎测试（11 个）
│   ├── test_cache_basic.c       # KV Cache 测试（10 个）
│   └── Makefile                 # 编译 3 个目标
│
├── gui/                         # GPU 加速 GUI
│   ├── gpui/                    # Rust 渲染引擎
│   │   ├── Cargo.toml          # → libwordcard_gui.so
│   │   └── src/
│   │       ├── lib.rs           # WordCardView + C FFI 导出
│   │       └── components/      # 25 个学习组件
│   ├── cbridge/                 # C ABI 桥
│   │   ├── gui_tick.c           # 定时器回调
│   │   └── lua_engine.c         # Lua 引擎（注册 C 函数）
│   ├── lua/                     # Lua 业务逻辑
│   │   ├── gui.lua             # FFI 绑定
│   │   └── main.lua            # 学习流程控制
│   ├── test_gui.c              # 演示入口
│   └── reference/              # 架构文档
│
├── importer/wrappers/           # C++ 电子书解析
│   ├── mobi_wrapper.cpp        # MOBI/AZW3 (libmobi)
│   └── pdf_wrapper.cpp         # PDF/EPUB (MuPDF)
│
├── design.md                    # 完整架构设计
├── README.md                    # 本文档
└── data/                        # 数据目录
    ├── wordcard.db             # 学习数据库
    └── cache/                  # KV Cache 数据
```

---

## 技术栈

| 层 | 技术 | 产物 | 大小 |
|-----|------|------|------|
| **学习引擎** | C (C11) | `libwordcard.so` | 34KB |
| **知识缓存** | C (C11) | `libcache.so` | 124KB |
| **C 桥接** | C + LuaJIT | `gui_tick.c` + `lua_engine.c` | - |
| **业务逻辑** | LuaJIT 2.1 | `gui/lua/*.lua` | - |
| **渲染引擎** | Rust + gpui | `libwordcard_gui.so` | 41MB |
| **UI 组件** | Rust + gpui-component | 25 个学习组件 | - |

### 依赖

| 依赖 | 用途 | 类型 |
|------|------|------|
| gcc / make | 编译 C 核心库 | 必需 |
| Rust / Cargo | 编译 GUI | 可选（只用 C API 则不需要） |
| LuaJIT 2.1 | 运行业务逻辑 | 可选（只用 C API 则不需要） |
| gpui-component | GPU 渲染框架 | 可选 |
| Python 3 | 已移除（v4.0 纯 C 架构） | ❌ 不需要 |

---

## SM-2 间隔重复

标准 SuperMemo-2 算法，覆盖所有场景：

| 场景 | 行为 |
|------|------|
| 新项首次学习 | interval = 1 天 |
| 第二次记住 | interval = 6 天 |
| 第三次记住 | interval = interval × ease_factor |
| 忘记 | interval 重置为 1 天 |
| 掌握判定 | repetitions ≥ 5 且 interval ≥ 21 天 |

## KV Cache 搜索能力

| 搜索类型 | 复杂度 | 实现 |
|---------|--------|------|
| 精确匹配 | O(1) | FNV-1a 哈希 |
| 前缀搜索 | O(log n + k) | 排序数组二分 |
| 正则搜索 | O(n) | POSIX regexec |
| 模糊搜索 | O(n) | Levenshtein 距离 |
| 标签搜索 | O(1) | 反向索引 |
| 向量搜索 | O(log n) | HNSW |

---

## GUI 组件一览

| 组件 | 用途 |
|------|------|
| `WordCard` | 英语单词卡片（音标/词性/释义/例句） |
| `FlashCard` | 通用卡片正反面 |
| `ChoiceQuiz` | 四选一 |
| `FillBlank` | 句子填空 |
| `MatchingGame` | 左右配对 |
| `SpellingPractice` | 看释义拼写 |
| `DictationView` | 听写模式 |
| `PronunciationGuide` | 音节拆分 + 重音 |
| `SpeedReview` | 3 秒速闪判断 |
| `StatsWidget` | 学习统计 |
| `DailyGoal` | 每日目标进度 |
| `HeatmapCalendar` | GitHub 风格热力图 |
| ... 共 25 个 |

---

## 版本历史

| 版本 | 时间 | 核心变更 |
|------|------|----------|
| v1.0 | 2024 | 文章翻译工具 |
| v2.0 | 2025-05 | C + Python 架构，SM-2 单词记忆 |
| v3.0 | 2025-05 | 通用学习引擎 |
| **v4.0** | **2026-06** | **纯 C 重构 + KV Cache + GPU GPU 界面** |

*最后更新: 2026-06-17*
