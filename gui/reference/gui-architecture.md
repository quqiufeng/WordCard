# WordCard GUI 架构：LuaJIT + Rust/gpui

> 技术架构继承自 `/opt/my_db/aicoding/reference/gui-architecture.md`
> 组件和业务逻辑完全针对 WordCard 学习场景重新开发

---

## 一、整体分层

```
┌──────────────────────────────────────────────────────────────┐
│                  Lua 业务逻辑层                                │
│  main.lua                                                     │
│  - 加载数据库（libwordcard.so FFI）                            │
│  - 获取今日学习队列 → 驱动卡片流程                              │
│  - 用户操作回调（翻转/作答/下一张）                             │
│  - 提交复习 → SM-2 更新                                        │
├──────────────────────────────────────────────────────────────┤
│                  LuaJIT FFI 绑定层                             │
│  gui.lua                                                      │
│  - ffi.load("libwordcard_gui") 加载 .so                       │
│  - ffi.cdef 声明 Rust 导出 + WordCard C API                   │
│  - set_queue / flip_card / submit_answer / set_result         │
├──────────────────────────────────────────────────────────────┤
│                   C 桥接层                                     │
│  gui_tick.c                                                   │
│  - wordcard_gui_tick(lua_state) 定时器 → Lua gui_tick()      │
│  - wordcard_gui_on_flip/on_answer/on_next 用户操作回调        │
├──────────────────────────────────────────────────────────────┤
│                   Rust 渲染引擎层                              │
│  gui_gpui/src/lib.rs + components/mod.rs                     │
│  ┌─ WordCard 自定义组件:                                      │
│  │  FlashCard      — 卡片正反面（点击翻转）                    │
│  │  ModeSelector   — 学习模式选择面板                         │
│  │  ReviewQueue    — 今日复习队列列表                          │
│  │  StatsWidget    — 学习统计概览（/掌握/进行中/新/连续天数）  │
│  │  AnswerInput    — 答案输入框（拼写/听写模式）               │
│  │  ProgressBar    — 学习进度条                                │
│  │  ScoreBadge     — 正确/错误即时反馈标签                     │
│  │  BookImport     — 电子书导入面板                            │
│  └─ 依赖: gpui-component + gpui_platform                       │
└──────────────────────────────────────────────────────────────┘

         Lua 层                     Rust 层
    ┌──────────────┐         ┌──────────────────┐
    │ libwordcard.so│ ← FFI →│ libwordcard_gui.so│
    │ (学习引擎)    │         │ (GPU 渲染)       │
    │ libcache.so   │         │ + gpui-component │
    │ (KV Cache)    │         └──────────────────┘
    └──────────────┘
```

---

## 二、数据流

### 2.1 启动流程

```
main.lua: run_gui()
  │
  ├─ wc_load_db("data/wordcard.db")      ← C API (libwordcard.so)
  ├─ wc_create_user / wc_find_user
  │
  ├─ gui.create({title="WordCard", ...})  ← Lua FFI → Rust
  │     └─ gui_app_create() → GuiApp 结构体
  │
  ├─ run_study(app, db, user_id)
  │     ├─ wc_generate_daily_queue()      ← C API 获取今日队列
  │     ├─ wc_find_item_by_id()            ← C API 获取卡片详情
  │     ├─ gui.set_queue(items)            ← Lua FFI → Rust 渲染
  │     └─ gui.set_current_card()          ← 显示第一张卡片
  │
  ├─ gui.set_stats({mastered, streak...}) ← 初始统计
  │
  └─ gui.run(app, lua_state)              ← 阻塞直到窗口关闭
        └─ Rust: gpui::application().run()
              ├─ 窗口 → WordCardView
              └─ 60fps 定时器 → wordcard_gui_tick → Lua gui_tick()
```

### 2.2 学习交互流程

```
显示卡片 (FlashCard)
  │  question = "abandon"
  │  answer = "放弃；抛弃"
  │
  ├─ 用户点击 → 翻转卡片
  │     └─ pending_action = {type="flip"}
  │           └─ gui_tick() → gui.flip_card() → Rust 重新渲染
  │
  ├─ 用户点击 "✓ I Got It Right"
  │     └─ pending_action = {type="answer", correct=true}
  │           └─ gui_tick()
  │                 ├─ wc_sm2_update(mastery, quality=4)
  │                 ├─ gui.set_stats(...) 更新统计
  │                 ├─ gui.set_result({correct, overall...})
  │                 └─ 显示 ScoreBadge (绿色 "✓ Correct!")
  │
  ├─ 用户点击 "✗ I Got It Wrong"
  │     └─ 同上，但 wc_sm2_update(mastery, quality=1)
  │
  └─ 自动进入下一张
        └─ pending_action = {type="next"}
              └─ gui_tick() → gui.next_card()
                    ├─ queue_offset++
                    ├─ 如果还有下一张：显示新卡片
                    └─ 如果队列已空：提示"学习完成！"
```

### 2.3 统计更新流

```
80fps 定时器 (每帧)
  │
  ├─ wordcard_gui_tick(lua_state)    [C]
  │     └─ Lua gui_tick()
  │           ├─ 处理 pending_action（翻转/作答/下一张）
  │           └─ 返回（无阻塞）
  │
  └─ cx.notify()                     [Rust 重绘]
        └─ WordCardView::render()
              ├─ 读取 queue / offset / flipped
              ├─ 读取 stats（mastered/streak/today）
              ├─ 读取 last_result（ScoreBadge 显示）
              └─ 渲染 UI 树
```

---

## 三、Rust 组件清单

