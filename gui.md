# WordCard UI 层技术架构

> Flutter Desktop (Linux) + Yaru + dart:ffi → `libwordcard.so`
> 文档版本: v0.1 — 2026-10-10

---

## 一、目标

为 WordCard 提供运行于 **Ubuntu 桌面**的图形界面，复用现有 C 核心引擎（SM-2 / KV Cache / 语音），
让「导入电子书 → 选词 → 复习 → 卡片」的流程可以在桌面端顺畅完成。

UI 层**只负责展示与交互**，不重写任何学习算法；算法与数据全部来自 C 共享库。

---

## 二、技术栈

| 项 | 选型 | 说明 |
|----|------|------|
| 框架 | **Flutter Desktop**（Linux Stable 渠道） | 同一套代码未来可扩移动端 |
| 语言 | **Dart**（健全空安全 / Strong Null-safety） | |
| Linux 宿主 | **GTK+ 3**（Flutter 官方 Linux 嵌入器） | 由 `flutter create` 生成 `linux/` 运行器 |
| UI 框架 | **Yaru（主）+ Material 3（辅）** | 融合 Ubuntu 桌面生态 |
| 窗口管理 | **YaruWindow / YaruWindowTitleBar** | 不使用 `window_manager`，避免双标题栏 |
| 中英文字体 | **Maple Mono NF CN**（唯一字体，等宽、含 CJK） | 见第六节 |
| 数据通道 | **dart:ffi** 直连本地 `.so` | 见第五节 |
| IDE | VS Code / Android Studio | |
| 打包 | **snapcraft → Snap** | Ubuntu 官方推荐分发格式 |

---

## 三、分层架构

```
┌──────────────────────────────────────────────────────────┐
│  展示层 (Flutter Widgets / Yaru)                          │
│   · YaruMasterDetailPage 侧边栏布局                        │
│   · YaruWindowTitleBar 自定义标题栏                        │
│   · 业务组件：FlashCard / ReviewQueue / StatsWidget ...   │
├──────────────────────────────────────────────────────────┤
│  状态层 (Dart)                                            │
│   · ChangeNotifier / ValueNotifier（按需，轻量）           │
│   · StudySession（队列 / 当前卡 / 评分 / 统计）           │
├──────────────────────────────────────────────────────────┤
│  FFI 绑定层 (lib/ffi/)                                    │
│   · ffi.cdef 声明 wc_* / voice_* C ABI                    │
│   · 结构体内存布局 <-> Dart 对象（Struct / Pointer）      │
│   · libwordcard.so, libvoice_engine.so                    │
├──────────────────────────────────────────────────────────┤
│  C 核心层（现有，未改动）                                  │
│   · libwordcard.so  SM-2 引擎 + 哈希索引 + KV Cache       │
│   · libvoice_engine.so  ASR/TTS                           │
└──────────────────────────────────────────────────────────┘
```

数据流（复习闭环）：

```
启动 → wc_load_db / wc_find_user
     → wc_generate_daily_queue(user, now)   今日队列
     → wc_find_item_by_id(item)             卡片详情
     → 用户翻转 / 作答 → wc_sm2_update(quality)
     → wc_save_db / wc_mark_dirty → 统计更新
```

### 统一导入模型（来源 ≠ 算法）

**词典导入与电子书导入只是「来源（source）」不同，记忆方式与算法完全通用。**

```
来源 (source)                     统一学习项              统一复习
──────────────                    (item_entry_t)          (SM-2)
 考试词表 (cet4/cet6/…)   ─┐
 电子书 (PDF/MOBI/EPUB…)  ─┼─►  同一 wordcard.db    ─►  同一 daily_queue
                            │     同一结构 (question/       同一 6 维掌握度
 其他来源 (题库/短文…)     ─┘      answer/hint/tags)        同一 modes 推荐
```

- 两种导入都调用 `wc_add_item`，写入**同一张 items 表**，仅 `tags` 不同
  （`dict:cet4` / `book:<title>`）以标记来源。
