# WordCard 设计方案

> 纯 C 间隔重复学习引擎 + KV Cache 知识缓存 + 电子书语义搜索
> 文档版本: v4.0 — 2026-06-17

---

## 一、设计哲学

**纯 C，零依赖，零 Python。**

- **C 共享库**：`libwordcard.so` 包含 SM-2 间隔重复引擎 + KV Cache 记忆系统 + 电子书解析能力，全部 C 实现
- **mmap 零拷贝持久化**：结构体直写磁盘 + 内存池分配，启动即加载
- **KV Cache 知识库**：层级命名空间 + 多维搜索 + 向量嵌入，专为 AI Agent 记忆设计
- **电子书语义搜索**：EPUB/MOBI/AZW3/PDF → 分章 → 向量化 → HNSW 近似搜索
- **无外部依赖**：仅需标准 C 库 + pthread + OpenMP（可选加速），零配置部署

---

## 二、技术架构

```
┌──────────────────────────────────────────────────────────────────────┐
│                         libwordcard.so                                │
│                                                                      │
│  ┌──────────────────────────┐  ┌──────────────────────────────────┐  │
│  │  间隔重复引擎 (wordcard.c)  │  │  KV Cache 知识缓存 (src/cache/)  │  │
│  │  · item_entry_t 通用学习项 │  │  · cache_set/get/del CRUD      │  │
│  │  · SM-2 间隔重复算法       │  │  · 层级命名空间 /coding/cpp/    │  │
│  │  · 6 维度掌握度系统        │  │  · 前缀/正则/模糊/标签搜索     │  │
│  │  · 智能推荐算法 (modes.c)  │  │  · 向量存储 + HNSW 近似搜索    │  │
│  │  · 哈希索引 + 到期排序索引  │  │  · mmap 内存池持久化           │  │
│  └──────────┬───────────────┘  │  · 索引持久化 (index.bin)       │  │
│             │                  │  · TCP/HTTP 远程访问服务         │  │
│             │                  └────────────────┬─────────────────┘  │
│             │                                   │                    │
│             ▼                                   ▼                    │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │  内容导入与电子书解析系统                                      │  │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌───────────────┐  │  │
│  │  │ importer/       │  │ tools/import_book│  │ Parser (.so)  │  │  │
│  │  │ C++ Wrapper .so │  │ (C 程序)          │  │ · libmobiparse│  │  │
│  │  │ · MOBI/AZW3     │  │ EPUB/MOBI/PDF →  │  │ · libpdfparse │  │  │
│  │  │ · PDF/EPUB      │  │ 分章→向量→Cache │  │ · (C++ Wrapper)│  │  │
│  │  └─────────────────┘  └─────────────────┘  └───────────────┘  │  │
│  └────────────────────────────────────────────────────────────────┘  │
│                       │                                              │
│                       ▼                                              │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │  持久化层：mmap 文件                                           │  │
│  │  ├── data/wordcard.db     (WCD\x03 结构体直写)                 │  │
│  │  ├── data/cache/cache.bin (KV Cache mmap 池, "MYCA")          │  │
│  │  ├── data/cache/index.bin (KV Cache 索引持久化)                │  │
│  │  └── data/cache/vectors/  (向量文件 + HNSW 索引)               │  │
│  └────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────┘
```

### 数据流

```
学习场景:
  用户 → SM-2 队列 → 学习模式(闪卡/选择/填空/...) → 复习提交 → 掌握度更新
                                                              │
                                                              ▼
                                                       wordcard.db 持久化

电子书导入:
  电子书(EPUB/MOBI/PDF) → C++ Wrapper 提取文本 → 分章 → LLM 摘要
       → KV Cache 存储 (/books/{title}/chapter-N)
       → Markdown 输出 (/opt/books/)
       → 向量生成 (Jina v2) → HNSW 索引

知识检索:
  自然语言查询 → 向量化 → HNSW 搜索 → 返回最相关页面
  前缀/正则/标签搜索 → 排序数组二分查找 → 返回结果
```

