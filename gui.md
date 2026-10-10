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

---

## 四、Yaru 融合主题策略

**主框架 Yaru，Material 3 无缝降级。**

- 顶层用 `YaruThemeBuilder` 全局监听 Ubuntu 系统外观：
  ```dart
  YaruThemeBuilder(
    builder: (context, yaruTheme, child) => MaterialApp(
      theme: yaruTheme.theme,
      darkTheme: yaruTheme.darkTheme,
      themeMode: yaruTheme.themeMode,
      home: const MainScreen(),
    ),
  )
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
│   ├── main.dart                # YaruThemeBuilder 入口
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
│   └── widgets/
│       ├── flash_card.dart
│       ├── review_queue.dart
│       ├── stats_widget.dart
│       └── book_import.dart
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

## 十、待办 / 后续

- [ ] 复习队列页跑通 FFI 闭环（首个里程碑）
- [ ] 电子书导入面板（对接 `importer`）
- [ ] 学习统计看板
- [ ] 卡片图片导出（Flutter `RepaintBoundary` → PNG）
- [ ] 「中国色 / 系统色」主题切换设置项
- [ ] 深色模式中国色板（玄色 / 缃色）
- [ ] 字体子集化瘦身
- [ ] Snap 打包与 CI

*最后更新: 2026-10-10*
