# WordCard UI 层技术架构

> Flutter Desktop (Linux) + Yaru + dart:ffi → `libwordcard.so`
> 文档版本: v1.0 — 2026-10-11

---

## 一、目标

为 WordCard 提供运行于 **Ubuntu 桌面**的图形界面，复用现有 C 核心引擎
（SM-2 / 语音）与 Python 处理管道（解析 / 选词 / 翻译 / OCR），
覆盖「导入 → 记忆 → 听写」全流程，兼顾**成人读原版书**与**小学生每周听写**两类场景。

UI 层**只负责展示与交互**，不重写学习算法；解析、翻译、查词复用 Python 脚本，
记忆与数据全部来自 C 共享库，经 `dart:ffi` 直连。

---

## 二、技术栈

| 项 | 选型 | 说明 |
|----|------|------|
| 框架 | **Flutter Desktop**（Linux Stable） | 同一套代码可扩移动端 |
| 语言 | **Dart**（健全空安全） | |
| Linux 宿主 | **GTK+ 3**（Flutter 官方嵌入器） | `flutter create` 生成 `linux/` 运行器 |
| UI 框架 | **Yaru（主）+ Material 3（辅）** | 融合 Ubuntu 桌面生态 |
| 设计语言 | **Kami**（暖米纸感 + 油墨蓝单强调 + 衬线） | `github.com/tw93/Kami`；见第四节 |
| 窗口 | **YaruWindowTitleBar**（关闭=最小化） | 不叠加 `window_manager`/托盘插件（会与 Yaru 冲突崩溃） |
| 字体 | **Maple Mono NF CN**（界面/自动化）+ **仓耳今楷 02**（卡片衬线） | 见第六节 |
| 数据通道 | **dart:ffi** 直连本地 `.so` | 见第五节 |
| LLM | 本地 llama.cpp：**Hunyuan-MT-7B**（翻译，默认）+ Qwen3-4B（兜底） | 见第七节 |
| OCR | **PP-OCRv4**（libocr_simple.so + onnxruntime 1.26） | 见第七节 |
| 打包 | **snapcraft → Snap** | Ubuntu 官方推荐分发格式 |

---

## 三、页面与分层

```
┌───────────────────────────────────────────────────────────────┐
│ 展示层 (Flutter / Yaru)                                        │
│  主界面 StudyPage（可折叠侧栏）：首页 / 任务 / 导入            │
│   · 首页 DashboardPage   记忆数据面板 + 任务完成度柱状图 + 遗忘曲线│
│   · 任务 TasksPage       任务列表（学习/听写/删除）+ 翻页词表      │
│   · 导入 ImportPage      词表 / 电子书 / 粘贴 / 图片OCR           │
│  路由页：ReviewScreen（记忆）、DictationExamPage（听写考试）      │
├───────────────────────────────────────────────────────────────┤
│ 状态层 (Dart, ChangeNotifier)                                  │
│  StudySession：队列 / 当前卡 / 翻转 / SM-2 提交 / 统计          │
├───────────────────────────────────────────────────────────────┤
│ FFI / 服务层                                                    │
│  lib/ffi/wordcard.dart   wc_* ABI + 结构体布局                  │
│  tts.dart / memo_service.dart / ebook_import.dart /            │
│  paste_import.dart / ocr_import.dart / wordlist.dart           │
├───────────────────────────────────────────────────────────────┤
│ C 核心 + Python 管道                                            │
│  libwordcard.so  SM-2 引擎 / 哈希索引 / 增删改查                │
│  tools/*.py      解析、选词、ECDICT 查词、LLM 翻译、OCR、TTS   │
└───────────────────────────────────────────────────────────────┘
```

**页面导航**：侧栏四项 `首页 / 任务 / 导入 / 阅读`
（`nav.home / nav.tasks / nav.import / nav.reader`）。
「记忆」不再是固定页，而是从 **首页「开始今日记忆」** 或 **任务行「学习」** 打开的
`ReviewScreen` 路由；「听写」打开 `DictationExamPage` 路由。

### 记忆（复习）闭环