---

## 三、KV Cache 记忆系统

### 3.1 来源与定位

集成自 `/opt/my_db` 项目的 KV Cache 模块（设计文档见 `kvCache.md`），专为 AI Agent 设计的层级化记忆存储系统。

| 属性 | 说明 |
|------|------|
| **来源** | `/opt/my_db` 项目，已生产验证（Phase 2 + TCP 远程操作完成） |
| **集成方式** | 源码直接嵌入 `libwordcard.so`，14 个 .c 文件编译进共享库 |
| **定位** | 非结构化知识存储（相对于 wordcard.db 的结构化学习数据） |
| **核心** | 纯 KV + 层级 Namespace + 多维搜索 + 向量嵌入 |

### 3.2 架构设计

```
cache_t (struct cache)
├── db_pool_t pool          # mmap 内存池 (cache.bin, 魔数 "MYCA")
├── hash_index_t hash       # FNV-1a 哈希索引 → entry_offset (O(1))
├── sorted_array_t sorted   # 排序数组 (key 字典序, 二分查找)
├── ns_node_t* ns_root      # Namespace 树 (/coding/cpp → /coding/cpp/templates)
├── tag_index_t tag_index   # 标签反向索引 (tag → [entry_offsets])
├── vector_index_t vector   # 向量索引 (HNSW 近似最近邻)
└── hot_entry_t hot[64]     # 热点缓存 (加速重复读取)
```

### 3.3 文件格式

```
cache.bin (mmap 内存池)
├── [文件头: 48 bytes]
│   ├── magic: "MYCA" (4)
│   ├── version: 1 (4)
│   ├── used: 8 (已用空间)
│   ├── entry_count: 8
│   ├── hash_offset: 8
│   └── reserved: 16
│
└── [Entries...] 变长存储
    ├── cache_entry_header_t: 28 bytes (packed)
    │   ├── key_len: 4
    │   ├── value_len: 4
    │   ├── expire_at: 8 (毫秒, 0=永久)
    │   ├── access_time: 8
    │   ├── flags: 2 (DELETED/PERMANENT)
    │   └── reserved: 2
    ├── key: N bytes (UTF-8)
    ├── \0: 1 byte
    ├── value: N bytes (JSON)
    └── \0: 1 byte

index.bin (索引持久化)
├── [文件头: 24 bytes]
│   ├── magic: "MYIX" (4)
│   ├── version: 1 (4)
│   ├── total_size: 8
│   ├── index_count: 4
│   └── reserved: 4
└── [Index Entries...]
    ├── type: 4 (HASH/SORTED/VECTOR/TAG/HNSW)
    ├── data_offset: 8
    ├── data_size: 8
    └── entry_count: 8
```

### 3.4 搜索能力

| 搜索类型 | 复杂度 | 实现 |
|---------|--------|------|
| **get** (精确匹配) | O(1) | FNV-1a 哈希 + 链地址法 |
| **前缀搜索** | O(log n + k) | 排序数组二分找 lower_bound + 向后遍历 |
| **范围搜索** | O(log n + k) | 二分找起止点 |
| **正则搜索** | O(n) | POSIX regexec 遍历 |
| **模糊搜索** | O(n) | Levenshtein 距离计算 |
| **标签搜索** | O(1) 平均 | tag → [offsets] 反向索引 |
| **向量搜索** | O(log n) | HNSW 分层可导航小世界图 |

### 3.5 命名空间设计

```
/books                   ← 书籍知识库
/books/ddia              ← 具体书籍
/books/ddia/chapter-01   ← 章节维度

/coding                  ← 编程知识
/coding/cpp/move-semantics
/coding/python/async

/agent                   ← Agent 配置与记忆
/agent/personality
/agent/session/20240617

/github/{owner}/{repo}   ← 源码项目扫描
/github/redis/redis/_meta/readme
```

