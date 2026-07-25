# WordCard v4.0 — SM-2 间隔重复学习引擎

> 从电子书导入 → 提取词汇 → SM-2 15 天复习 → CLI/API + 卡片图片

---

## 项目定位

WordCard 是一个**电子书驱动**的间隔重复学习系统：

- **C 核心引擎**：零依赖 SM-2 算法 + 哈希索引 + 结构体直写磁盘
- **电子书导入**：PDF/MOBI/AZW3/MD → 提取词汇 → 上下文关联
- **双接口**：CLI 终端复习 + FastAPI REST 接口
- **卡片图片**：HarfBuzz shaping + Knuth-Plass 最优断行 + Cairo 渲染
- **15 天掌握周期**：SM-2 算法确保到期复习

---

## 架构

```
用户
 ├── CLI (cli.py) ──────── 终端交互复习
 ├── API (api.py) ──────── FastAPI REST (port 8000)
 └── 卡片图片 ───────────── txt2png Canvas → PNG

Python 层
 ├── engine.py  ────────── SM-2 ctypes 绑定 → libwordcard.so
 ├── importer.py ───────── 电子书解析 → 词汇提取 → DB
 ├── txt2png.py ────────── 画布 API → libtxt2png.so
 └── generate_card.py ──── 多格式输出 (MD/PNG/PDF)

C/C++ 层
 ├── libwordcard.so ────── SM-2 学习引擎 (wordcard.c + modes.c)
 ├── libcache.so ───────── KV Cache (14 个模块)
 ├── libtxt2png.so ─────── HarfBuzz + Knuth-Plass + Cairo
 └── importer/libs/
      ├── libmobiparse.so ─ MOBI/AZW3 解析 (libmobi)
      └── libpdfparse.so ── PDF/EPUB 解析 (MuPDF)
```

---

## 快速开始

### 1. 安装依赖

```bash
# C 核心库
cd src && make

# 电子书解析（可选，仅 PDF/MOBI 需要）
cd importer/wrappers && make

# Python 依赖
pip install fastapi uvicorn pyphen uniseg  # API + txt2png
```

### 2. 初始化数据库

```bash
python3 -c "
import engine
db = engine.WordCardDB()
db.create_user('default', 'Default User')
db.save('data/wordcard.db')
"
```

### 3. 导入电子书

```bash
python3 cli.py import book.mobi
python3 cli.py import book.pdf
python3 cli.py import chapter.md
```

### 4. 开始复习

```bash
# CLI 交互
python3 cli.py review

# 查看统计
python3 cli.py stats

# 生成单词卡片图片
python3 cli.py card 1
```

### 5. 启动 API

```bash
python3 api.py
# → http://localhost:8000/docs
```

---

## 项目结构

```
WordCard/
├── src/                          # C 核心库
│   ├── wordcard.h / wordcard.c  # SM-2 引擎
│   ├── modes.c                  # 智能推荐算法
│   ├── cache/                   # KV Cache（14 个模块）
│   ├── txt2png/                 # C++ txt2png 桥接
│   │   ├── linebreak.h/cpp      # Knuth-Plass 算法
│   │   ├── textrender_core.cpp  # HarfBuzz + Cairo 渲染
│   │   └── txt2png_bridge.h     # C ABI 接口
│   └── Makefile
│
├── engine.py                    # SM-2 ctypes 绑定
├── importer.py                  # 电子书导入管道
├── cli.py                       # CLI 交互复习
├── api.py                       # FastAPI REST
├── txt2png.py                   # 画布 API (Canvas)
├── generate_card.py             # 多格式卡片输出
│
├── importer/
│   ├── wrappers/                # C++ 电子书解析
│   │   ├── mobi_wrapper.cpp     # MOBI/AZW3 (libmobi)
│   │   ├── pdf_wrapper.cpp      # PDF/EPUB (MuPDF)
│   │   └── Makefile
│   └── libs/                    # 编译产物
│       ├── libmobiparse.so
│       └── libpdfparse.so
│
├── data/                        # 数据库目录
│   └── wordcard.db
│
├── output/                      # 卡片输出
│
├── design.md                    # 架构文档
├── README.md                    # 本文档
└── task.md                      # 开发进度
```

---

## API 一览

| 端点 | 方法 | 说明 |
|------|------|------|
| `/api/v1/user` | POST | 创建用户 |
| `/api/v1/user/{id}` | GET | 获取用户 |
| `/api/v1/item` | POST | 添加学习项 |
| `/api/v1/item/{id}` | GET | 获取学习项 |
| `/api/v1/review` | POST | 提交复习 (quality 0-5) |
| `/api/v1/queue/{user_id}` | GET | 获取今日学习队列 |
| `/api/v1/import` | POST | 导入电子书 |
| `/api/v1/stats/{user_id}` | GET | 学习统计 |

---

## SM-2 间隔重复

| 场景 | 行为 |
|------|------|
| 新项首次学习 | interval = 1 天，repetitions = 1 |
| 第二次记住 | interval = 6 天 |
| 第三次记住 | interval × ease_factor |
| 忘记 (quality < 3) | interval 重置为 1 天 |
| 掌握判定 | repetions ≥ 5 且 interval ≥ 21 天 |

---

## 技术栈

| 层 | 技术 | 产物 |
|-----|------|------|
| **学习引擎** | C (C11) | `libwordcard.so` |
| **KV Cache** | C (C11) | `libcache.so` |
| **文本渲染** | C++17 + HarfBuzz + Cairo | `libtxt2png.so` |
| **电子书解析** | C++17 + libmobi/MuPDF | `libmobiparse.so` / `libpdfparse.so` |
| **业务逻辑** | Python (ctypes) | `engine.py` |
| **CLI** | Python | `cli.py` |
| **REST API** | Python (FastAPI) | `api.py` |

---

## 版本历史

| 版本 | 时间 | 核心变更 |
|------|------|----------|
| v1.0 | 2024 | 文章翻译工具 |
| v2.0 | 2025-05 | C + Python 架构，SM-2 单词记忆 |
| v3.0 | 2025-05 | 通用学习引擎 |
| **v4.0** | **2026-07** | **纯 C 重构 + 电子书导入 + CLI/API + 卡片图片** |

*最后更新: 2026-07-26*