```
首页/任务 → StudySession.start() / startItems(ids)
          → wc_generate_daily_queue(user, now)
          → FlashCard 显示 → 翻卡（跑 TTS 读词）
          → 不会(空格, q=1) / 记得(→, q=4) → wc_sm2_update
          → 到期排程；结束时 wc_save_db
```

### 双语阅读闭环

```
阅读书架（扫描 /opt/books/<slug>/chapters/NN-.../page_*.md）
  → 章节正文清洗 + 段落还原（reader_library.dart）
  → 段间对照：英文原文；点「译」或「翻译本章」→ memo_server（Hunyuan-MT-7B）
  → 译文写入 data/reader_cache.jsonl，下次打开直接显示
  → 点段落中的单词 → ECDICT / 词形还原 / LLM 兜底 → 「加入读书任务」
  → tags = book:<书名>，与其它导入共用同一 SM-2 队列
```

- 译文按需生成，不预翻全书；`MemoService` 常驻进程逐段处理，界面按结果流式回填。
- 阅读进度存 `data/reader_progress.json`（每本书的章节索引）。
- 书库根目录默认 `/opt/books`，可用环境变量 `BOOK_MD_ROOT` 覆盖；导入复用
  `/opt/my_db/tools/import_book`（`--skip-vectors`，只阅读不需要向量索引）。

### 任务模型（在 items 的 tags 之上分的一层）

- 每个**导入来源** = 一个任务：`book:<书名>` / `dict:<词表名>` / `custom:<名称>`。
- 任务页：一行显示名称、类型、词数；操作 **学习 / 听写 / 删除**；点进去**翻页**看词表。
- 删除任务 = `wc_delete_items_by_tag`（删学习项及其掌握度，重建索引）。

---

## 四、Kami 设计语言

参考 `github.com/tw93/Kami`「好内容，值得好版面」，UI 遵循：

- **暖米纸感底 `#F5F4ED`**（不用纯白）；卡片面 `#FBFAF4` + **细线边框**。
- **单一强调色：油墨蓝 `#1B365D`**（目标词、朗读图标、进度）；不用多色。
- **衬线字体**贯穿卡片正文（仓耳今楷）。
- **字号层级 + 大量留白**，分区用**细线**分隔，**无渐变 / 无阴影 / 无 3D**。
- 语义色（中国色）保留淡雅作用，不喧宾夺主：正确 `#2E8B57`、错误 `#D92121`。

```dart
abstract final class Kami {
  static const parchment = Color(0xFFF5F4ED); // 底
  static const surface   = Color(0xFFFBFAF4); // 卡片
  static const inkBlue   = Color(0xFF1B365D); // 强调（唯一）
  static const ink       = Color(0xFF2B2A26); // 正文
  static const muted     = Color(0xFF6B665C); // 次要
  static const hairline  = Color(0xFFE4DFD3); // 细线
}
```

主题仍用 Yaru 接管系统色（浅/深色跟随系统），Kami 用于业务与卡片排版。

---

## 五、数据通道（dart:ffi）

UI 直接 `dart:ffi` 调 `libwordcard.so`，不经过 Python / HTTP。

```dart
final lib = DynamicLibrary.open('libwordcard.so');
final wcLoadDb = lib.lookupFunction<
    Pointer<Void> Function(Pointer<Utf8>),
    Pointer<Void> Function(Pointer<Utf8>)>('wc_load_db');
```

主要 C ABI（`src/wordcard.h`）：

| 函数 | 用途 |
|------|------|
| `wc_db_init` / `wc_load_db` / `wc_save_db` / `wc_db_free` | 生命周期 |
| `wc_create_user` / `wc_find_user` | 用户 |
| `wc_generate_daily_queue` / `wc_get_due_items` / `wc_get_new_items` | 队列 |
| `wc_find_item_by_id` / `wc_find_item_by_question` | 卡片详情 |
| `wc_add_item` | 新增学习项 |
| `wc_update_item_answer` / `wc_update_item_explanation` | 异步回填释义 / 段落译文 |
| `wc_get_or_create_mastery` / `wc_find_mastery` | 掌握度 |
| `wc_sm2_update` / `wc_recalc_overall` | 复习提交 |
| `wc_item_count` / `wc_item_id_at` | 遍历学习项（任务/统计） |
| `wc_delete_items_by_tag` | 删除某任务 |
| `wc_now` / `wc_version_string` | 工具 |