### 3.6 API 一览

```c
#include "cache.h"

// 生命周期
cache_t* cache_open(const char* db_dir, size_t max_memory);
void cache_close(cache_t* cache);
int cache_sync(cache_t* cache);

// CRUD
int cache_set(cache_t* cache, const char* key, const char* value, uint64_t ttl_ms);
const char* cache_get(cache_t* cache, const char* key);
int cache_del(cache_t* cache, const char* key);
int cache_exists(cache_t* cache, const char* key);
int cache_batch_set(cache_t* cache, const cache_batch_item_t* items, size_t count);

// 命名空间
int cache_set_ns(cache_t* cache, const char* ns, const char* key, const char* value, uint64_t ttl_ms);
const char* cache_get_ns(cache_t* cache, const char* ns, const char* key);
int cache_del_namespace(cache_t* cache, const char* ns);

// 搜索
int cache_search_prefix(cache_t* cache, const char* prefix, ...);
int cache_search_regex(cache_t* cache, const char* pattern, ...);
int cache_search_fuzzy(cache_t* cache, const char* query, int max_distance, ...);
int cache_search_tag(cache_t* cache, const char* tag, ...);
int cache_search_vector(cache_t* cache, const float* query, size_t dim, int top_k, ...);

// 向量
int cache_set_vector(cache_t* cache, const char* key, const char* value,
                     const float* vector, size_t dim, uint64_t ttl_ms);

// 源码分析
cache_ast_tree_t* cache_analyze_source(const char* filename, const char* source);
char* cache_ast_to_json(const cache_ast_tree_t* tree, const char* filename);

// 管理
size_t cache_compact(cache_t* cache);
size_t cache_purge_expired(cache_t* cache);
int cache_check(const char* db_dir);
```

### 3.7 生命周期与 TTL

```
三级记忆系统:
  TTL_WORKING   = 5 分钟     # 工作记忆：当前任务上下文
  TTL_SHORT     = 1 小时     # 短期记忆：会话记忆
  TTL_LONG      = 24 小时    # 中期记忆：日内记忆
  TTL_PERMANENT = 0          # 永久记忆：知识积累

LRU 淘汰: access_time 排序 → 淘汰最旧非永久条目 → 直到内存 < 80%
惰性过期: cache_get 时检查 expire_at → 返回 NULL + 标记 DELETED
```

---

## 四、电子书导入与语义搜索系统

### 4.1 来源与定位

完整设计见 `/opt/my_db/ebook.md`。基于 KV Cache 存储后端的电子书语义搜索系统。

| 组件 | 来源 | 说明 |
|------|------|------|
| **KV Cache 存储** | `src/cache/*.c` | 集成到 libwordcard.so |
| **MOBI/AZW3 解析** | `importer/wrappers/mobi_wrapper.cpp` | 基于 libmobi 的 C++ Wrapper |
| **PDF/EPUB 解析** | `importer/wrappers/pdf_wrapper.cpp` | 基于 MuPDF 的 C++ Wrapper |
| **import_book** | tools/import_book.c（预期位置） | C 版电子书导入程序 |
| **Jina 嵌入** | ONNX Runtime + TensorRT 加速 | 768 维向量 |
| **HNSW 索引** | `src/cache/hnsw.c` | 分层可导航小世界图 |

### 4.2 支持格式

| 格式 | 扩展名 | 解析库 | C++ Wrapper 位置 |
|------|--------|--------|-----------------|
| EPUB | `.epub` | MuPDF | `importer/wrappers/pdf_wrapper.cpp` |
| MOBI | `.mobi` | libmobi | `importer/wrappers/mobi_wrapper.cpp` |
| AZW3 | `.azw3` | libmobi | `importer/wrappers/mobi_wrapper.cpp` |
| PDF | `.pdf` | MuPDF | `importer/wrappers/pdf_wrapper.cpp` |

### 4.3 导入流程

