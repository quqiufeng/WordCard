# WordCard UI 层技术架构

> Flutter Desktop (Linux) + Yaru + dart:ffi / StaticPy native  
> 文档版本: v2.0 — 2026-11-02

---

## 一、目标

为 WordCard 提供 Ubuntu 桌面界面，覆盖「导入 → 记忆 → 听写 → 阅读 → 口语 → 导出卡片」流程。

UI 只负责展示与交互；学习算法、解析、翻译、OCR、TTS、卡片渲染都在 native 层。

---

## 二、技术栈

| 项 | 选型 |
|---|---|
| 框架 | Flutter Desktop / Linux |
| UI | Yaru + Material 3 |
| 设计 | Kami（暖米底 + 油墨蓝 + 仓耳今楷） |
| 引擎 | `dart:ffi` → `libwordcard.so` |
| 内容能力 | `native/staticpy/*` 原生二进制 |
| LLM | 本地 `llama-server` (Hunyuan-MT-7B) |
| OCR | `wc_ocr` + PP-OCRv4 + onnxruntime |
| 语音 | `wc_voice`（TTS/ASR） |
| 打包 | `gui/flutter/package.sh` → tar.gz |

---

## 三、页面结构

```
StudyPage（可折叠侧栏）
 ├─ 首页 DashboardPage：统计 / 任务完成度 / 遗忘曲线
 ├─ 任务 TasksPage：任务列表、翻页词表、学习/听写/删除
 ├─ 导入 ImportPage：词表 / 电子书 / 粘贴 / 图片 OCR
 ├─ 阅读 ReaderPage → BilingualReaderScreen
 └─ 口语 SpeechPage

路由页
 ├─ ReviewScreen（记忆）
 └─ DictationExamPage（听写）
```

导航：

- `nav.home` / `nav.tasks` / `nav.import` / `nav.reader` / `nav.speech`
- `nav.toggle` 收起/展开侧栏
- `app.quit` 退出

---

## 四、状态与数据

- 数据库：`data/wordcard.db`
- 书库：`/opt/books/<slug>/chapters/*/page_*.md`
- 阅读进度：`data/reader_progress.json`
- 译文缓存：`data/reader_cache.jsonl`
- 词表：`data/wordlists/*.tsv`
- TTS 缓存：`~/.cache/wordcard/tts/`
- 卡片导出：`~/<hash>.png` 或 `~/<hash>_N.png`

---

## 五、FFI / Native 通道

`lib/ffi/wordcard.dart` 封装 `wc_*` ABI：

- 生命周期：`wc_db_init` / `wc_load_db` / `wc_save_db` / `wc_db_free`
- 用户/队列：`wc_create_user` / `wc_find_user` / `wc_generate_daily_queue`
- 学习项：`wc_add_item` / `wc_find_item_by_question` / `wc_update_item_explanation`
- 复习：`wc_sm2_update` / `wc_recalc_overall`
- 任务：`wc_delete_items_by_tag` / `wc_item_count` / `wc_item_id_at`

Native 进程：

- `wc_ebook_json`：电子书 → JSON
- `wc_text`：选词 + 上下文
- `wc_define`：ECDICT 查词
- `wc_translate`：LLM 翻译
- `wc_ocr`：图片 OCR
- `wc_voice`：TTS / ASR / 录音
- `wc_card_txt`：双语卡片
- `wc_card_cn`：全中文卡片
- `wc_build_wordlists`：ECDICT 词表生成

路径统一由 `NativePaths` 查找；C 侧支持 `WORDCARD_ROOT` / `WORDCARD_FONT`。

---

## 六、双语阅读

```
扫描 /opt/books → 章节 → 段落解析
  → 英文原文 + 缓存译文
  → 点词查词 / 加入读书任务
  → 导出卡片
```

- 章节解析在 isolate 中执行，避免阻塞 UI
- 目录支持拖动调宽、隐藏、恢复
- 正文字体：仓耳今楷 / Maple Mono 可切换
- 字号：`A-` / `A+`，范围 12–36
- TOC 页按锚点层级还原缩进，紧凑排版
- 翻译按需生成，句级优先对齐

---

## 七、卡片导出

阅读页图片按钮：

- 全中文 → `wc_card_cn`
  - 不翻译、不提取词汇
  - 固定 `780×1200`
  - 按实际排版高度分页
  - 短内容单图，长内容多图
- 双语/英文 → `wc_card_txt`
  - 提取词汇表
  - 提取例句
  - 优先复用已有译文
  - 缺失时调用 `wc_translate`
- 文件名用内容 hash；导出前清理同 hash 旧分片

---

## 八、口语

```
SpeechPage
  → 开始对话 / 打字 / 录音
  → wc_voice record → asr
  → llama-server (OpenAI 兼容 /v1/chat/completions)
  → wc_voice TTS
```

- 录音当前固定 4 秒
- 本地 `llama-server` 自动拉起
- 英文回复自动补中文译文
- TTS 按文本缓存，重复朗读不重新加载模型

---

## 九、字体

| 用途 | 字体 |
|---|---|
| 界面/单词 | Maple Mono NF CN |
| 卡片/正文 | 仓耳今楷 02 |

```dart
abstract final class AppFonts {
  static const mapleMono = 'MapleMonoNF';
  static const tsangerJinKai = 'TsangerJinKai';
}
```

---

## 十、自动化 API

Unix socket + JSON Lines：`/tmp/wordcard-automation.sock`

| 请求 | 说明 |
|---|---|
| `{"cmd":"list"}` | actions / functions |
| `{"cmd":"state"}` | 当前页面/统计/任务/复习 |
| `{"cmd":"click","id":"..."}` | 触发按钮 |
| `{"cmd":"call","fn":"...","args":{}}` | 调用函数 |

主要函数：

- `nav.goto`
- `task.list` / `task.words` / `task.study` / `task.dictate` / `task.delete` / `task.create`
- `import.wordlist` / `import.ebook` / `import.image`
- `reader.list` / `reader.open` / `reader.chapter` / `reader.translate`
- `reader.toggleChapters` / `reader.setFontSize` / `reader.setFont` / `reader.setChapterWidth`
- `reader.exportCard` → `{files, chinese, words, examples}`
- `reader.castToKindle` → 推送整本书到 Kindle 阅读器并打开
- `speech.start` / `speech.stop` / `speech.userText` / `speech.play` / `speech.state`
- `app.quit`

---

## 十一、构建 / 测试 / 打包

```bash
cd gui/flutter
flutter analyze
flutter test
flutter build linux --release
bash package.sh
```

产物：

- `build/linux/x64/release/bundle/wordcard`
- `dist/wordcard-linux-x64.tar.gz`

运行：

```bash
./run.sh
# 或解包后
./run-wordcard.sh
```

---

## 十二、目录

```
gui/flutter/lib/
├── main.dart / app.dart
├── native_paths.dart
├── reader_library.dart
├── reader_export_utils.dart
├── reader_card_export.dart
├── memo_service.dart / tts.dart / llama_service.dart
├── voice_chat_service.dart
├── ebook_import.dart / paste_import.dart / ocr_import.dart / wordlist.dart
├── ffi/
├── state/
├── automation/
├── pages/
└── widgets/
```

---

## 十三、规范

- Dart 提交前 `flutter analyze` 必须无问题
- 章节解析/大文件处理避免主 isolate 同步 IO
- 导出/翻译/OCR/TTS 统一走 native，不新增 Python
- 卡片导出固定高度，内容按实际排版分页
- 窗口关闭按钮 = 最小化
- 文档与代码同步更新
