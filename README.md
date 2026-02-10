# WordCard Translator

使用 LM Studio + Qwen2.5-7B-Instruct 模型，一键生成英文学习卡片（PNG/PDF/MD）。

## LM Studio 配置

- **模型**: [mradermacher/Qwen2.5-7B-Instruct-GGUF](https://huggingface.co/mradermacher/Qwen2.5-7B-Instruct-GGUF)
- **量化版本**: `Qwen2.5-7B-Instruct.Q5_K_M.gguf`
- **模型路径**: `E:\model\mradermacher\Qwen2.5-7B-Instruct-GGUF`
- **服务器**: `http://192.168.124.3:11434/v1` (OpenAI 兼容 API)

---

英文文章自动翻译工具，生成中英双语学习材料。

## 功能特点

- **全文翻译**：使用 NLLB-200 模型将英文翻译成中文
- **词汇提取**：自动从文章提取长度>5的有价值词汇（过滤常用词）
- **句子提取**：提取包含关键词的精彩句子
- **双语对照**：生成 EN-CH 双语区块，英文中文逐段对照
- **卡片生成**：一键生成 PNG、PDF、MD 三种格式的学习卡片

## 安装依赖

```bash
pip install pillow fpdf requests
```

**LM Studio 要求**：
- LM Studio 服务器运行中
- 模型已加载：`qwen2.5-7b-instruct`

## 使用方法

```bash
# 1. 调用 LM Studio 生成翻译 txt
python llm.py article.txt [标题]

# 2. 生成卡片（处理 output 下所有 txt）
python article_card.py
```

## 输出示例

查看 `output/` 目录：

| 文件 | 说明 |
|------|------|
| `article_trans.txt` | 翻译后的格式化文件 |
| `article_trans.md` | Markdown 格式 |
| `article_trans.png` | PNG 图片卡片 |
| `article_trans.pdf` | PDF 文档卡片 |

## 配置说明

### llm.py 参数

```python
LLMS_HOST = "http://192.168.124.3:11434/v1"  # LM Studio 地址
MODEL = "qwen2.5-7b-instruct"  # 模型名称
```

### article_card.py 参数

```python
CARD_WIDTH = 780  # PNG图片宽度(像素)
EN_WRAP = 52  # 英文换行字符数
ZH_WRAP = 25  # 中文换行字符数
```

## 技术架构

### 核心模块

```
llm.py                 # 调用 LM Studio，生成翻译 txt
└── generate_content() # 调用 LM Studio API
└── parse_content()    # 解析 AI 输出

article_card.py
├── load_txt()         # 解析 _trans.txt 文件
├── create_md()        # 生成 Markdown 文件
├── create_png()       # 生成 PNG 图片卡片
└── create_pdf()       # 生成 PDF 文档卡片
```

### 处理流程

```
输入文件 (article.txt)
         │
         ▼
┌─────────────────────┐
│ llm.py              │  调用 LM Studio
└─────────┬───────────┘
          ▼
┌─────────────────────┐
│ 1. 读取文章         │
└─────────┬───────────┘
          ▼
┌─────────────────────┐
│ 2. LM Studio 生成内容 │  一次性提示词
└─────────┬───────────┘
          ▼
┌─────────────────────┐
│ 3. 解析输出         │  分离4个区块
└─────────┬───────────┘
          ▼
    output/xxx_trans.txt
         │
         ▼
┌─────────────────────┐
│ article_card.py     │  生成卡片
└─────────────────────┘
```
generate_cards.py      # 统一入口，一键完成所有步骤
├── generate_content()  # 调用 LM Studio API
├── parse_one_shot()   # 解析 AI 输出
└── create_cards()     # 调用 article_card.py

article_card.py
├── load_txt()         # 解析 _parsed.txt 文件
├── create_md()        # 生成 Markdown 文件
├── create_png()       # 生成 PNG 图片卡片
└── create_pdf()       # 生成 PDF 文档卡片
```

### 处理流程

```
输入文件 (article.txt)
         │
         ▼
┌─────────────────────┐
│ generate_cards.py   │  一键脚本
└─────────┬───────────┘
          ▼
┌─────────────────────┐
│ 1. 读取文章         │
└─────────┬───────────┘
          ▼
┌─────────────────────┐
│ 2. LM Studio 生成内容  │  一次性提示词
└─────────┬───────────┘
          ▼
┌─────────────────────┐
│ 3. 解析输出         │  分离4个区块
└─────────┬───────────┘
          ▼
┌─────────────────────┐
│ 4. 格式化           │  转换格式
└─────────┬───────────┘
          ▼
┌─────────────────────┐
│ 5. 生成卡片         │  PNG / PDF / MD
└─────────────────────┘
```

### 关键技术

- **LLM 提示词**：
  - 一次性生成 4 个部分（原文/双语/词汇/句子）
  - 结构化输出，格式清晰
  - 温度 0.3，保证一致性

- **格式解析**：
  - 按 `【章节名】` 标记分割内容
  - 处理跨行文本
  - 提取编号词汇和句子

## 输出格式

### TXT 文件

```txt
TITLE: 文章标题

ORIGINAL:
英文原文（按65字符换行）

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

### MD 文件

Markdown 格式，词汇表双列显示：

```markdown
# 标题

> 生成时间: 2025-02-09

---

## 原文

英文原文...

---

## 中英双语

英文段落...
中文翻译...

---

## 词汇表

| 英文                中文        | 英文              中文     |
| planets             星球       | asteroids         小行星   |
| system              系统       | particles         颗粒     |

---

## 精彩句子

> **English sentence.**
>
> 中文翻译。
```

## 文件说明

| 文件 | 说明 |
|------|------|
| `llm.py` | LM Studio API 调用 + 格式解析 |
| `article_card.py` | 卡片生成（PNG/PDF/MD） |
| `translate_nllb.py` | NLLB 翻译脚本（保留备用） |
| `solar_system.txt` | 示例英文文章 |
| `output/` | 生成的卡片文件目录 |
| `*.ttf` | 中英文字体文件 |

## 运行环境

- Python 3.8+
- LM Studio (Windows)
- 16GB+ 内存
- Windows

## 字体说明

项目包含以下字体文件：

- `LXGWWenKai-Regular.ttf` - 中文常规字体（PDF使用）
- `LXGWWenKaiMono-Bold.ttf` - 中文粗体（PNG标题使用）
- `JetBrainsMono-Bold.ttf` - 英文粗体

字体文件需放在项目根目录。
