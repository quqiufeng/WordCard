# WordCard v3.0 — 基于记忆曲线的通用学习引擎

> 从"单词记忆系统"进化为"任意知识的间隔重复引擎"
>
> **核心定位**：SM-2 记忆曲线不只能背单词——法条、口语话题、数学公式、医学术语，一切需要记忆的内容都可以被追踪、被优化、被记住。

---

## 项目定位

WordCard 是一个**极简架构**的**通用间隔重复学习系统**：

- **C 语言内存数据库**：自定义数据结构，全部驻留内存，结构体直写磁盘 bin 文件，零依赖零配置
- **SM-2 间隔重复算法**：科学记忆曲线，追踪每个用户对每个知识点的记忆衰减
- **多维度掌握度**：不只记录"会不会"，还记录"认不认识""会不会复现""听不听得懂""表达准不准"
- **内容类型无关**：英语单词、司法法条、雅思口语、GRE数学、医学术语——同一套引擎
- **智能推荐**：根据你的薄弱环节，自动推荐最适合的学习模式
- **8 种学习模式**：闪卡/选择/填空/默写/听辨/表达/配对/速闪
- **语音集成**：SenseVoice 语音识别 + Piper 语音合成（可选）
- **FastAPI HTTP 服务**：一行命令启动，钉钉机器人可直接对接

---

## 通用学习场景

同一份代码，支持任意备考需求：

| 考试/领域 | 内容类型 | question 示例 | answer 示例 |
|-----------|---------|--------------|------------|
| **英语词汇** | `CAT_ENGLISH_VOCAB` | `abandon` | `放弃；抛弃` |
| **司法考试** | `CAT_LEGAL_LAW` | `【刑法】第266条 诈骗罪` | `诈骗公私财物，数额较大的，处三年以下有期徒刑...` |
| **雅思口语** | `CAT_IELTS_SPEAKING` | `Describe a memorable journey` | `高分框架：1. 背景 2. 经过 3. 感受...` |
| **雅思写作** | `CAT_IELTS_WRITING` | `讨论远程办公的利弊` | `论点结构：利-节省通勤/工作生活平衡；弊-团队协作困难...` |
| **GRE 语文** | `CAT_GRE_VERBAL` | `abstemious` | `adj. 节制的，节俭的（根：abs-离开 + temetum-烈酒）` |
| **GRE 数学** | `CAT_GRE_QUANT` | `若 x² + 3x - 10 = 0，求 x` | `x = 2 或 x = -5（因式分解：(x+5)(x-2)=0）` |
| **医学术语** | `CAT_MEDICAL_TERM` | `Myocardial infarction` | `心肌梗死（病理：冠状动脉急性闭塞→心肌缺血坏死）` |
| **注册会计师** | `CAT_CPA` | `企业合并中商誉的确认条件` | `合并成本 > 可辨认净资产公允价值份额时确认...` |
| **自定义** | `CAT_CUSTOM` | `任意问题` | `任意答案` |

---

## 目录结构

```
WordCard/
├── src/                           # C 核心库
│   ├── wordcard.h                 # 通用数据结构定义 + API 声明
│   ├── wordcard.c                 # 数据库引擎（内存管理 + 磁盘IO + 哈希索引）
│   ├── modes.c                    # 智能推荐算法
│   ├── test_sm2.c                 # 单元测试（11个测试全部通过）
│   ├── Makefile                   # 编译脚本
│   └── libwordcard.so             # 编译后的共享库
│
├── api.py                         # FastAPI HTTP 服务 + Python ctypes FFI 绑定
├── import_article.py              # 通用导入工具（res/*.txt → 提取内容 → 写入C DB）
├── voice/                         # 语音系统集成
│   └── __init__.py                # ASR (SenseVoice) + TTS (Piper) + 发音评分
│
├── data/                          # 数据目录
│   └── wordcard.db                # 二进制数据库文件（结构体直写，启动时载入内存）
│
├── design.md                      # 完整架构设计文档
├── task.md                        # 开发进度跟踪
│
├── llm.py                         # LLM 内容生成引擎（已有，复用）
├── card.py                        # 卡片渲染 MD/PNG/PDF（已有，复用）
├── build_llama_cpp.sh             # llama.cpp CUDA 编译脚本（RTX 3080 优化版）
├── run_qwen3.sh                   # llama.cpp 服务启动脚本
├── res/                           # 原始学习材料目录
│   └── *.txt
└── output/                        # 输出目录
    └── *.{md,png,pdf}
```