约定：C 层字符串统一 `char*`（UTF-8）；结构体在 Dart 用 `final class ... extends Struct`
精确对齐；返回指针所有权归 C 层，只读、不手动 `free`。

---

## 六、字体

| 用途 | 字体 | 文件 | 字重 |
|------|------|------|------|
| 界面/单词/自动化 | **Maple Mono NF CN**（等宽、含 CJK） | `MapleMono-NF-CN-{Regular,Medium,SemiBold,Bold}.ttf` | 400/500/600/700 |
| 卡片正文（衬线） | **仓耳今楷 02**（Kami 默认中文衬线） | `TsangerJinKai02-W{04,05}.ttf` | 400/500 |

```dart
abstract final class AppFonts {
  static const mapleMono = 'MapleMonoNF';
  static const tsangerJinKai = 'TsangerJinKai';
}
```

- 全局界面用 Maple Mono；**卡片**（单词/释义/段落/例句）用仓耳今楷。
- 仓耳今楷（`TsangerJinKai02`）个人非商用免费，取自 Kami 的 CDN；
  下载见 `skills/kami/scripts/ensure-fonts.sh`（源：`cdn.jsdelivr.net/gh/tw93/Kami@main/assets/fonts/`）。
- 体积较大（Maple ~79MB + 仓耳 ~38MB），后续可用 `fonttools` 子集化。

---

## 七、导入与内容管道（复用 Python）

**统一原则：来源不同，记忆相同** —— 所有导入都经 `wc_add_item` 写入同一张 items 表，
仅 `tags` 区分来源，复习端不区分来源。

| 入口 | 动作 id | 实现 |
|------|---------|------|
| 考试词表 | `import.dict.<name>` / `import.dict.all` | 读 `data/wordlists/<name>.tsv`（ECDICT 生成） |
| 电子书 | `import.ebook` | `tools/ebook_extract.py` 解析 + ECDICT 释义 + `tools/ebook_translate.py` LLM 译段落/例句 |
| 粘贴词表 | `import.paste` | 支持**词组**（按首个中文切分 `look after 照顾`）→ `tools/define_words.py` 查词 |
| 图片 OCR | `import.image` | PP-OCRv4 识别（可多选）→ 复用粘贴导入 |

- **单词释义 = 词典**：离线查 **ECDICT**（`tools/bilingual.py`，秒级，含音标/词性/中英释义），
  未收录才走 LLM；缓存 `data/dict_cache.tsv`。
- **段落/句子/助记 = LLM**：`tools/ebook_translate.py` 逐条生成，
  经 FFI `wc_update_item_explanation` 异步回填；译文缓存 `data/translate_cache.jsonl`。
- **中英文对照物料**：导入即生成 `data/books/<slug>.tsv` 与 `<slug>.jsonl`。
- **按需生成**：复习到某词若无「用法」助记/段落译文，常驻 `tools/memo_server.py`
  即时生成并回填，避免导入时长时间等待。

### LLM / OCR / TTS 服务

- **翻译**：`translate.py` 默认用 **Hunyuan-MT-7B**（`/data/models/Hunyuan-MT-7B-Q4_K_M.gguf`，
  约 4.4G / 显存 ~5.3G），可 `WC_LLM_MODEL` 覆盖；兜底 Qwen3-4B。
  `llama-server` 不再后台静默常驻，而是在**终端窗口**中前台启动（默认 xterm，
  `WC_TERMINAL=qterminal` 可切换）：Ctrl+C / 关闭窗口即可停止；WordCard 退出时
  也会自动停止并释放显存。手动控制：`python3 tools/llama_ctl.py start|stop|status`。
  - **默认本地 LLM**；也可改用在线翻译：在 `.env` 配
    `WC_TRANSLATE_BACKEND=deepseek`、`DEEPSEEK_BASE_URL`、`DEEPSEEK_API_KEY`
    （OpenAI 兼容），此时不启动本地模型/终端。`auto` 才根据 key 自动选择。
