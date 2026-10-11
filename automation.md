# WordCard 全自动化开发模式（Fully-Automated Mode）

> Agent 能**看见并使用自己创造的软件**，在“被使用中”直接迭代验证。
> 我们认为这是软件行业的一个**新模式**：代码第一次由创造它的 Agent 在**真实运行、真实交互**中闭环迭代。
> 文档版本: v1.0 — 2026-10-11

---

## 一、这是什么

传统开发闭环是**单向**的：

```
人写代码 → 单元测试/CI → 打包 → 人做 UI 验收 → 反馈 → 人再改
           （机器看不见界面，也“用不了”成品）
```

本模式把它变成**Agent 自闭环**：

```
Agent 设计 → 构建 → 在真实会话里运行 → 用 API 模拟人操作 UI
     ▲                                          │
     │                                          ▼
     └── 改代码 ← 定位问题 ← 读图自检 ← 截图（只截本应用）
```

关键点：**Agent 既能“操作”成品（点击/翻页/评分/导入），也能“看见”成品（截图 + 读图）**，
因此可以在**真实使用**中发现问题并立即修复、重新验证——无需人类中转描述。

> 一句话：**代码第一次可以直接在“使用中”被迭代验证。**

---

## 二、为什么它是新的

| 维度 | 传统（含 AI 编码助手） | 本模式 |
|------|------------------------|--------|
| 验证对象 | 源码 / 单元测试 | **真实运行的应用** |
| 谁看界面 | 人 | **Agent 自己看（截图+读图）** |
| 谁操作 | 人点鼠标 | **Agent 用 API/FFI 模拟操作** |
| 反馈信号 | 日志/断言 | **像素级真实渲染 + 交互状态** |
| 迭代速度 | 分钟~小时（人参与） | **秒~分钟（全自动）** |
| 人参与 | 必须 | **可选（只在关键决策时）** |

传统自动化测试覆盖“逻辑正确”，但**看不到、也点不了**最终 UI；本模式把
**“看得见 + 点得动 + 改得快”**三者合一。

---

## 三、能力边界（已实现）

1. **构建**：`gui/flutter/build.sh`（编 C 核心 + `flutter build linux --release`）。
2. **运行**：`gui/flutter/run.sh` / `launch.sh`——**在图形会话内**启动（继承
   `DISPLAY`/`XAUTHORITY`），保证 GPU/GL 可用。
3. **操作（驱动 UI）**：`Automation` 桥（Unix socket，JSON Lines）——
   - 每个按钮走 `invoke(id)`；外部可 `click`；
   - 带参命令 `call(fn,args)`：数据/任务/导入/复习/窗口全套；
   - LuaJIT FFI 封装 `automation/wordcard.lua`。
4. **看见（视觉自检）**：`import -window root` 全屏抓图 → 按 `wmctrl -lG` 窗口几何
   `convert -crop` 裁剪 → **`Read` 读图**（Agent 直接“看图”）。
5. **迭代**：定位差异 → 改代码 → 重新构建运行 → 再截图验证 → 提交。

---

## 四、使能技术栈

| 环节 | 技术 | 位置 |
|------|------|------|
| 数据/算法 | C 核心 SM-2 + 哈希索引 | `src/` → `libwordcard.so` |
| UI | Flutter + Yaru + Kami 设计 | `gui/flutter/` |
| 直连 | `dart:ffi`（Dart ↔ C） | `lib/ffi/` |
| 自动化桥 | `Automation` 服务 + Unix socket | `lib/automation/automation.dart` |
| 外部客户端 | C 库 + LuaJIT FFI | `src/automation/*`、`automation/wordcard.lua` |
| 内容管道 | ECDICT / LLM 翻译 / PP-OCRv4 / TTS | `tools/*.py` |
| 视觉验证 | 截图 + 裁剪 + 读图 | `import`/`convert` + Read |

---

## 五、对外 API（供 Agent / 语音 / 微信）