- 复习端 `StudySession` 只按 `wc_generate_daily_queue` 取队列，**不区分来源**；
  因此无需为词典/电子书各写一套复习逻辑。
- 若需「只复习 CET4」这类过滤，用 `tags` 之上再加一层筛选即可，属增量功能。

---

## 四、Yaru 融合主题策略

**主框架 Yaru，Material 3 无缝降级。**

- 顶层用 `YaruTheme` 的 **builder 形式**全局监听 Ubuntu 系统外观
  （注意：当前 yaru 11 已无 `YaruThemeBuilder`，等价 API 是 `YaruTheme`）：
  ```dart
  YaruTheme(
    builder: (context, yaru, child) => MaterialApp(
      theme: yaru.theme,          // 自动匹配系统浅色主题
      darkTheme: yaru.darkTheme,  // 自动匹配系统深色主题
      themeMode: ThemeMode.system, // 跟随系统切换
      home: const StudyPage(),
    ),
  )
  ```
- 窗口标题栏需在启动时初始化：
  ```dart
  Future<void> main() async {
    WidgetsFlutterBinding.ensureInitialized();
    await YaruWindowTitleBar.ensureInitialized();
    runApp(const WordCardApp());
  }
  ```
- **强调色 / 主题模式跟随系统**（当前采用系统色；「中国色」切换作为后续可选设置项）。
- 当 Yaru 缺少某业务组件时，使用 Material 3 组件，但必须继承 YaruTheme 提供的 `ThemeData`，
  保证颜色 / 圆角 / 间距一致。
- 优先使用 Yaru 桌面级组件：`YaruMasterDetailPage`（侧边栏）、`YaruWindowTitleBar`、`Yaru*` 表单控件。

### 中国传统色（仅作语义数据色）

系统色作为主色（primary/accent），以下色板取自 `src/dotui.h` 与 `vocab_card.py`，
用于**业务语义**（生词卡底色、正确/错误反馈、边框），不覆盖系统主色。

| 角色 | 色值 | 名称 |
|------|------|------|
| 生词卡底 / background | `#E2F0CB` | 霜地 |
| card 渐变上 | `#F3F8E8` | 嫩菊绿 |
| card 渐变下 | `#E7F0D6` | — |
| border | `#C4D6A6` | — |
| 卡片边框（强调） | `#A3A33E` | 秋香色 |
| ink（正文） | `#1D1B1C` | 墨色 |
| muted | `#5B6B4F` | — |
| accent（数据） | `#2A3C5C` | 黛蓝 |
| success | `#2E8B57` | 青绿 |
| error | `#D92121` | 朱砂红 |
| warn | `#C77A16` | — |

> 深色模式另配「玄色 / 缃色」一套，后续补充。

---

## 五、数据通道（dart:ffi）

UI 直接通过 `dart:ffi` 调用本地共享库，不经过 Python / HTTP。

```dart
final lib = DynamicLibrary.open('libwordcard.so');
final wcLoadDb = lib.lookupFunction<
    Pointer<Void> Function(Pointer<Utf8>),
    Pointer<Void> Function(Pointer<Utf8>)>('wc_load_db');
```

主要使用的 C ABI（`src/wordcard.h`）：

| 函数 | 用途 |
|------|------|
| `wc_db_init` / `wc_load_db` / `wc_save_db` / `wc_db_free` | 数据库生命周期 |
| `wc_create_user` / `wc_find_user` / `wc_find_user_by_id` | 用户 |
| `wc_generate_daily_queue` / `wc_get_due_items` / `wc_get_new_items` | 队列 |
| `wc_find_item_by_id` / `wc_find_item_by_question` | 卡片详情 |
| `wc_get_or_create_mastery` / `wc_find_mastery` | 掌握度 |
| `wc_sm2_update` / `wc_update_mastery_dimension` / `wc_recalc_overall` | 复习提交 |
| `wc_record_activity` / `wc_now` / `wc_today` | 统计 |
| `voice_*`（`libvoice_engine.so`） | ASR / TTS |