- **OCR**：`tools/ocr_image.py` 调 `libocr_simple.so` + `models/ocr/` 的 PP-OCRv4 模型
  （det/rec onnx + 字典）；需 onnxruntime `VERS_1.26.0`，App 通过
  `LD_LIBRARY_PATH=/data/venv/onnxruntime-linux-x64-gpu-1.26.0/lib`（`WC_ORT_LIB` 可覆盖）传入。
- **TTS**：`tools/tts_server.py` 常驻（Kokoro/sherpa-onnx，模型只加载一次），
  合成缓存 `data/tts_cache/` 并 `paplay` 播放；默认 **2.5× 增益**（`WC_TTS_VOLUME`）。
  点单词/段落、听写考试读词均走此服务；合成期间按钮显示等待动画。

---

## 八、记忆数据面板（首页）

- 顶部指标卡：**任务数 / 总词数 / 已记住 / 未记住 / 完成度% / 待复习**。
- **任务完成度柱状图**：每个任务一根柱（已掌握 / 总数），柱顶百分比。
- **遗忘曲线（每个任务一条）**：对已复习词按艾宾浩斯 `R = exp(-t/S)`（S≈间隔天数）
  求未来记忆保持率均值，`CustomPaint` 自绘；**没有记忆数据则不显示**。
- 「开始今日记忆」按钮 → `ReviewScreen`（今日队列）。

---

## 九、听写考试（任务列表入口）

- 随机取该任务词表的**一半**单词/词组。
- 逐个朗读，**每词间隔 8 秒**（圆环倒计时），可重听/结束。
- **结束后**列出全部听写词条及对应中文翻译（答卷一页看全）。
- **不批改、不打分**，全程**手动**（孩子纸笔写，应用只报题与给答案）。

---

## 十、对外自动化 API（AI / 语音 / 微信 驱动）

**目标：把全部能力暴露为稳定 API，任何外部 agent 都能完整操作本应用。**

```
Flutter App ── UDS(JSON Lines) ── libwordcard_ctl.so(C) ── LuaJIT FFI ── agent
 /tmp/wordcard-automation.sock        automation_ctl.c        automation/wordcard.lua
```

UI 按钮与 API 走同一入口：按钮点击 = `invoke(id)`；外部调用 = socket 命令。

### 协议（Unix socket，JSON Lines）

| 请求 | 说明 |
|------|------|
| `{"cmd":"list"}` | 返回可用 `actions` 与 `functions` |
| `{"cmd":"state"}` | 返回当前状态（页面 + 统计 + 任务 + 复习） |
| `{"cmd":"click","id":"<action>"}` | 触发按钮动作 |
| `{"cmd":"call","fn":"<fn>","args":{...}}` | 调用带参数的 API 函数 |
| `{"cmd":"ping"}` | 存活探测 |

事件推送：`{"event":"click","id":...,"source":"ui"|"ai"}`；连接建立时发 `{"event":"ready",...}`。

### 按钮动作 id

- 导航：`nav.toggle` / `nav.home` / `nav.tasks` / `nav.import`
- 记忆：`review.flip` / `review.know` / `review.dontKnow` / `review.restart` / `review.speakParagraph`
- 导入：`import.dict.<name>` / `import.dict.all` / `import.ebook` / `import.paste` / `import.image`

### API 函数（`call`，供其他 agent 完整操作）