| 组件 | 文件 | 用途 | 属性 |
|------|------|------|------|
| `FlashCard` | `components/mod.rs` | 卡片正反面显示 | question, answer, flipped |
| `ModeSelector` | `components/mod.rs` | 学习模式选择 | modes[ {id, label, icon, active} ] |
| `ReviewQueue` | `components/mod.rs` | 队列列表 | total, done, due[] |
| `StatsWidget` | `components/mod.rs` | 学习统计看板 | mastered, learning, new, streak, today_reviewed, today_correct |
| `AnswerInput` | `components/mod.rs` | 拼写答案输入 | placeholder, disabled |
| `ProgressBar` | `components/mod.rs` | 进度条 | current, total |
| `ScoreBadge` | `components/mod.rs` | 正确/错误标签 | correct, label |
| `NamespaceTree` | `components/mod.rs` | KV Cache 浏览 | entries[{path, depth}] |
| `BookImport` | `components/mod.rs` | 电子书导入 | supported_formats, import_path |

---

## 四、C ABI 契约

### 4.1 Rust 导出的 C 函数（被 Lua 调用）

```c
// libwordcard_gui.so: #[no_mangle] pub extern "C" fn ...

// 生命周期
void*   gui_app_create(const char* config_json);
void    gui_app_free(void* app);
int     gui_run(void* app, void* lua_state);

// 学习队列
void    gui_set_queue(void* app, const char* queue_json);
char*   gui_get_queue(void* app);
void    gui_set_current_card(void* app, uint32_t item_id,
                             const char* question, const char* answer, uint8_t mode);
void    gui_flip_card(void* app);
void    gui_set_answer(void* app, const char* text);
void    gui_submit_answer(void* app);
void    gui_set_result(void* app, const char* result_json);
int     gui_next_card(void* app);
int     gui_queue_count(void* app);

// 统计
void    gui_set_stats(void* app, const char* stats_json);
char*   gui_get_stats(void* app);
```

### 4.2 C 层导出的函数（被 Rust 调用）

```c
// gui_tick.c: 可在 GPUI 主线程安全调用
void wordcard_gui_tick(void* lua_state);          // 60fps 驱动 Lua 协程
void wordcard_gui_on_flip(void* lua_state);       // 用户翻转卡片
void wordcard_gui_on_answer(void* lua_state, const char* text, int quality);  // 用户作答
void wordcard_gui_on_next(void* lua_state);        // 用户下一张
```

### 4.3 Lua 端注册的全局函数（被 C 回调）

```lua
-- main.lua 定义，被 gui_tick.c 通过 lua_getglobal 查找
function gui_tick()       -- 60fps 定时器，处理 pending_action
function gui_on_copy(text) -- 暂未实现
```

---

## 五、状态管理

### 5.1 Rust 侧共享状态（`GuiApp` 结构体）

```rust
struct GuiApp {
    // 学习队列
    queue:        Arc<Mutex<Vec<CardItem>>>,
    queue_offset: Arc<Mutex<usize>>,

    // 当前卡片
    current_question: Arc<Mutex<String>>,
    current_answer:   Arc<Mutex<String>>,
    current_mode:     Arc<Mutex<u8>>,
    current_item_id:  Arc<Mutex<u32>>,
    flipped:          Arc<Mutex<bool>>,
    awaiting_answer:  Arc<Mutex<bool>>,
    last_result:      Arc<Mutex<Option<ReviewResult>>>,
    answer_buffer:    Arc<Mutex<String>>,

    // 统计
    stats: Arc<Mutex<StudyStats>>,

    // 运行时
    lua_state: *mut c_void,
    view:      Mutex<Option<WeakEntity<WordCardView>>>,
    executor:  Mutex<Option<ForegroundExecutor>>,
}
```

### 5.2 Lua 侧状态

```lua
-- main.lua
local current_app = nil      -- 当前 GUI 实例句柄
local current_db = nil       -- 数据库句柄
local current_user = 1       -- 当前用户 ID
local pending_action = nil   -- 挂起的用户操作 {type, ...}
```

---

## 六、与源码来源的差异

| 项目 | aicoding 原始 GUI | WordCard GUI |
|------|-------------------|-------------|
| **用途** | AI Agent 聊天 | 间隔重复学习 |
| **Rust 组件** | ChatView, StatusBar, InfoSection, TokenProgress, ThinkingBlock, CodeBlock, ToolOutputBlock | FlashCard, ModeSelector, ReviewQueue, StatsWidget, AnswerInput, ProgressBar, ScoreBadge |
| **C API** | gui_on_user_message, gui_stream_delta, gui_append_message, gui_tool_output | gui_set_queue, gui_flip_card, gui_set_current_card, gui_set_result, gui_next_card |
| **Lua 逻辑** | LLM 请求 → 流式输出 → 工具执行 | 加载队列 → 翻转 → 作答 → SM-2 更新 |
| **依赖的外部库** | libopencode_gui.so, libopencode_agent.a | libwordcard_gui.so, libwordcard.so, libcache.so |
| **窗口标题** | "opencode" | "WordCard - Spaced Repetition Learning" |
| **默认尺寸** | 1280x720 | 960x680 |

---

## 七、编译与运行

```bash
# 1. 编译 Rust GUI
cd gui/gpui && cargo build --release
cp target/release/libwordcard_gui.so ../

# 2. 编译 C 核心库
cd src && make && make test

# 3. 运行 GUI
cd gui/lua && luajit main.lua
```

---

## 八、性能指标

| 指标 | 值 |
|------|-----|
| UI 刷新率 | 60fps |
| 卡片翻转延迟 | <16ms |
| 复习提交延迟 | <16ms（下帧渲染） |
| 二进制体积 | ~40MB（Rust .so）|

*最后更新: 2026-06-17*