```
    电子书文件 (.epub/.mobi/.azw3/.pdf)
            │
            ▼
    ┌──────────────────┐
    │ C++ Wrapper .so   │  ← libmobiparse.so / libpdfparse.so
    │ 提取纯文本 + 元数据│     基于 /opt/libmobi + /opt/mupdf
    └────────┬─────────┘
            │ 文本
            ▼
    ┌──────────────────┐
    │ 章节切分          │  ← 多策略匹配：
    │                   │     1. NCX 目录索引逐章提取
    │                   │     2. "Chapter X:" 格式匹配
    │                   │     3. 中文章节前缀 ("第一章")
    │                   │     4. 固定长度 fallback
    └────────┬─────────┘
            │ 章节列表
            ▼
    ┌──────────────────┐
    │ 每个章节:          │
    │ 1. 分段 → pages   │  ← 句子边界切分 (支持中文标点)
    │ 2. 生成向量        │  ← Jina v2 768d ONNX + TensorRT
    │ 3. 写入 KV Cache   │  ← /books/{title}/ch-{N}/page_{M}
    │ 4. 写入 Markdown   │  ← /opt/books/{title}/chapters/
    └────────┬─────────┘
            │
            ▼
    ┌──────────────────┐
    │ 构建 HNSW 索引    │  ← tools/build_hnsw_index
    │ 向量搜索加速       │
    └────────┬─────────┘
            │
            ▼
    ┌──────────────────┐
    │ 批量 mv 到最终目录 │  ← tmpfs (/dev/shm) 加速文件 IO
    │ 完成导入           │
    └──────────────────┘
```

### 4.4 搜索与查询

```bash
# 书籍概览
./explore_book.sh /books/ddia overview

# 语义搜索（自然语言）
./explore_book.sh /books/ddia search "consensus algorithm"

# 读取页面
./explore_book.sh /books/ddia read chapters/08-Consensus/page_0012

# 跨书搜索（所有已导入书籍）
./tools/cache_query "concurrency" --type search --analysis-dir /book/cache
```

### 4.5 输出结构

```
/opt/books/{book_name}/
├── _meta.json              # 书籍元数据
└── chapters/               # 章节目录
    └── 01-Chapter_Title/   # 章节文件夹
        ├── page_0000.md    # 页面 Markdown
        ├── page_0001.md
        └── ...

/book/cache/
├── cache.bin               # KV Cache 原始数据 (mmap)
├── index.bin               # 索引持久化文件
└── vectors/                # 向量文件
    ├── books_{name}.jina.bin       # 向量二进制
    ├── books_{name}.jina.idx       # 偏移索引
    └── books_{name}.jina.bin.hnsw  # HNSW 搜索索引
```

---

## 五、C 层数据结构（libwordcard.so）

### 5.1 组件依赖关系

```
libwordcard.so
├── wordcard.c          # SM-2 间隔重复引擎
│   ├── item_entry_t    #  通用学习项（question/answer/explanation...）
│   ├── user_t          #  用户管理
│   ├── user_item_mastery_t  #  6 维度掌握度 + SM-2 参数
│   ├── 哈希索引        #  5 种运行时哈希表（动态扩容）
│   └── 到期排序索引    #  惰性重建，二分查找
│
├── modes.c             # 智能推荐算法（7条规则决策树）
│
├── cache/*.c           # KV Cache 系统（来自 /opt/my_db）
│   ├── cache.c         #  核心 CRUD + 热点缓存
│   ├── hash_index.c    #  FNV-1a 哈希索引
│   ├── sorted_array.c  #  排序数组（前缀/范围搜索）
│   ├── search.c        #  正则/模糊搜索
│   ├── namespace.c     #  层级命名空间
│   ├── tag_index.c     #  标签反向索引
│   ├── skip_list.c     #  跳表（>100 万数据加速）
│   ├── vector_index.c  #  向量索引
│   ├── hnsw.c          #  HNSW 近似最近邻
│   ├── iter.c          #  迭代器
│   ├── index_persistence.c  #  索引持久化
│   ├── source_analyzer.c    #  源码语义分析
│   ├── server.c        #  TCP 远程服务
│   └── http_server.c   #  HTTP REST 服务
│
└── 基础设施（来自 /opt/my_db）
    ├── mmap.c          #  db_pool_t 内存池 (mmap)
    ├── metrics.c       #  结构化日志 + Prometheus 指标
    └── crc32.c         #  CRC32 校验
```