| fn | args | 说明 |
|----|------|------|
| `state` | — | 页面 + `stats` + `tasks` + `review` |
| `stats` | — | 任务数/总词数/已记住/未记住/完成度/待复习 |
| `nav.goto` | `{page:0\|1\|2\|3}` | 切页（首页/任务/导入/阅读） |
| `task.list` | — | 任务列表（含 done/count） |
| `task.words` | `{tag,page,size}` | 翻页取某任务单词 |
| `task.study` | `{tag}` | 打开该任务的**记忆**页 |
| `task.dictate` | `{tag}` | 打开该任务的**听写**页 |
| `task.delete` | `{tag}` | 删除任务 |
| `task.create` | `{name,text}` | 粘贴文本建任务（支持词组） |
| `import.wordlist` | `{name}` 或 `{names:'all'\|[..]}` | 导入考试词表 |
| `import.ebook` | `{path}` | 导入电子书（解析 + 释义 + 翻译） |
| `import.image` | `{paths:[..],name}` | 图片 OCR 建任务 |
| `review.startDaily` | — | 打开今日记忆 |
| `reader.list` | — | 书架：书名/章节/页数/阅读进度 |
| `reader.open` | `{slug}` | 打开某本书（书内状态函数同时注册） |
| `reader.import` | `{path}` | 调 `/opt/my_db/tools/import_book` 导入（--skip-vectors） |
| `reader.state` | — | 当前书/章/段落/已译数 |
| `reader.chapter` | `{index}` | 跳到某章 |
| `reader.translate` | `{index}` 或 `{all:true}` | 翻译一段/整章 |
| `reader.nextChapter` / `reader.prevChapter` | — | 章节翻页（按钮动作） |
| `app.quit` | — | 退出应用 |

### 用法（LuaJIT）

```lua
local wc = require("wordcard")
local c = assert(wc.open())
for _, f in ipairs(c:actions()) do print(f) end   -- 或 c:list()
print(c:stats())                     -- 统计
print(c:tasks())                     -- 任务列表
c:study("book:岛上书店")             -- 打开某任务记忆
c:dictate("dict:cet4")               -- 听写该任务
c:createTask("第3周", "abandon 放弃\nlook after 照顾")
c:readerOpen("ddia"); c:readerChapter(10); c:readerTranslate(0)
c:close()
```

**原生窗口/截图（LuaJIT FFI，无 xdotool/wmctrl 子进程）**：

```lua
local c = require("wordcard").open()
local w = assert(c:window())              -- libxdo 定位窗口
w:activate():center()                     -- 激活/置顶/居中
w:capture("/tmp/opencode/wordcard_ui.png")-- FFI 截屏（GL 窗口可用）
w:click(92, 198); w:key("ctrl+l"); w:type("search")
c:close()
```

一行式：`luajit -e 'package.path="/opt/WordCard/gui/flutter/automation/?.lua;"..package.path; local c=require("wordcard").open(); c:window():center():capture("/tmp/wc.png"); c:close()'`

实现见 `automation/xdo.lua`（libxdo/X11 FFI）+ `automation/x11.lua`；
截屏走 `/opt/my-agent/agentkit/lib/libagentkit.so`（FFI）。
`c:activate()/c:center()/c:move()/c:capture()` 均为原生实现，不再提供 socket 窗口 API。

便捷方法（返回原始 JSON 字符串）：`stats / tasks / words / study / dictate /
deleteTask / createTask / importWordlist / importEbook / goto / startDaily /
readerList / readerOpen / readerState / readerChapter / readerTranslate / call`。
`activate / center / move / capture` 为原生窗口操作（成功返回 true/窗口对象），
不经过 socket；`window()` 返回可直接链式调用的窗口对象。

构建与运行：`cd src && make automation`（→ `libwordcard_ctl.so`）；
`luajit gui/flutter/automation/agent_demo.lua`；原生窗口演示
`luajit gui/flutter/automation/native_demo.lua`。
环境变量：`WC_AUTOMATION_SOCK`、`WORDCARD_ROOT`、`WCCTL_LIB`、`WC_WINDOW_TITLE`、
`AGENTKIT_LIB`。


---

## 十一、桌面端开发规范

- **响应式**：`LayoutBuilder` / `Expanded`，不硬编码尺寸。
- **窗口**：客户端标题栏 `YaruWindowTitleBar`，**关闭 = 最小化**（不退出）；
  不引入 `window_manager` / `tray_manager`（与 Yaru 冲突会触发 `implicit view` SEGV）。
