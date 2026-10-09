# WordCard — 电子书「读前预习」词汇学习系统

> 解析电子书 → 挑出最值得学的词（带上下文）→ SM-2 记住 → 顺畅读完不卡顿

---

## 设计目标

**把一本原版书读懂、读顺，不再卡顿。**

核心思路：读之前，先把这本书里「**你不认识、又在书中高频**」的词学会——它们每读几页就撞一次，不学就一直卡。

```
电子书(PDF/MOBI/AZW3/EPUB/MD)
   │ ① 解析 → 完整正文，按章节切分
   ▼
   │ ② 选词 → 通用词频(Zipf) + 书内词频 + 散布度 + 学习者水平
   │          在「覆盖率(能读通)」与「学习价值(值得学)」间平衡
   ▼
   │ ③ 材料 → 中英双语释义 + 含词的双语段落 + 双语句例 + 英文朗读 + 卡片图片
   ▼
   │ ④ 记忆 → 导入 SM-2 间隔重复引擎，到期自动复习
   ▼
   ⑤ 复读 → 词都记住了，原文读起来就顺了
```

## 核心特性

- **C 核心引擎**：零依赖 SM-2 算法 + 哈希索引 + 结构体直写磁盘
- **智能选词**：`libwordpick.so` 内置 6 万词频表 + 词形还原，偏态难度曲线 + 覆盖率加权
- **完整解析**：PDF/MOBI/AZW3/EPUB/MD → 清洗后的完整正文，按章节切分
- **双语材料**：本地 LLM 翻译 + Kokoro 语音 + HarfBuzz/Cairo 卡片
- **双接口**：CLI 终端复习 + FastAPI REST 接口
- **全本地**：无外部数据库/API 依赖

---

## 架构

```
用户
 ├── CLI (cli.py) ──────── 终端交互复习
 ├── API (api.py) ──────── FastAPI REST (port 8000)
 ├── 卡片图片 ───────────── txt2png Canvas → PNG
 └── 语音 ──────────────── ASR (SenseVoice) + TTS (Kokoro)

Python 层
 ├── engine.py    ────────── SM-2 ctypes 绑定 → libwordcard.so
 ├── importer.py  ────────── 电子书解析 → 词汇提取 → DB
 ├── txt2png.py   ────────── 画布 API → libtxt2png.so
 ├── voice.py     ────────── ASR/TTS → libvoice_engine.so
 ├── sound.py     ────────── 音频录制/播放/转换
 └── generate_card.py ────── 多格式输出 (MD/PNG/PDF)

C/C++ 层
 ├── libwordcard.so     ───── SM-2 学习引擎 (wordcard.c + modes.c)
 ├── libcache.so        ───── KV Cache (14 个模块)
 ├── libtxt2png.so      ───── HarfBuzz + Knuth-Plass + Cairo
 ├── libwordpick.so     ───── 智能词汇选择 (基于通用词频 zipf)
 ├── libqwen3_asr.so    ───── Qwen3-ASR (ONNX + llama.cpp)
 │                         来源: /opt/friday/agent/qwen3_asr_engine.cpp
 ├── importer/libs/
 │   ├── libmobiparse.so ──── MOBI/AZW3 解析 (libmobi)
 │   └── libpdfparse.so ──── PDF/EPUB 解析 (MuPDF)
 └── voice/wrappers/
     ├── piper_wrapper.cpp ─── TTS (需编译)
     ├── sensevoice_wrapper.cpp ─ ASR 备选
     └── qwen3_asr_bridge.*  ─── Qwen3-ASR C ABI
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
├── voice.py                     # ASR/TTS (Qwen3-ASR / SenseVoice / Piper)
├── sound.py                     # 音频录制/播放/转换
├── generate_card.py             # 多格式卡片输出
│
├── importer/
│   ├── wrappers/                # C++ 电子书解析
│   │   ├── mobi_wrapper.cpp     # MOBI/AZW3 (libmobi)
│   │   ├── pdf_wrapper.cpp      # PDF (MuPDF)
│   │   ├── epub_wrapper.cpp     # EPUB (libzip + libxml2)
│   │   └── Makefile
│   └── libs/                    # 编译产物
│       ├── libmobiparse.so
│       └── libpdfparse.so
│
├── voice/                       # 语音引擎
│   ├── libs/libqwen3_asr.so     # Qwen3-ASR (来自 /opt/friday)
│   ├── wrappers/
│   │   ├── qwen3_asr_bridge.h/cpp  # C ABI 桥
│   │   ├── sensevoice_wrapper.cpp  # SenseVoice 封装
│   │   └── piper_wrapper.cpp       # Piper TTS 封装
│   └── Makefile
│
├── data/                        # 数据库目录
│   └── wordcard.db
│
├── output/                      # 卡片输出
│
├── design.md                    # 架构文档
├── README.md                    # 本文档
└── todolist.md                    # 应用方向
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

## 词汇卡生成（vocab_card）

为选出的单词生成学习卡片（PNG + MD），含：

- **中英双语释义**（本地 LLM 生成）
- **含该词的段落**（原文 + 中文翻译）
- **数条含该词的例句**（原文 + 中文翻译）

```bash
# 需要本地 llama-server（自动拉起，Qwen3-14B）
python3 vocab_card.py book.azw3 --max 30 --level 4 --sent 3 --out output/
```

译义/翻译由 `translate.py` 调用本地 `llama-server`（OpenAI 兼容 API）完成，零外部 API 依赖。

---

## 智能词汇选择（wordpick）

从电子书正文挑选「最值得学习」的单词，用于 SM-2 卡片：

```
score = U(zipf) · (0.35 + 0.65·rel) · spread · prod · lenpen
  U      : 偏态难度曲线（简单侧陡衰减，生僻侧长尾）
  rel    : 书内词频 log 归一
  spread : 书内散布度（跨 chunk）
  prod   : 构词能产性分级（高/低后缀）
  lenpen : 过长词惩罚