---

## 核心架构

```
┌─────────────────────────────────────────────────────────────┐
│              用户选择学习内容（任意领域）                        │
│  (英语词汇 / 司法法条 / 雅思口语 / GRE数学 / 医学术语...)        │
└──────────────────────┬──────────────────────────────────────┘
                       │ 内容导入
                       ▼
┌─────────────────────────────────────────────────────────────┐
│              C 核心库 (libwordcard.so) v3.0                   │
│  ├─ 通用学习项 item_entry_t（question/answer/explanation/      │
│  │                         hint/category/tags）               │
│  ├─ SM-2 间隔重复算法（与用户×学习项绑定）                     │
│  ├─ 多维度掌握度（recognition/recall/spelling/listening/       │
│  │               pronunciation/usage + overall 加权）          │
│  ├─ 文件持久化 v3（结构体直写磁盘 bin，启动时 fread 载入）     │
│  ├─ 运行时哈希索引（question/id/source/user/mastery/stat 六种）│
│  └─ 到期复习排序索引（惰性重建，二分查找）                     │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│              8 种记忆模式 (modes.c)                           │
│  闪卡 → 选择 → 填空 → 默写 → 听辨 → 表达 → 配对 → 速闪        │
│  （算法根据掌握度自动推荐最适合的模式）                        │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│              Python FastAPI (api.py)                          │
│  ├─ RESTful API（用户/学习项/复习/统计）                      │
│  ├─ ctypes FFI 绑定（Python ↔ C 共享库）                      │
│  ├─ 异步保存（后台线程每60秒自动保存 + 退出时保存）            │
│  └─ 语音端点（ASR/TTS/发音评分，可选）                        │
└──────────────────────┬──────────────────────────────────────┘
                       │ HTTP API
                       ▼
┌─────────────────────────────────────────────────────────────┐
│              前端入口（钉钉机器人 / 浏览器 / 其他客户端）       │
└─────────────────────────────────────────────────────────────┘
```

---

## 核心功能详解

### 1. C 内存数据库引擎（通用版）

**文件**：`src/wordcard.c` + `src/wordcard.h`

- **通用学习项 `item_entry_t`**：6 个字段承载任意知识
  - `question[512]` — 问题/题目/提示（如单词、法条编号、口语话题）
  - `answer[512]` — 答案/释义/解答（如中文翻译、法条内容、回答框架）
  - `explanation[1024]` — 详细解析/例句/案例/记忆技巧
  - `hint[256]` — 提示/音标/关键词/公式
  - `category` — 内容类型（`CAT_ENGLISH_VOCAB`、`CAT_LEGAL_LAW` 等）
  - `tags[128]` — 标签（逗号分隔，如 `"english,vocab,cet4"`）

- **文件格式 v3**：64 字节文件头（魔数 `"WCD\x03"`）+ 按顺序排列的定长结构体数组
- **零拷贝加载**：启动时 `fread` 直接读入内存数组，运行时全内存操作，性能最大化
- **原子写入**：保存时先写 `.tmp` 临时文件，再 `rename` 覆盖原文件，保证数据完整性
- **运行时哈希索引**：`question → index`、`item_id → index`、`(user_id,item_id) → mastery_index` 等六种哈希表，查询 O(1)
- **动态扩容**：哈希表在 load_factor > 0.75 时自动 2 倍扩容
- **到期复习索引**：`mastery_due_sorted` 按 `next_review` 排序，惰性重建，二分查找
- **线程安全**：全局 `pthread_mutex` 锁保护所有写操作 + Python 层 `threading.Lock`

```bash
cd src
make clean && make          # 编译 libwordcard.so
make test                    # 运行单元测试（11个测试全部通过）
```

### 2. SM-2 间隔重复算法

**文件**：`src/wordcard.c`（`wc_sm2_update` 函数）

标准 SuperMemo-2 算法实现，与内容类型无关：

| 场景 | 行为 |
|------|------|
| 新项首次学习 | interval = 1 天，repetitions = 1 |
| 第二次记住 | interval = 6 天 |
| 第三次记住 | interval = interval × ease_factor |
| 忘记（Again）| interval 重置为 1 天，repetitions 重置为 0 |
| 难度调整 | ease_factor 根据评级动态调整（最低 1.3） |
| 掌握判定 | repetitions ≥ 5 且 interval ≥ 21 天 → 已掌握 |