- **桌面交互**：鼠标 hover、滚轮；键盘快捷键——空格=不会、→=记得（听写/输入时禁用）。
- **可访问性**：焦点顺序、键盘可操作、跟随系统高/低对比度。

---

## 十二、目录结构

```
gui/flutter/
├── pubspec.yaml                 # 依赖 + 字体资产
├── assets/fonts/                # MapleMono-NF-CN-*.ttf + TsangerJinKai02-W0{4,5}.ttf
├── assets/icons/                # 应用图标（app 图标，供桌面项）
├── lib/
│   ├── main.dart                # YaruTheme 入口 + YaruWindowTitleBar.ensureInitialized + Automation
│   ├── app.dart                 # MaterialApp + 全局标题栏
│   ├── theme/
│   │   ├── app_theme.dart       # Yaru 融合主题 + Kami 调色板
│   │   └── fonts.dart           # AppFonts
│   ├── ffi/
│   │   ├── wordcard.dart        # wc_* 绑定 + TaskInfo/MasterySnapshot
│   │   ├── structs.dart         # C 结构体布局
│   │   └── voice.dart           # voice_* 绑定（占位）
│   ├── state/study_session.dart # 队列 / 当前卡 / 评分 / startItems / restart
│   ├── automation/automation.dart # 动作注册表 + socket + 事件
│   ├── tts.dart / memo_service.dart                 # 常驻 TTS / 助记+翻译
│   ├── wordlist.dart / ebook_import.dart /
│   │   paste_import.dart / ocr_import.dart          # 各导入来源
│   ├── pages/
│   │   ├── study_page.dart      # 主框架 + 侧栏（首页/任务/导入/阅读）
│   │   ├── dashboard_page.dart  # 记忆数据面板
│   │   ├── tasks_page.dart      # 任务列表 + 翻页词表
│   │   ├── reader_page.dart     # 书架（/opt/books + 导入）
│   │   ├── bilingual_reader.dart# 双语阅读（段间对照/查词/加入任务）
│   │   ├── review_screen.dart   # 记忆（路由）
│   │   ├── dictation_exam.dart  # 听写考试（路由）
│   │   └── import_page.dart     # 导入
│   ├── reader_library.dart      # 书库/章节/段落解析 + 译文/进度缓存
│   └── widgets/
│       ├── flash_card.dart      # 卡片（Kami 排版）
│       ├── clickable_text.dart  # 可点词 RichText（查词）
│       ├── memory_curve.dart    # 遗忘曲线（CustomPaint）
│       └── task_bar_chart.dart  # 任务完成度柱状图
├── automation/                  # wordcard.lua / xdo.lua / x11.lua（LuaJIT FFI）
│                                # agent_demo.lua / native_demo.lua
├── linux/                       # flutter create 生成（GTK 运行器）
└── snap/                        # snapcraft.yaml（预留）
```

---

## 十三、构建 / 运行 / 桌面快捷方式

依赖版本（**重要**）：`yaru: ^10.2.0` + `dependency_overrides: platform: 3.1.6`。
（yaru 11 需 platform 3.2.0 新 API，而 `platform_linux 0.1.2+1` 仍用被移除的
`Platform.environment`，两者不兼容，故锁定。）

```bash
# 构建（默认 Flutter 在 ~/development/flutter，可 FLUTTER_HOME 覆盖）
gui/flutter/build.sh            # 编译 C 核心 + flutter build linux --release
gui/flutter/run.sh              # 运行（未构建会先自动构建）
```

产物：`gui/flutter/build/linux/x64/release/bundle/wordcard`。
`run.sh` 导出 `LD_LIBRARY_PATH` 指向 `src/`、`libs/`、`voice/libs/`。

**systemd 用户服务**（`wordcard-app.service`）：常驻运行、`Restart=no`、
设 `DISPLAY`/`XDG_RUNTIME_DIR`/`PULSE_SERVER`/`LD_LIBRARY_PATH`。
```bash
systemctl --user restart wordcard-app     # 重启（改代码 build 后）
journalctl --user -u wordcard-app -f      # 日志
```

