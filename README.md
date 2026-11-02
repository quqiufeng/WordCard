# WordCard — 电子书「读前预习」词汇学习系统

> 解析电子书 → 选出最值得学的词（带上下文）→ SM-2 记忆 → 双语阅读 → 卡片/口语复习

---

## 设计目标

把一本原版书读懂、读顺：先学会「不认识、又在书中高频」的词，再进入阅读，减少反复卡顿。

```
电子书(PDF/MOBI/AZW3/EPUB/MD)
  → 解析/分章
  → 选词(zipf + 书内词频 + 散布度 + 水平)
  → 释义/例句/翻译/卡片
  → SM-2 复习
  → 双语阅读
```

## 当前架构

```
Flutter UI (gui/flutter)
  ├─ dart:ffi ───────────── libwordcard.so        SM-2 引擎
  ├─ native 进程 ────────── native/staticpy/*     解析/选词/翻译/OCR/TTS/卡片
  └─ llama-server(:8081) ── 本地翻译/口语模型

C/C++ 底层
  ├─ src/                  libwordcard.so / libwordpick.so / libtxt2png.so
  ├─ importer/libs/        MOBI/PDF/EPUB 解析
  ├─ voice/libs/           voice_engine + OCR
  └─ native/src/           StaticPy 入口对应的 C 源码
```

运行时不依赖 Python。`native/staticpy/ffi.static.py` 只是 StaticPy 源码输入。

## 主要能力

- **学习引擎**：C 实现 SM-2、哈希索引、结构体直写磁盘
- **桌面 UI**：Flutter + Yaru，首页/任务/记忆/听写/导入/阅读/口语
- **阅读器**：`/opt/books` 书架、目录拖动/隐藏、字号/字体切换、TOC 清洗、段间翻译
- **导入**：考试词表、电子书、粘贴词表、图片 OCR
- **卡片导出**：直接保存到 `~`，内容 hash 命名；双语页提取词汇/例句，全中文走独立 `wc_card_cn`，固定 `780×1200` 分页
- **语音**：`wc_voice` 录音/ASR/TTS；本地 `llama-server` 生成口语回复
- **本地优先**：翻译/朗读/卡片均本地完成，DeepSeek 仅可选

## 构建与运行

```bash
# 完整构建：C 核心 + StaticPy + Flutter release
gui/flutter/build.sh

# 运行
gui/flutter/run.sh

# 打包 Linux x64
gui/flutter/package.sh
# → dist/wordcard-linux-x64.tar.gz
```

单独构建 native：

```bash
bash native/staticpy/build.sh
```

## 常用 native 入口

```bash
native/staticpy/ebook_json/wc_ebook_json <book> <out.json>
native/staticpy/card_cn/wc_card_cn <title> <content.txt> <out.png> 1200
native/staticpy/card_txt/wc_card_txt <input.txt> <out.png> <out.md>
native/staticpy/define/wc_define <word> --dict data/wordlists/cet4.tsv
native/staticpy/voice/wc_voice tts <text> <out.wav> 3
native/staticpy/voice/wc_voice asr <wav> en
```

## 测试与检查

```bash
cd gui/flutter
flutter analyze
flutter test
flutter build linux --release
```

## 数据与模型

- 电子书解析结果：`/opt/books/<slug>/chapters/*/page_*.md`
- 数据库：`data/wordcard.db`
- 词表：`data/wordlists/*.tsv`
- 字体：`LXGWWenKai-Regular.ttf`（可用 `WORDCARD_FONT` 覆盖）
- 本地模型默认：`/data/models/Hunyuan-MT-7B-Q4_K_M.gguf`（可用 `WC_LLM_MODEL` 覆盖）
- OCR：`models/ocr/` + onnxruntime 1.26（可用 `WC_ORT_LIB` 覆盖）

## 目录

```
src/                 C 核心/选词/渲染
native/staticpy/     StaticPy 构建入口与 wrapper
native/src/          抽出的 C 源码
importer/            MOBI/PDF/EPUB 解析
voice/               语音引擎与 OCR 运行库
gui/flutter/         Flutter 桌面应用
data/                数据库/词表/缓存
```

## 已知限制

- OCR 依赖 onnxruntime 1.26；不同机器需设置 `WC_ORT_LIB`
- 口语录音当前固定 4 秒，未接 VAD
- 复杂 EPUB 的正文/目录排版仍依赖源文件质量
- `bilingual_reader.dart` 仍在继续拆分中

*最后更新: 2026-11-02*
