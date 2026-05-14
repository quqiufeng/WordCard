# WordCard

英文文章转中英双语学习卡片工具，支持生成 PNG/PDF/MD 三种格式。

## 目录结构

```
WordCard/
├── llm.py                 # 调用 llama.cpp + qwen9b 生成翻译（从 res 读取）
├── card.py                # 生成卡片（输出到 output）
├── run_qwen3.sh           # llama.cpp + qwen9b 启动脚本
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

### 翻译流程: llama.cpp + qwen9b 本地推理

```bash
# 1. 启动 llama.cpp 服务
./run_qwen3.sh

# 2. 处理 res 目录下所有 txt 文件
python llm.py

# 处理指定的文件
python llm.py article1.txt article2.txt
```

### 生成卡片

```bash
# 处理 output 目录下所有 _trans.txt 文件
python card.py

# 处理指定的文件
python card.py article1_trans.txt article2_trans.txt
```

## llama.cpp + qwen9b 配置

- **模型**: qwen9b (Qwen3-8B-Q5_K_M.gguf)
- **模型路径**: `/opt/image/Qwen3-8B-Q5_K_M.gguf`
- **启动脚本**: `./run_qwen3.sh`
- **API 地址**: `http://127.0.0.1:11434/v1` (OpenAI 兼容)

### 启动命令

```bash
# 方式1: 使用提供的启动脚本
./run_qwen3.sh

# 方式2: 手动启动
$HOME/llama.cpp/build/bin/llama-server \
  -m /opt/image/Qwen3-8B-Q5_K_M.gguf \
  --host 0.0.0.0 --port 11434 \
  -ngl 33 -c 131072 \
  --flash-attn on
```

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
| `generate_content(text)` | 调用 llama.cpp API，发送提示词获取翻译内容 |
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
res/*.txt → llm.py (llama.cpp + qwen9b) → output/*_trans.txt → card.py → output/*.{md,png,pdf}
```

### 翻译方案对比

| 特性 | llama.cpp + qwen9b |
|------|--------------------|
| 部署方式 | 本地 llama.cpp 服务 |
| 硬件要求 | 8GB+ 显存 / 16GB+ 内存 |
| 翻译质量 | 优秀 |
| 速度 | 快 (GPU 加速) |
| 网络依赖 | 无 |
| 语言支持 | 多语言 |

### 核心模块

```
llm.py
└── generate_content()     # 调用 llama.cpp API (OpenAI 兼容)
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

### 基础依赖（llama.cpp 方案）

```bash
pip install pillow fpdf requests
```

### llama.cpp 环境

```bash
# 克隆并编译 llama.cpp
git clone https://github.com/ggerganov/llama.cpp
cd llama.cpp
cmake -B build -DGGML_CUDA=ON  # NVIDIA GPU
cmake --build build --config Release

# 下载 qwen9b 模型 (Qwen3-8B-GGUF)
# 模型文件: Qwen3-8B-Q5_K_M.gguf
# 放置到: /opt/image/Qwen3-8B-Q5_K_M.gguf
```

**PDF 依赖**:
```bash
pip install fpdf
```

## 运行环境

### llama.cpp + qwen9b 方案

- Python 3.8+
- llama.cpp (编译好的 llama-server)
- Qwen3-8B-Q5_K_M.gguf 模型文件
- 8GB+ GPU 显存 或 16GB+ 内存
- Linux / Windows / macOS
