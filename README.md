# WordCard

英文文章转中英双语学习卡片工具，支持生成 PNG/PDF/MD 三种格式。

## 目录结构

```
WordCard/
├── llm.py                 # 调用 LM Studio 生成翻译（从 res 读取）
├── card.py                # 生成卡片（输出到 output）
├── translate_nllb.py      # NLLB 翻译脚本（保留备用）
├── res/                   # 原始文章目录
│   └── *.txt              # 英文文章文件
├── output/                # 输出目录
│   ├── *_trans.txt        # 翻译后的格式化文件
│   ├── *.md               # Markdown 格式
│   ├── *.png              # PNG 图片卡片
│   └── *.pdf              # PDF 文档卡片
└── *.ttf                  # 中英文字体文件
```

## 使用方法

### 方式1: LM Studio 在线翻译（推荐）

```bash
# 处理 res 目录下所有 txt 文件
python llm.py

# 处理指定的文件（文件名从 res 目录读取）
python llm.py article1.txt article2.txt
```

### 方式2: NLLB 离线翻译（备用）

```bash
# 处理单个文件
python translate_nllb.py res/article.txt
```

### 生成卡片

```bash
# 处理 output 目录下所有 _trans.txt 文件
python card.py

# 处理指定的文件
python card.py article1_trans.txt article2_trans.txt
```

## LM Studio 配置