**验证**：单元测试已验证与 Anki 的 SM-2 实现行为一致。

### 3. 多维度掌握度系统

**文件**：`src/wordcard.c`（`wc_update_mastery_dimension` + `wc_recalc_overall`）

每个学习项对每个用户追踪 6 个维度：

| 维度 | 权重 | 含义 | 英语场景 | 司法场景 |
|------|------|------|----------|----------|
| recognition | 25% | 看到问题→知答案 | 看英文知中文 | 看到法条编号知内容 |
| recall | 20% | 看到提示→想答案 | 看中文想英文 | 看到案例知适用法条 |
| spelling | 20% | 默写/复现准确度 | 拼写单词 | 默写条文原文 |
| listening | 15% | 听辨/理解 | 听音辨词 | 听案情分析要点 |
| pronunciation | 10% | 表达/发音评分 | ASR 朗读 | 口头陈述法条（可选） |
| usage | 10% | 应用/实践 | 语境造句 | 案例分析判断 |
| **overall** | 加权平均 | **综合掌握度** | — | — |

更新规则：正确 +10 分，错误 -15 分，滑动平均，clamp 到 0-100。

### 4. 智能推荐算法

**文件**：`src/modes.c`（`wc_recommend_mode` 函数）

根据掌握度自动推荐学习模式（与内容类型无关）：

```
新项（total_reviews == 0）
    → 闪卡模式（建立初步认知）

连续忘记 3 次以上（forget_count >= 3）
    → 闪卡模式 + 标记困难

识别高(>80) 但复现差(<50)
    → 默写模式

能认(>70) 但表达差(<60)
    → 表达模式（ASR评分，可选）

能认(>70) 但听辨差(<50)
    → 听辨模式

全面掌握(overall>85, streak>=5)
    → 速闪模式（维持记忆）

SM-2 到期复习
    → 根据最弱维度自动选模式

默认
    → 选择题模式
```

### 5. FastAPI HTTP 服务

**文件**：`api.py`

```bash
python api.py
# 启动后访问 http://localhost:8000/docs 查看自动生成的 API 文档
```

核心端点：

| 端点 | 方法 | 说明 |
|------|------|------|
| `/api/v1/user/register` | POST | 注册用户（dingtalk_uid） |
| `/api/v1/user/{id}/stats` | GET | 用户学习统计 |
| `/api/v1/user/{id}/daily-queue` | GET | 今日学习队列（自动推荐模式） |
| `/api/v1/item` | POST | 添加学习项 |
| `/api/v1/item/{id}` | GET | 查询学习项 |
| `/api/v1/item/search/{question}` | GET | 按问题文本搜索 |
| `/api/v1/study/review` | POST | 提交复习结果（更新SM-2+掌握度） |
| `/api/v1/mastery/{user_id}/{item_id}` | GET | 查询掌握度 |
| `/api/v1/db/save` | POST | 强制保存数据库 |

Python 封装类 `WordCardDB`：
- `add_item()` / `find_item()` — 学习项操作
- `add_source()` — 添加内容载体
- `create_user()` / `find_user()` — 用户管理
- `review()` — 提交复习（自动更新 SM-2 + 多维度掌握度 + 每日统计）
- `get_daily_queue()` — 获取今日学习队列
- `get_mastery()` — 查询掌握度详情
- 后台自动保存线程（每 60 秒 + 程序退出时）

### 6. 语音系统集成（可选）

**文件**：`voice/__init__.py`

- **ASR（语音识别）**：封装 SenseVoice 共享库，支持 amr/wav/mp3 → 文本
- **TTS（语音合成）**：封装 Piper 共享库，文本 → WAV 音频
- **发音评分**：对比用户读音（ASR 结果）和标准文本的相似度，返回 0-100 分

语音模块为可选依赖，未安装时系统仍可正常运行（仅朗读/发音功能不可用）。

```python
from voice import get_asr, get_tts, pronunciation_score

# 语音识别
text = get_asr().recognize("/tmp/audio.wav")

# 语音合成
path = get_tts().synthesize("Hello world", "/tmp/output.wav")

# 发音评分
score = pronunciation_score(user_text="hello", standard_text="hello world")
```

### 7. 内容导入工具

**文件**：`import_article.py`

自动提取学习材料中的内容并导入数据库：