### 5.2 文件格式对比

| 系统 | 文件 | 魔数 | 版本 | 存储方式 | 用途 |
|------|------|------|------|----------|------|
| **间隔重复引擎** | `wordcard.db` | `WCD\x03` | 3 | 结构体数组直写 | 学习项/用户/掌握度 |
| **KV Cache** | `cache.bin` | `MYCA` | 1 | mmap 变长池 | Key-Value 知识存储 |
| **KV Cache 索引** | `index.bin` | `MYIX` | 1 | mmap 索引 | 哈希/排序/向量索引 |

### 5.3 哈希索引实现

**间隔重复引擎**（纯 C 手写 3 种哈希表）:

| 哈希类型 | 用途 | 键 | 值 |
|----------|------|-----|-----|
| `str_hash_t` | question → item_index | char* | int (数组下标) |
| `int_hash_t` | id → item_index | uint32_t | int |
| `pair_hash_t` | (user_id,item_id) → mastery_index | 2×uint32_t | int |

特点：链地址法 + 动态扩容 (load factor > 0.75 → bucket x2)

**KV Cache**（FNV-1a + 开放寻址）:

```
HASH(key) = FNV-1a(key) % bucket_count
冲突解决：链地址法（排序数组存储 offset）
扩容：load factor > 0.75 → bucket 翻倍 + 重哈希
```

---

## 六、间隔重复引擎（wordcard.c + modes.c）

### 6.1 SM-2 算法

标准 SuperMemo-2 实现，验证与 Anki 行为一致：

| 场景 | 行为 |
|------|------|
| 新项首次学习 | interval = 1 天，repetitions = 1 |
| 第二次记住 | interval = 6 天 |
| 第三次记住 | interval = interval × ease_factor |
| 忘记（quality < 3）| interval 重置为 1 天，repetitions = 0 |
| 难度调整 | ease_factor += 0.1 - (5-q) × (0.08 + (5-q) × 0.02)，最低 1.3 |
| 掌握判定 | repetitions ≥ 5 且 interval ≥ 21 天 |

### 6.2 6 维度掌握度

| 维度 | 权重 | 含义 |
|------|------|------|
| recognition | 25% | 看到问题→知答案 |
| recall | 20% | 看到提示→想答案 |
| spelling | 20% | 默写/复现准确度 |
| listening | 15% | 听辨/理解 |
| pronunciation | 10% | 发音评分（ASR） |
| usage | 10% | 应用/实践 |

更新规则：正确 +10 分，错误 -15 分，滑动平均，clamp 0-100。

### 6.3 智能推荐算法（7 条规则）

```
新项 (total_reviews == 0)         → 闪卡模式
连续忘记 ≥ 3 次                    → 闪卡模式 + 标记困难
识别高(>80) 但拼写差(<50)         → 拼写/默写模式
能认(>70) 但表达差(<60)           → 发音模式 (ASR 评分)
能认(>70) 但听辨差(<50)           → 听写模式
全面掌握(overall>85, streak≥5)    → 速闪模式
SM-2 到期复习                      → 最弱维度匹配模式
默认                               → 选择题模式
```

### 6.4 8 种学习模式