**桌面快捷方式**：`~/Desktop/wordcard.desktop`（`chmod +x`，同时装入
`~/.local/share/applications/`），`Exec` 指向 `run.sh`，`Icon` 指向 `assets/icons/wordcard.png`。

### 应用图标生成（backup.sh）

由 `/opt/static_comfyui/cpp/sd/backup.sh`（SDXL/Qwen3，HiRes）出 1024×1024，再缩放：

```bash
cd /opt/static_comfyui/cpp/sd
NEGATIVE_PROMPT="person, people, human, face, portrait, text, letters, words, watermark, \
signature, logo, brand, photo, photorealistic, 3d render, blurry, low quality, noise, \
frame distortion, border artifacts" \
SKIP_QUALITY_PREFIX=1 \
./backup.sh "flat minimal app icon, rounded square emblem, an open book with a floating \
vocabulary flashcard above it, sage green cream and vermilion red palette, traditional \
Chinese minimal ornamental style, centered, solid soft light green background, clean vector" \
/tmp/opencode/wordcard_icon.png 1024 1024

SRC=$(ls -t /tmp/opencode/wordcard_icon_*.png | head -1)
convert "$SRC" -resize 512x512 gui/flutter/assets/icons/wordcard-512.png
convert "$SRC" -resize 256x256 gui/flutter/assets/icons/wordcard.png
cp "$SRC" gui/flutter/assets/icons/wordcard-1024.png
cp gui/flutter/assets/icons/wordcard.png ~/.local/share/icons/hicolor/256x256/apps/wordcard.png
```

---

## 十四、开发工作流（自设计 · 自验证 · 自迭代）

> Agent 可**自己设计、自己构建、自己截图验证、自己迭代**；细则见仓库根 `AGENTS.md`。

```
设计 → 构建 → 运行 → 截图 → 读图自检 → 迭代 → 提交
```

1. **构建**：`gui/flutter/build.sh`（先编 C 核心再 `flutter build linux --release`）；
   改 Dart 先 `flutter analyze`（须 No issues）。
2. **运行（必须会话内）**：以当前图形会话环境启动，避免 systemd 无 `XAUTHORITY` 导致 GL 失败：
   ```bash
   P=$(pgrep -x pcmanfm-qt|head -1); XA=$(tr '\0' '\n' </proc/$P/environ|sed -n 's/^XAUTHORITY=//p')
   setsid env DISPLAY=:0 XAUTHORITY="$XA" XDG_RUNTIME_DIR=/run/user/1000 \
     gui/flutter/run.sh >/tmp/opencode/wc.log 2>&1 </dev/null & disown
   ```
3. **截图自检**（LuaJIT 原生窗口 + FFI 截屏，无外部进程）：
   ```bash
   WORDCARD_ROOT=/opt/WordCard luajit -e 'package.path="/opt/WordCard/gui/flutter/automation/?.lua;"..package.path;
     local c=require("wordcard").open(); c:window():center():capture("/tmp/opencode/wordcard_ui.png"); c:close()'
   # 再用 Read 读 /tmp/opencode/wordcard_ui.png 即可看到真实界面
   ```
4. **驱动 UI**：所有按钮走 `Automation.invoke(id)`，用 LuaJIT FFI 查询/点击/读状态
   （`luajit gui/flutter/automation/agent_demo.lua`）。

**环境红线**：NVIDIA 内核态/用户态版本必须一致（否则所有 OpenGL 程序无窗口，需重启）；
`.desktop` 需 `chmod 755` + `trusted`；用 `pkill -x`/括号技巧避免误杀 shell。

---

## 十五、待办 / 后续

- [ ] 卡片图片导出（Flutter `RepaintBoundary` → PNG）
- [ ] 深色模式调色板（Kami 暖米 ↔ 暖深）
- [ ] 「中国色 / 系统色」主题切换设置项
- [ ] 字体子集化瘦身（Maple + 仓耳今楷体积较大）
- [ ] 每日新词上限设置（当前 10；每周词表一次练完需调大）
- [ ] 系统托盘常驻（需绕过 Flutter 隐藏窗口的 SEGV）
- [ ] Snap 打包与 CI

*最后更新: 2026-10-25*