```bash
# 导入单篇文章（自动调用 LLM 生成翻译和词汇）
python import_article.py res/solar_system.txt

# 导入所有文章
python import_article.py --all

# 指定数据库路径
python import_article.py --db data/wordcard.db res/*.txt
```

处理流程：
1. 读取 `res/*.txt` 学习材料
2. 调用 `llm.py` 生成结构化内容（问题/答案/解析）
3. 创建 `content_source_t` 载体记录
4. 写入 C 数据库（`item_entry_t` + 掌握度记录）

---

## 快速开始

### 1. 编译 C 核心库

```bash
cd src
make clean && make
# 生成 libwordcard.so
```

### 2. 运行单元测试

```bash
cd src
make test
# 预期输出：11 tests passed, 0 failed
```

### 3. 导入学习内容

```bash
# 英语词汇示例
python import_article.py --all

# 也可以直接调用 Python API 添加任意内容
python -c "
from api import get_db
db = get_db()

# 添加英语单词
db.add_item('abandon', '放弃', category=1)

# 添加司法法条
db.add_item(
    '【刑法】第266条 诈骗罪',
    '诈骗公私财物，数额较大的，处三年以下有期徒刑...',
    category=2,
    tags='刑法,法条'
)

# 添加雅思口语话题
db.add_item(
    'Describe a memorable journey',
    '高分框架：1. 背景 2. 经过 3. 感受...',
    category=3,
    tags='ielts,speaking'
)

# 添加 GRE 数学题
db.add_item(
    '若 x² + 3x - 10 = 0，求 x',
    'x = 2 或 x = -5（因式分解：(x+5)(x-2)=0）',
    category=6,
    tags='gre,math,quadratic'
)

db.save()
print('导入完成！')
"
```

### 4. 启动 HTTP API 服务

```bash
python api.py
# 服务启动后访问 http://localhost:8000/docs
```

### 5. API 测试

```bash
# 注册用户
curl -X POST http://localhost:8000/api/v1/user/register \
  -H "Content-Type: application/json" \
  -d '{"dingtalk_uid": "user001", "name": "TestUser"}'
# {"user_id": 1, "dingtalk_uid": "user001"}

# 添加学习项（英语）
curl -X POST http://localhost:8000/api/v1/item \
  -H "Content-Type: application/json" \
  -d '{
    "question": "ephemeral",
    "answer": "短暂的，朝生暮死的",
    "explanation": "例句：Fashions are ephemeral.",
    "category": 1,
    "tags": "english,vocab"
  }'

# 添加学习项（司法）
curl -X POST http://localhost:8000/api/v1/item \
  -H "Content-Type: application/json" \
  -d '{
    "question": "【民法典】第1165条",
    "answer": "行为人因过错侵害他人民事权益造成损害的，应当承担侵权责任...",
    "category": 2,
    "tags": "civil,law"
  }'

# 获取今日学习队列
curl http://localhost:8000/api/v1/user/1/daily-queue
# {"user_id": 1, "count": 10, "queue": [...]}

# 提交复习结果
curl -X POST http://localhost:8000/api/v1/study/review \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": 1,
    "item_id": 1,
    "quality": 4,
    "dimension": "r",
    "correct": true
  }'
# {"success": true, "mastery": {...}, "recommended_next_mode": "choice"}
```

---

## 原有功能（保持不变）

### llm.py —— LLM 内容生成引擎

读取 `res/*.txt`，调用本地 llama.cpp API 生成结构化学习内容。

```bash
# 启动 llama.cpp 服务
setsid ./run_qwen3.sh > /tmp/qwen3_8b.log 2>&1 &

# 生成翻译和词汇
python llm.py solar_system.txt
# 输出：output/solar_system_trans.txt
```

### card.py —— 卡片渲染

将 `_trans.txt` 渲染为 MD/PNG/PDF 三种格式。

```bash
python card.py solar_system_trans.txt
# 输出：output/solar_system.md / .png / .pdf
```

---

## 安装依赖

### 1. 系统依赖

```bash
# Python 依赖
pip install fastapi uvicorn pydantic pillow fpdf requests

# C 编译环境（gcc + make）
sudo apt-get install build-essential cmake

# C++ wrapper 编译依赖（libmobi + mupdf）
sudo apt-get install -y \
  autoconf automake libtool pkg-config \
  libxml2-dev zlib1g-dev \
  liblcms2-dev libjpeg-dev libopenjp2-7-dev \
  libjbig2dec0-dev libpng-dev libfreetype6-dev \
  libharfbuzz-dev libmujs-dev
```