约定：
- C 层字符串统一 `char*`（UTF-8）；Dart 侧用 `package:ffi` 的 `Utf8` 与 `.toDartString()`。
- `item_entry_t` / `user_item_mastery_t` 等结构体在 Dart 侧用 `final class ... extends Struct` 精确对齐。
- 返回值指针的所有权归 C 层（多为库内部指针），UI 侧只读，不手动 `free`。

---

## 六、字体

**全应用统一单一字体：Maple Mono NF CN**（等宽、Nerd Font 补丁、含 CJK，中英混排统一）。

声明于 `pubspec.yaml`（`gui/flutter/assets/fonts/`）：

| 字重 | 文件 |
|------|------|
| 400 | `MapleMono-NF-CN-Regular.ttf` |
| 500 | `MapleMono-NF-CN-Medium.ttf` |
| 600 | `MapleMono-NF-CN-SemiBold.ttf` |
| 700 | `MapleMono-NF-CN-Bold.ttf` |

```dart
abstract final class AppFonts {
  static const mapleMono = 'MapleMonoNF';
}
```

- 全局通过 `ThemeData.textTheme` 统一设置 `fontFamily`。
- 单词 / 音标 / 例句 / 释义均使用该字体，不引入第二套字体。
- 体积约 79MB（4 字重）随应用打包；如需瘦身可后续用 `fonttools` 子集化。

---

## 七、桌面端开发规范

- **响应式布局**：禁止硬编码固定宽高，使用 `LayoutBuilder` / `MediaQuery` /
  `Row` + `Flexible`/`Expanded`，适配窗口自由缩放。
- **窗口**：使用 `YaruWindow` 管理大小、位置、最小化/最大化与标题栏；不叠加其他窗口插件。
- **桌面交互**：
  - 列表/表单支持鼠标滚轮与 **hover 状态**（`MouseRegion` / Yaru 自带 hover）。
  - 提供键盘快捷键（`Shortcuts` + `Actions`），例如翻卡（空格）、评分（1–4）。
- **可访问性**：焦点顺序、键盘可操作性、高对比度主题跟随系统。

---

## 八、目录结构

```
gui/flutter/
├── pubspec.yaml                 # 依赖 + 字体资产声明
├── assets/fonts/                # MapleMono-NF-CN-{Regular,Medium,SemiBold,Bold}.ttf
├── lib/
│   ├── main.dart                # YaruTheme 入口 + YaruWindowTitleBar.ensureInitialized
│   ├── app.dart                 # MaterialApp + 路由
│   ├── theme/
│   │   ├── app_theme.dart       # Yaru 融合主题 + 中国色语义色
│   │   └── fonts.dart           # AppFonts
│   ├── ffi/
│   │   ├── wordcard.dart        # wc_* 绑定
│   │   ├── voice.dart           # voice_* 绑定
│   │   └── structs.dart         # C 结构体布局
│   ├── state/
│   │   └── study_session.dart   # 队列 / 当前卡 / 统计
│   ├── pages/
│   │   ├── study_page.dart      # 主页面（YaruMasterDetailPage：复习/队列/统计/导入）
│   │   └── import_page.dart     # 电子书导入（占位）
│   └── widgets/
│       ├── flash_card.dart
│       ├── review_queue.dart
│       └── stats_widget.dart
├── linux/                       # flutter create 生成（GTK 运行器）
└── snap/                        # snapcraft.yaml（分发包 .so + 字体）
```

---

## 九、打包与分发（Snap）

1. `flutter build linux --release` → 原生 ELF 二进制。
2. `snapcraft.yaml` 打包：
   - 将 `libwordcard.so` / `libvoice_engine.so` 一并 stage 进包（`stage-packages` 或本地 `prime`）。
   - 字体资产由 Flutter bundle 携带。
   - 运行时通过 `LD_LIBRARY_PATH` 或 rpath 定位 `.so`。
3. 目标：Ubuntu 官方推荐的 **Snap** 格式。

---