| 模式 | ID | 说明 |
|------|-----|------|
| 闪卡 (Flashcard) | 1 | 问题→答案，建立初步认知 |
| 选择 (Choice) | 2 | 四选一综合测试 |
| 填空 (Fill Blank) | 3 | 在例句中填空 |
| 拼写 (Spelling) | 4 | 看释义写答案 |
| 听写 (Dictation) | 5 | 听音频写答案 |
| 发音 (Pronunciation) | 6 | ASR 评分 |
| 配对 (Matching) | 7 | 问题-答案配对 |
| 速闪 (Speed Review) | 8 | 快速判断，维持记忆 |

---

## 七、项目结构

```
WordCard/
├── design.md                     # 本文档
├── README.md                     # 项目总览
├── task.md                       # 开发进度

├── src/                          # C 核心库 (编译 → libwordcard.so)
│   ├── wordcard.h                # 间隔重复引擎：数据结构 + API 声明
│   ├── wordcard.c                # 数据库引擎 + SM-2 + 哈希索引
│   ├── modes.c                   # 智能推荐算法
│   ├── test_sm2.c                # C 单元测试（11 个测试）
│   │
│   ├── cache.h                   # KV Cache 公共 API（来自 /opt/my_db）
│   ├── cache_internal.h          # 内部数据结构
│   ├── cache_index.h             # 索引持久化
│   ├── cache_hnsw.h              # HNSW 搜索
│   ├── cache_http_server.h       # HTTP 远程服务
│   ├── cache_server.h            # TCP 远程服务
│   ├── mydb.h                    # my_db 兼容头
│   ├── mydb_internal.h           # db_pool_t 内部结构
│   ├── metrics.h                 # 结构化日志
│   │
│   ├── mmap.c                    # 内存池实现（来自 /opt/my_db）
│   ├── metrics.c                 # 日志/指标实现
│   ├── crc32.c                   # CRC32 校验
│   │
│   ├── cache/                    # KV Cache 实现（14 个 .c 文件）
│   │   ├── cache.c               # 核心 CRUD
│   │   ├── hash_index.c          # FNV-1a 哈希索引
│   │   ├── hnsw.c                # HNSW 近似最近邻
│   │   ├── http_server.c         # HTTP REST 服务
│   │   ├── index_persistence.c   # 索引持久化
│   │   ├── iter.c                # 迭代器
│   │   ├── namespace.c           # 层级命名空间
│   │   ├── search.c              # 前缀/正则/模糊搜索
│   │   ├── server.c              # TCP 文本协议服务
│   │   ├── skip_list.c           # 跳表（大数据加速）
│   │   ├── sorted_array.c        # 排序数组 + 二分查找
│   │   ├── source_analyzer.c     # 源码语义分析
│   │   ├── tag_index.c           # 标签反向索引
│   │   └── vector_index.c        # 向量索引
│   │
│   └── Makefile                  # 编译脚本（自动检测 OpenMP）

├── importer/wrappers/            # C++ 电子书解析 Wrapper
│   ├── mobi_wrapper.cpp          # MOBI/AZW3 解析（基于 libmobi）
│   ├── pdf_wrapper.cpp           # PDF/EPUB 解析（基于 MuPDF）
│   └── Makefile                  # 编译 → importer/libs/ 目录

└── data/                         # 数据目录
    ├── wordcard.db               # 间隔重复数据库
    └── cache/                    # KV Cache 数据
        ├── cache.bin             # mmap 内存池
        └── index.bin             # 索引持久化
```

---

## 八、依赖来源

| 组件 | 来源 | 许可 | 说明 |
|------|------|------|------|
| **间隔重复引擎** | 本项目原创 | - | SM-2 + 6 维度掌握度 + 智能推荐 |
| **KV Cache 系统** | `/opt/my_db` 项目 | - | 14 个 .c 文件源码嵌入 |
| **my_db 基础设施** | `/opt/my_db` 项目 | - | mmap 池 + metrics + crc32 |
| **libmobi 解析库** | `/opt/libmobi` | GPL | 静态链接到 libmobiparse.so |
| **MuPDF 解析库** | `/opt/mupdf` | AGPL | 静态链接到 libpdfparse.so |
| **Jina v2 嵌入** | HuggingFace / ONNX | Apache 2.0 | 可选语义搜索组件 |
| **ONNX Runtime** | Microsoft | MIT | 可选 GPU 加速推理 |
| **TensorRT** | NVIDIA | NVIDIA EULA | 可选 GPU 加速（4090D 优化） |