### 2. 编译 llama.cpp（GPU 加速版，可选）

使用项目自带的 RTX 3080 优化编译脚本：

```bash
# 赋予执行权限
chmod +x build_llama_cpp.sh

# 运行编译脚本（自动检测 GPU 架构、启用 Flash Attention、CUDA Graphs 等优化）
./build_llama_cpp.sh
```

**脚本功能**：
- 自动检测 CUDA 环境和 GPU 型号（RTX 3080/3090/4090 等）
- 自动设置正确的 CUDA 架构（sm_86 等）
- 启用 Flash Attention 内核优化
- 启用 CUDA Graphs 加速小 batch 推理
- 启用 mmq kernels（消费级显卡小 batch 更快）
- 编译 llama-server（API 服务）、llama-cli、llama-llava-cli（多模态）

**编译完成后**：
- 可执行文件位于 `$HOME/llama.cpp/build/bin/`
- API 服务：`llama-server`
- 命令行工具：`llama-cli`
- 多模态工具：`llama-llava-cli`

### 3. 编译电子书解析库（C++ Wrapper → .so）

WordCard 集成了 **libmobi**（MOBI/AZW3）和 **MuPDF**（PDF/EPUB），通过 C++ Wrapper 编译为共享库，Python 通过 ctypes FFI 调用。

**架构设计**：与 `voice/` 模块一致（SenseVoice/Piper wrapper 模式）

```
ebook file (.mobi/.azw3/.pdf/.epub)
    │
    ▼
┌─────────────────────────────────────────┐
│  C++ Wrapper（importer/wrappers/）        │
│  · mobi_wrapper.cpp → libmobiparse.so   │
│  · pdf_wrapper.cpp  → libpdfparse.so    │
│  extern "C" 暴露接口，供 Python ctypes 调用 │
└────────────────────┬────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────┐
│  Python FFI（importer/__init__.py）       │
│  · MobiParser() / PdfParser()           │
│  · parse_mobi() / parse_pdf()           │
│  · 上下文管理器 with ... as parser      │
└─────────────────────────────────────────┘
```

**源码位置**：
- `libmobi` → `/opt/libmobi`（GitHub: `bfabiszewski/libmobi`）
- `MuPDF` → `/opt/mupdf`（GitHub: `ArtifexSoftware/mupdf`）

**编译步骤**：

```bash
# 1. 安装编译依赖（已在上方系统依赖中包含）
# 2. 编译 libmobi（静态库）
cd /opt/libmobi
./autogen.sh && ./configure && make -j$(nproc)

# 3. 编译 MuPDF（静态库，需 -fPIC 以链接到 .so）
cd /opt/mupdf
# 关键子模块：thirdparty/lcms2, thirdparty/openjpeg, thirdparty/mujs
git submodule update --init thirdparty/lcms2 thirdparty/openjpeg thirdparty/mujs
make XCFLAGS="-fPIC" -j$(nproc) libs

# 4. 编译 Wrapper → .so
cd /opt/WordCard/importer/wrappers
make clean && make -j$(nproc)

# 输出：
#   importer/libs/libmobiparse.so  (MOBI/AZW3)
#   importer/libs/libpdfparse.so   (PDF/EPUB)
```

**Python 调用**：

```python
from importer import parse_mobi, parse_pdf, parse_epub

# MOBI / AZW3
result = parse_mobi("book.azw3")
print(result["title"], result["author"])
print(result["text"][:500])

# PDF
result = parse_pdf("doc.pdf")
print(f"Pages: {result['page_count']}")
print(result["text"][:500])

# EPUB（复用 MuPDF 解析能力）
result = parse_epub("book.epub")
print(f"Pages: {result['page_count']}")
print(result["text"][:500])
```

**已验证支持的格式**：

| 格式 | 扩展名 | 解析库 | 状态 |
|------|--------|--------|------|
| MOBI | `.mobi` | libmobi | ✅ |
| AZW3 | `.azw3` | libmobi | ✅ |
| PDF | `.pdf` | MuPDF | ✅ |
| EPUB | `.epub` | MuPDF | ✅ |

**迁移特性**：
- `.db` 数据库文件是单一自包含二进制（结构体直写，无指针，无外部依赖）
- `libmobiparse.so` 和 `libpdfparse.so` 已静态链接原生库，运行时无需源码
- 复制 `data/wordcard.db` + `importer/libs/*.so` 到新服务器即可直接使用