- **模型**: [Qwen2.5-7B-Instruct-GGUF](https://huggingface.co/mradermacher/Qwen2.5-7B-Instruct-GGUF)
- **量化版本**: `Qwen2.5-7B-Instruct.Q5_K_M.gguf`
- **模型路径**: `E:\model\mradermacher\Qwen2.5-7B-Instruct-GGUF`
- **服务器**: `http://192.168.124.3:11434/v1` (OpenAI 兼容 API)

### Qwen2.5-7B 模型介绍

**官方链接**: https://huggingface.co/Qwen/Qwen2.5-7B-Instruct

**模型架构**:
- 类型: Decoder-only Transformer
- 参数规模: 7B (70亿参数)
- 上下文长度: 131,072 tokens
- 语言: 多语言（含中英文）

**性能特点**:
- 优秀的中英文理解与生成能力
- 指令遵循能力强
- 适合内容生成和翻译任务
- GGUF 量化版在消费级硬件上推理速度快

## NLLB 翻译模型 (离线备用)

虽然当前默认使用 LM Studio，但 NLLB 模型作为离线翻译方案仍然保留。

- **模型**: [NLLB-200 3.3B](https://huggingface.co/facebook/nllb-200-distilled-3.3B)
- **模型路径**: `E:/cuda/nllb-200-3.3B-ct2-float16`
- **格式**: CTranslate2 量化 (FP16)
- **加速**: CUDA GPU 推理

### NLLB 模型介绍

**官方链接**: https://huggingface.co/facebook/nllb-200-distilled-3.3B

**模型架构**:
- 类型: Encoder-Decoder Transformer
- 参数规模: 3.3B (33亿参数，蒸馏版)
- 语言支持: 200 种语言
- 训练数据: 多语言平行语料

**性能特点**:
- **支持 200 种语言**，包括罕见语言
- 翻译质量高，尤其是英中互译
- **离线运行**，无需网络
- CTranslate2 量化加速，GPU 推理

**使用场景**:
- 网络不可用时
- 需要批量离线翻译
- 对翻译质量有极高要求

### NLLB 配置要求

```bash
# 安装依赖
pip install ctranslate2 transformers torch pillow fpdf tqdm
```

**硬件要求**:
- CUDA GPU (8GB+ 显存)
- 或 CPU 模式（较慢）

## 字体文件

项目使用以下中文字体，均需放在项目根目录：

| 文件 | 用途 |
|------|------|
| `LXGWWenKai-Regular.ttf` | PDF 常规字体 |
| `LXGWWenKaiMono-Bold.ttf` | PNG 标题和正文 |
| `JetBrainsMono-Bold.ttf` | 英文标题 |

## 脚本函数说明

### llm.py

| 函数 | 说明 |
|------|------|
| `generate_content(text)` | 调用 LM Studio API，发送提示词获取翻译内容 |
| `parse_content(content)` | 解析 AI 返回的结构化内容，分离4个区块 |
| `format_for_article_card(sections, title)` | 转换为 card.py 期望的格式 |
| `main()` | 主入口，支持批量处理 |

### card.py

| 函数 | 说明 |
|------|------|
| `load_txt(txt_file)` | 读取并解析 _trans.txt 文件，按区块分割 |
| `create_md(sections, output_path)` | 生成 Markdown 文件，词汇表双列显示 |
| `create_png(sections, output_path)` | 生成 PNG 图片卡片，自动计算高度 |
| `create_pdf(sections, output_path)` | 生成 PDF 文档，多页面布局 |
| `main()` | 主入口，批量处理文件 |

### translate_nllb.py (备用)

| 函数 | 说明 |
|------|------|
| `load_translator()` | 加载 CTranslate2 NLLB 翻译模型 |
| `load_article(txt_path)` | 读取原始文章，解析标题和段落 |
| `translate_text()` | 翻译单个文本 |
| `translate_batch()` | 批量翻译文本列表 |
| `extract_vocabulary()` | 提取文章词汇（长度>5，过滤常用词） |
| `extract_sentences()` | 提取包含词汇的精彩句子 |

## 输出格式

### 输入格式 (res/*.txt)

```txt
文章标题
第一段内容...
第二段内容...
...
```

### 中间格式 (output/*_trans.txt)

```txt
TITLE: 文章标题
---
ORIGINAL:
英文原文...
---
EN-CH:
英文段落1
中文翻译1
英文段落2
中文翻译2
...
---
VOCABULARY:
1. vocabulary|中文翻译
2. ...
---
SENTENCES:
1. English sentence.
中文翻译。
2. ...
```

### 输出格式

| 格式 | 说明 |
|------|------|
| MD | Markdown 格式，词汇表双列显示，支持 GitHub 渲染 |
| PNG | 图片卡片，固定宽度 780px，高度自适应 |
| PDF | 文档卡片，多页面布局，每页一个章节 |

## 技术架构

### 处理流程

```
# 方式1: LM Studio 在线翻译（推荐）
res/*.txt → llm.py → output/*_trans.txt → card.py → output/*.{md,png,pdf}

# 方式2: NLLB 离线翻译（备用）
res/*.txt → translate_nllb.py → output/*_trans.txt → card.py → output/*.{md,png,pdf}
```

### 翻译方案对比

| 特性 | LM Studio (Qwen2.5) | NLLB-200 |
|------|---------------------|----------|
| 部署方式 | 本地 API 服务 | 本地模型文件 |
| 硬件要求 | 16GB+ 内存 | 8GB+ GPU 显存 |
| 翻译质量 | 优秀 | 高 |
| 速度 | 快 | 依赖 GPU |
| 网络依赖 | 无 | 无 |
| 语言支持 | 多语言 | 200 种语言 |

### 核心模块

```
llm.py
└── generate_content()     # 调用 LM Studio API
└── parse_content()        # 解析 AI 输出的4个区块
└── format_for_article_card()  # 格式化输出

card.py
├── load_txt()             # 解析 _trans.txt
├── create_md()            # 生成 Markdown
├── create_png()           # 生成 PNG 图片
└── create_pdf()           # 生成 PDF 文档
```

### 关键技术

**LLM 提示词工程**:
- 一次性生成 4 个部分（原文/双语/词汇/句子）
- 使用 `【章节名】` 标记结构化输出
- 温度 0.3，保证输出一致性

**文本换行算法**:
- 英文: 按字符数，在单词边界断行
- 中文: 按字符数截断
- 中英文宽度对齐（中文字符=2，英文=1）

**卡片布局**:
- PNG: 动态计算高度，支持长文章
- PDF: 多页面，每页独立章节
- MD: 表格布局，词汇表双列显示

## 安装依赖

### 基础依赖（LM Studio 方案）

```bash
pip install pillow fpdf requests
```

### NLLB 离线翻译依赖

```bash
pip install ctranslate2 transformers torch tqdm
```

**PDF 依赖**:
```bash
pip install fpdf
```

## 运行环境

### LM Studio 方案

- Python 3.8+
- LM Studio (Windows)
- 16GB+ 内存
- Windows

### NLLB 离线方案

- Python 3.8+
- CUDA 11.x + cuDNN 8.x
- 8GB+ GPU 显存
- Windows / Linux