协议：Unix socket `/tmp/wordcard-automation.sock`，JSON Lines。

```
{"cmd":"list"}                       # 列出 actions / functions
{"cmd":"state"}                      # 页面 + 统计 + 任务 + 复习态
{"cmd":"click","id":"review.know"}   # 触发按钮
{"cmd":"call","fn":"task.study","args":{"tag":"dict:cet4"}}
```

动作（`click`）：`nav.*` `review.*` `import.*`
函数（`call`）：`state` `stats` `nav.goto` `task.list` `task.words` `task.study`
`task.dictate` `task.delete` `task.create` `import.wordlist` `import.ebook`
`import.image` `review.startDaily` `window.activate` `window.center` `window.move` `app.quit`

Lua：
```lua
local c = require("wordcard").open()
print(c:stats()); print(c:tasks())
c:study("book:岛上书店"); c:dictate("dict:cet4")
c:createTask("第3周", "abandon 放弃\nlook after 照顾")
c:center()
```

---

## 六、标准闭环（可复制）

```bash
# 1) 构建
export PATH="$HOME/development/flutter/bin:$PATH"
gui/flutter/build.sh

# 2) 会话内运行
P=$(pgrep -x pcmanfm-qt|head -1); XA=$(tr '\0' '\n' </proc/$P/environ|sed -n 's/^XAUTHORITY=//p')
setsid env DISPLAY=:0 XAUTHORITY="$XA" XDG_RUNTIME_DIR=/run/user/1000 \
  gui/flutter/run.sh >/tmp/opencode/wc.log 2>&1 </dev/null & disown

# 3) 驱动（Lua）
WORDCARD_ROOT=/opt/WordCard luajit gui/flutter/automation/agent_demo.lua

# 4) 看见：置顶 → 居中 → 抓图裁剪
HEX=$(wmctrl -lG|awk '/WordCard/{print $1;exit}'); WID=$((HEX))
xdotool windowactivate --sync "$WID"; xdotool windowraise "$WID"
read SW SH < <(xdotool getdisplaygeometry)
read X Y W H < <(wmctrl -lG|grep -i WordCard|awk '{print $3,$4,$5,$6}')
wmctrl -r WordCard -e "0,$(( (SW-W)/2 )),$(( (SH-H)/2 )),$W,$H"
import -window root /tmp/opencode/full.png
convert /tmp/opencode/full.png -crop "${W}x${H}+$(( (SW-W)/2 ))+$(( (SH-H)/2 ))" +repage ~/wordcard_ui.png
# 5) Read ~/wordcard_ui.png 看图 → 判差异 → 改代码 → 回到 1)
```

---

## 七、已实证案例（本仓库）

一次全自动自测（无人参与）：
1. `c:createTask("自测任务", "abandon 放弃 / orbit / look after 照顾 / necessary / nebula")`
   → 生成任务（词组识别正常）。
2. `c:study("custom:自测任务")` → 打开记忆页。
3. `c:click("review.flip")` → 卡片背面显示 `照顾`，并**按需 LLM 生成「用法」**。
4. `c:click("review.know")` ×N → 词条推进、跑完自动重开。
5. 截图读图时发现标题带 `custom:` 前缀 → **当场改代码、重建、复验** → 显示 `自测任务 · 自建`。
6. `c:center()` / `c:goto()` → 窗口居中、切页正常。

---

## 八、局限与后续

- **视觉判读**仍需多模态读图；复杂动画/瞬时态需多帧采样。
- 依赖桌面会话环境（`XAUTHORITY`/GL）；无头环境需虚拟显示（Xvfb + 软件 GL）。
- 后续：给 API 增加更细粒度（如复习评分质量、卡片导出 PNG）、事件订阅（UI 主动推送状态变化）、
  并把本模式固化为 CI/常驻守护。
- 命名：我们称其为 **Fully-Automated Mode（全自动化模式）**——
  Agent 设计、构建、运行、驱动、观察、迭代，一气呵成。

---

*最后更新: 2026-10-11*