```

| 特性 | 说明 |
|------|------|
| 难度轴 | 通用词频 Zipf（内置 6 万词表），CEFR A1–C2 预设 |
| 词形还原 | 内置 1.6 万条 lemma 表 + 规则回退 |
| 过滤 | 噪声 / CapRatio 专有名词 / 停用词 / 基础词 |
| 模式 | 0=学习价值，1=覆盖率 |
| 评估 | `eval_wordpick.py`：Precision@K / NDCG@K / 覆盖率曲线 |

```python
import importer
# 学习价值模式（默认），可选 CEFR 等级
words = importer.extract_words(text, max_words=50, level=4)   # B2
# 覆盖率模式
words = importer.extract_words(text, max_words=50, mode=1)
```

---

## 技术栈

| 层 | 技术 | 来源 | 产物 |
|-----|------|------|------|
| **学习引擎** | C (C11) | 本项目 | `libwordcard.so` |
| **KV Cache** | C (C11) | `/opt/my_db` | `libcache.so` |
| **文本渲染** | C++17 + HarfBuzz + Cairo | `/opt/txt2png` | `libtxt2png.so` |
| **ASR 引擎** | C++17 + ONNX + llama.cpp | `/opt/friday/agent/` | `libqwen3_asr.so` |
| **ASR 备选** | subprocess | `/opt/friday/shell/` | SenseVoice |
| **TTS** | C++ Piper | `voice/wrappers/` | 需编译 |
| **电子书解析** | C++17 + libmobi/MuPDF | `importer/wrappers/` | `libmobiparse.so` / `libpdfparse.so` |
| **词汇选择** | C++17 | 本项目 | `libwordpick.so` |
| **业务逻辑** | Python ctypes | 本项目 | `engine.py` |
| **CLI / API** | Python | 本项目 | `cli.py` / `api.py` |

---

## 版本历史

| 版本 | 时间 | 核心变更 |
|------|------|----------|
| v1.0 | 2024 | 文章翻译工具 |
| v2.0 | 2025-05 | C + Python 架构，SM-2 单词记忆 |
| v3.0 | 2025-05 | 通用学习引擎 |
| **v4.0** | **2026-07** | **纯 C 重构 + 电子书导入 + CLI/API + 卡片图片** |

*最后更新: 2026-07-26*