### 编译步骤

```bash
# 1. 编译 C 核心库（间隔重复引擎 + KV Cache）
cd src && make clean && make && make test
# 输出: src/libwordcard.so (包含全部功能)

# 2. 编译电子书解析 Wrapper（可选）
cd importer/wrappers && make
# 输出: importer/libs/libmobiparse.so, importer/libs/libpdfparse.so
```

---

## 九、使用示例

### 间隔重复引擎

```c
#include "wordcard.h"

int main() {
    // 打开数据库
    wordcard_db_t *db = wc_db_init();

    // 添加学习项
    item_entry_t item = {0};
    strcpy(item.question, "abandon");
    strcpy(item.answer, "放弃");
    item.category = CAT_ENGLISH_VOCAB;
    uint32_t id = wc_add_item(db, &item);

    // 创建用户
    uint32_t uid = wc_create_user(db, "user001", "Alice");

    // 获取掌握度并复习
    user_item_mastery_t *m = wc_get_or_create_mastery(db, uid, id);
    wc_sm2_update(m, 4);  // SM-2 评级：4 = Good

    // 获取今日学习队列
    uint32_t now = wc_now();
    uint32_t ids[50];
    uint8_t modes[50];
    size_t count = wc_generate_daily_queue(db, uid, now, ids, modes, 50);

    // 保存并关闭
    wc_save_db(db, "data/wordcard.db");
    wc_db_free(db);
}
```

### KV Cache

```c
#include "cache.h"

int main() {
    // 打开 KV Cache（100MB 上限）
    cache_t *cache = cache_open("data/cache", 100 * 1024 * 1024);

    // 存储知识点
    cache_set(cache, "/coding/cpp/move-semantics",
              "{\"t\":\"concept\",\"c\":\"右值引用实现完美转发\",\"i\":5}", 0);

    // 命名空间快捷方式
    cache_set_ns(cache, "/coding/cpp", "templates/sfinae",
                 "SFINAE: Substitution Failure Is Not An Error...", 0);

    // 前缀搜索
    cache_result_t *results;
    size_t count;
    cache_search_options_t opts = cache_search_options_default();
    cache_search_prefix(cache, "/coding/cpp/", &opts, &results, &count);

    // 精确获取
    const char *val = cache_get(cache, "/coding/cpp/move-semantics");

    // 持久化
    cache_sync(cache);
    cache_close(cache);
}
```

---

## 十、性能指标

| 操作 | 间隔重复引擎 | KV Cache |
|------|-------------|----------|
| get (精确匹配) | O(1) 哈希 | O(1) FNV-1a 哈希 |
| 添加项 | O(1) 均摊 | O(log n) 排序数组插入 |
| 前缀搜索 | - | O(log n + k) |
| 正则搜索 | - | O(n) |
| 向量搜索 (HNSW) | - | O(log n) |
| 磁盘加载 (10万条) | < 1 秒（结构体直写） | < 100ms（mmap 零拷贝） |
| 单次查询 | < 1ms | < 1us（热点命中） |

---

## 十一、版本历史

| 版本 | 时间 | 核心变更 |
|------|------|----------|
| v1.0 | 2024 | 文章翻译工具（llm.py + card.py） |
| v2.0 | 2025-05 | C + Python 架构，SM-2 单词记忆 |
| v3.0 | 2025-05 | 通用学习引擎，支持任意知识类型 |
| **v4.0** | **2026-06** | **纯 C 重构：移除 Python，集成 KV Cache + 电子书语义搜索** |

*最后更新: 2026-06-17*