### 4. 下载模型（可选）

```bash
# 下载 Qwen3-8B 模型（约 5.5GB）
mkdir -p /opt/image
wget -O /opt/image/Qwen3-8B-Q5_K_M.gguf \
  "https://huggingface.co/Qwen/Qwen3-8B-GGUF/resolve/main/qwen3-8b-q5_k_m.gguf"
```

---

## 运行环境

| 组件 | 要求 |
|------|------|
| Python | 3.8+ |
| C 编译器 | gcc 9.0+ |
| 系统 | Linux（推荐）/ WSL / macOS |
| GPU | 8GB+ 显存（用于 llama.cpp，核心系统纯 CPU 运行） |

---

## 技术亮点

| 特性 | 实现方式 | 性能 |
|------|----------|------|
| **通用学习引擎** | 单一 `item_entry_t` 承载任意知识 | 零拷贝，无序列化开销 |
| **内存数据库** | C 结构体数组 + 6种哈希索引 | 单次查询 < 1ms |
| **动态哈希扩容** | load_factor > 0.75 时自动 2 倍扩容 | 持续高效，无性能衰减 |
| **到期复习索引** | 惰性重建的排序数组 + 二分查找 | 避免全表扫描 |
| **磁盘持久化 v3** | 结构体直写 bin 文件（`WCD\x03`） | 10万项加载 < 1秒 |
| **SM-2 算法** | 标准 SuperMemo-2 | 与 Anki 行为一致 |
| **多维度掌握度** | 6维度滑动平均 + 加权 overall | 精准定位薄弱环节 |
| **智能推荐** | 7条规则决策树 | 毫秒级响应 |
| **语音系统** | SenseVoice ASR + Piper TTS | 本地推理，零网络延迟 |
| **零配置部署** | `python api.py` 一行启动 | 开箱即用 |

---

## 版本历史

| 版本 | 时间 | 核心变更 |
|------|------|----------|
| v1.0 | 2024 | 文章翻译工具（llm.py + card.py） |
| v2.0 | 2025-05 | C + Python 架构，SM-2 单词记忆系统（`WCD\x02`） |
| **v3.0** | **2025-05** | **通用学习引擎（`WCD\x03`），支持任意知识类型** |

---

## 项目状态

**当前版本：v3.0.0 — 通用学习引擎（已可用）**

✅ **已完成**：
- C 内存数据库引擎（v3 通用数据结构，加载/保存/哈希索引/线程安全）
- 6 种运行时哈希索引 + 动态扩容机制
- 到期复习排序索引（惰性重建，避免全表扫描）
- SM-2 间隔重复算法（标准实现 + 单元测试）
- 多维度掌握度系统（6维度 + 加权 overall）
- 智能推荐算法（7条规则覆盖所有场景）
- FastAPI HTTP 服务（用户/学习项/复习/统计端点）
- 语音系统集成（ASR/TTS/发音评分框架，可选）
- 内容导入工具（文章→通用学习项）
- C 单元测试（11个测试全部通过）

📋 **待扩展**（欢迎贡献）：
- 司法考试题库批量导入（PDF/Word 解析）
- 雅思口语话题模板库
- GRE 数学公式卡片
- 医学 Anki 牌组迁移工具
- 钉钉机器人多场景回调
- 性能基准测试（10万项/百万项）

---

## 文件清单

| 文件 | 说明 | 状态 |
|------|------|------|
| `design.md` | 完整架构设计文档 | ✅ |
| `src/wordcard.h` | C 头文件（通用数据结构 + API声明） | ✅ v3 |
| `src/wordcard.c` | C 核心库（数据库 + SM-2 + IO + 哈希索引） | ✅ v3 |
| `src/modes.c` | 智能推荐算法（7条规则） | ✅ v3 |
| `src/test_sm2.c` | C 单元测试（11个测试） | ✅ v3 |
| `src/Makefile` | 编译脚本 | ✅ |
| `api.py` | Python FastAPI + ctypes FFI | ✅ v3 |
| `import_article.py` | 通用内容导入工具 | ✅ v3 |
| `voice/__init__.py` | 语音系统集成 | ✅ |
| `llm.py` | LLM 内容生成引擎 | ✅ |
| `card.py` | 卡片渲染 MD/PNG/PDF | ✅ |
| `task.md` | 开发进度跟踪 | ✅ |

---

*最后更新: 2026-05-15（v3.0 通用学习引擎）*