## 十、构建 / 运行 / 桌面快捷方式

依赖版本（**重要**）：`yaru: ^10.2.0`。
yaru 11.0.0 需要 `platform 3.2.0` 的新 API，而其依赖 `platform_linux 0.1.2+1`
仍在调用 3.2.0 已移除的 legacy `Platform.environment`，二者不兼容；
故锁回 10.2.0，并在 `pubspec.yaml` 中 `dependency_overrides: platform: 3.1.6`。

```bash
# 构建（默认 Flutter 位于 ~/development/flutter，可 FLUTTER_HOME 覆盖）
gui/flutter/build.sh            # 编译 C 核心 + flutter build linux --release

# 运行（未构建会先自动构建）
gui/flutter/run.sh
```

产物：`gui/flutter/build/linux/x64/release/bundle/wordcard`。
`run.sh` 已导出 `LD_LIBRARY_PATH` 指向 `src/`、`libs/`、`voice/libs/` 以定位 C 核心库。

桌面快捷方式：`~/Desktop/wordcard.desktop`（已 `chmod +x`，同时装入 `~/.local/share/applications/`），
`Exec` 指向 `run.sh`，`Icon` 指向 `assets/icons/wordcard.png`（由 `backup.sh` 生成并缩放）。
点击即可启动。

### 应用图标生成（backup.sh）

图标由 `/opt/static_comfyui/cpp/sd/backup.sh`（SDXL / Qwen3，HiRes 两阶段）出图，
1024×1024，再用 ImageMagick 缩放为多尺寸：

```bash
cd /opt/static_comfyui/cpp/sd

NEGATIVE_PROMPT="person, people, human, face, portrait, woman, man, girl, boy, body, hands, \
text, letters, words, chinese characters, watermark, signature, logo, brand, photo, \
photorealistic, 3d render, blurry, low quality, jpeg artifacts, noise, frame distortion, border artifacts" \
SKIP_QUALITY_PREFIX=1 \
./backup.sh \
  "flat minimal app icon, rounded square emblem, an open book with a floating vocabulary flashcard above it, sage green cream and vermilion red palette, traditional Chinese minimal ornamental style, centered, solid soft light green background, clean vector illustration" \
  /tmp/opencode/wordcard_icon.png 1024 1024
# 注: backup.sh 会给输出文件名追加时间戳 → /tmp/opencode/wordcard_icon_YYYYmmdd_HHMMSS.png

# 缩放并安装（在仓库根 /opt/WordCard 下执行）
SRC=$(ls -t /tmp/opencode/wordcard_icon_*.png | head -1)
convert "$SRC" -resize 512x512 gui/flutter/assets/icons/wordcard-512.png
convert "$SRC" -resize 256x256 gui/flutter/assets/icons/wordcard.png
cp "$SRC" gui/flutter/assets/icons/wordcard-1024.png
mkdir -p ~/.local/share/icons/hicolor/256x256/apps
cp gui/flutter/assets/icons/wordcard.png ~/.local/share/icons/hicolor/256x256/apps/wordcard.png
```

要点：
- `backup.sh` 默认是「人像档」，故用 `NEGATIVE_PROMPT` 强负面排除 人/脸/文字/水印/logo；
  `SKIP_QUALITY_PREFIX=1` 去掉脚本层质量前缀（宽画幅易诱导主体复制）。
- 出图约 50s（RTX 3080）；`.desktop` 的 `Icon` 用绝对路径指向 256px 版本。

---

## 十一、待办 / 后续

- [ ] 复习队列页跑通 FFI 闭环（首个里程碑）
- [ ] 电子书导入面板（对接 `importer`）
- [ ] 学习统计看板
- [ ] 卡片图片导出（Flutter `RepaintBoundary` → PNG）
- [ ] 「中国色 / 系统色」主题切换设置项
- [ ] 深色模式中国色板（玄色 / 缃色）
- [ ] 字体子集化瘦身
- [ ] Snap 打包与 CI

*最后更新: 2026-10-10*
