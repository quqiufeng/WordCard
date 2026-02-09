# WordCard Translator

> **TODO**: 用 Ollama + Qwen:7B 替换 NLLB-200，改善翻译质量
> 
> 方案：
> 1. 新增 `ollama_translate.py` - 调用 Ollama API 翻译
> 2. 修改 `translate.py` - 支持切换翻译后端（NLLB/Ollama）
> 3. Ollama 配置：`ollama run qwen:7b`
> 4. API 地址：`http://localhost:11434/api/generate`
> 5. 提示词模板：`Translate to Chinese: {text}`

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
pip install ctranslate2 transformers tqdm torch pillow fpdf requests
```

**模型要求**：

**方案A - NLLB（当前）**：
- 需要下载 NLLB-200 3.3B 模型（FP16格式）
- 模型路径：`E:/cuda/nllb-200-3.3B-ct2-float16`
- 支持 CUDA GPU 加速

**方案B - Ollama Qwen（待实现）**：
- 安装 Ollama：`winget install Ollama.Ollama`
- 拉取模型：`ollama run qwen:7b`
- 无需 CUDA，本地 CPU 推理

## 使用方法

### 1. 翻译文章

```bash
python translate.py article.txt
```

### 2. 生成卡片

```bash
python article_card.py article_trans.txt
```

## 输出示例

查看 `output/` 目录：

| 文件 | 说明 |
|------|------|
| `solar_system_trans.md` | Markdown 格式 |
| `solar_system_trans.png` | PNG 图片卡片 |
| `solar_system_trans.pdf` | PDF 文档卡片 |

## 配置说明

### translate.py 参数

```python
MODEL_DIR = "E:/cuda/nllb-200-3.3B-ct2-float16"  # 模型路径
EN_WRAP = 65  # 英文每行字符数
ZH_WRAP = 40  # 中文每行字符数
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
translate.py
├── load_translator()      # 加载 NLLB 翻译模型
├── load_article()         # 读取原始文章，解析段落
├── translate_text()        # 翻译单个文本
├── translate_batch()       # 批量翻译（带进度条）
├── wrap_english()         # 英文按字符数换行（单词边界断行）
├── wrap_chinese()          # 中文按字符数换行
├── extract_vocabulary()    # 提取文章词汇（过滤常用词）
├── extract_sentences()     # 提取精彩句子
└── create_trans_file()     # 生成输出文件

article_card.py
├── load_txt()             # 解析 _trans.txt 文件
├── create_md()            # 生成 Markdown 文件
├── create_png()           # 生成 PNG 图片卡片
└── create_pdf()           # 生成 PDF 文档卡片
```

### 处理流程

```
输入文件 (article.txt)
    │
    ▼
┌─────────────────┐
│ 1. 读取文章      │  解析标题、段落
└────────┬────────┘
         ▼
┌─────────────────┐
│ 2. 翻译全文      │  NLLB-200 模型翻译
└────────┬────────┘
         ▼
┌─────────────────┐
│ 3. 提取词汇      │  长度>5，过滤常用词
└────────┬────────┘
         ▼
┌─────────────────┐
│ 4. 翻译词汇      │  逐词翻译
└────────┬────────┘
         ▼
┌─────────────────┐
│ 5. 提取句子      │  关键词筛选
└────────┬────────┘
         ▼
┌─────────────────┐
│ 6. 翻译句子      │  逗号拆分翻译
└────────┬────────┘
         ▼
┌─────────────────┐
│ 7. 生成输出      │  格式化为 _trans.txt
└────────┬────────┘
         ▼
    _trans.txt
         ▼
┌─────────────────┐
│ 8. 生成卡片      │  PNG / PDF / MD
└─────────────────┘
```

### 关键技术

- **翻译模型**：Meta NLLB-200 (No Language Left Behind)
  - 支持200种语言
  - CTranslate2 量化加速
  - CUDA GPU 推理

- **词汇提取算法**：
  ```
  1. 正则匹配提取所有单词
  2. 停用词表过滤（约120个常用词）
  3. 计算加权分数：score = freq × log(len)
     - freq: 词频，出现次数越多越重要
     - len: 词长，长词更有学习价值
     - log: 对数函数，平滑分数差异
  4. 按分数降序排序，选取 Top 20
  ```

- **句子提取算法**：
  ```
  1. 按 [.!?] 标点分割句子
  2. 长度筛选：80 < 字符数 < 250
  3. 匹配包含词汇表词汇的句子
  4. 每个词汇最多匹配1个句子
  5. 最多返回20个句子
  ```

- **文本换行**：
  - 英文：按字符数，在单词边界断行
  - 中文：按字符数截断
  - 中英文宽度对齐

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
| `translate.py` | 主翻译脚本 |
| `article_card.py` | 卡片生成脚本（PNG/PDF/MD） |
| `solar_system.txt` | 示例英文文章 |
| `solar_system_trans.txt` | 翻译后的双语文件 |
| `output/` | 生成的卡片文件目录 |
| `*.ttf` | 中英文字体文件 |

## 运行环境

- Python 3.8+
- CUDA 11.x + cuDNN 8.x
- 8GB+ GPU 显存
- Windows/Linux

## 字体说明

项目包含以下字体文件：

- `LXGWWenKai-Regular.ttf` - 中文常规字体（PDF使用）
- `LXGWWenKaiMono-Bold.ttf` - 中文粗体（PNG标题使用）
- `JetBrainsMono-Bold.ttf` - 英文粗体

字体文件需放在项目根目录。
