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

## 九、附：对 Codex / Computer Use 实现方案的解析

> 目的：把“通用 Computer Use”与本项目做法对照，说明我们为何能把 UI 操作做到**又稳又省**。

### 1) 通用回路：感知—推理—行动

逐步循环：**截屏 → 送入多模态模型 → 输出动作 → 执行 → 再截屏观察**，直到完成。
OpenAI 的 CUA/Operator、Anthropic 的 computer-use（`computer` 工具），以及 Codex 的
“操作电脑/浏览器”能力，都是这一范式。模型看到的是**图像**，回的是**动作**。

### 2) 动作空间（典型）

`screenshot`、`mouse_move(x,y)`、`left_click`/`right_click`/`double_click`、
`left_click_drag`、`type(text)`、`key(combo)`、`scroll(dx,dy)`、`wait`、`cursor_position`。

### 3) 坐标落地（核心难点）

- 模型多在**归一化坐标**（0–1000，或相对 1024×768 视口）输出点击点，harness 再映射到真实分辨率。
- 更稳的实现会结合**可访问性树 / AXTree / DOM** 给元素命名与包围盒，减少“纯像素猜坐标”的误差。
- 误差来源：DPR/缩放、多显示器、窗口装饰与 reparent、动画/加载延迟。

### 4) Harness（框架）

组装消息（截图 + 历史动作）→ 调模型 → 解析动作（tool call / JSON）→ 分发到驱动层
（XTest / CDP / ADB / 系统 API）→ 回传结果与**新的截图**，循环下去。
一般运行在**隔离环境**（VM/容器/浏览器沙箱），便于失败回滚与快照。

### 5) 与本项目对照：WordCard 直接走“结构化操作 + 视觉验收”

| 维度 | 通用 Computer Use | WordCard（本项目） |
|------|-------------------|--------------------|
| 操作通道 | 像素点击（模型现场出坐标） | **结构化 API**（Automation 桥 `click`/`call`） |
| 感知频率 | 每步都要截图 + VLM 推理 | 仅**验收时**截图；操作走 API |
| 稳定性 | 依赖模型每一步都对 | API 语义稳定；截图只做验收 |
| 成本 | 每步一次多模态推理（贵/慢） | 操作**零推理**；仅少量读图 |
| 工作流 | 交给人/模型即兴决策 | **固化为 Lua 脚本/命令**，可 diff、可回归 |

> WordCard 比“纯像素 Computer Use”更进一步：**能操作**用 API（`invoke(id)` / `call(fn,args)`，
> 比像素点击更稳更语义化），**能看见**用截图读图——即 **“结构化操作 + 视觉验收”**。
> 当界面**没有** API 时（如微信/Chrome），才退化为区域锚定点击（见 my-agent 的 agentkit）。

### 6) 绕不开的工程坑（本项目已解）

- **输入法**：非英文环境需切 IME，或用**剪贴板粘贴**绕过。
- **窗口**：WM reparent/最大化会改变几何与坐标；**GL 窗口**不能被 `import -window` 直接抓，
  需 root 抓取 + 裁剪（`shot.sh` 同法）。
- **时序**：动画/加载需等待；**合成鼠标移动可能不触发 hover tooltip**（故用“点击后看结果页”判定）。
- **校验**：操作后必须复核（OCR 文本变化 / 图像差分）。

### 7) 结论

通用回路（看图→动作→复验）**必要但昂贵**。落地的正确方向是**把它“编译”下来**：

- 有 API 的应用 → **语义化函数调用**（WordCard：`Automation` 桥）；
- 无 API 的应用 → **探索一次固化区域 + 脚本化**（my-agent：agentkit 的 `maps/*.lua`）；
- 视觉（截图+读图/OCR）**只在探索期与验收期**使用，而非每一步。

这样既保留 Computer Use 的通用性，又把每步推理的**成本与不确定性**摊销掉。


---

---
## 附二：四个核心技术与探索流程

> 落地由四块拼成：**视觉识别 → 位置缓存 → 动态代码生成 → 流程回放**；
> **探索**是把它们串起来的一次性前置动作。

### 1) 视觉识别（Visual Recognition）

- **截图**：`import -window root` + `convert -crop`（GL 窗口走 root 抓取 + 裁剪）。
- **OCR**：PP-OCRv4（`tools/` 管道）取文本 + 坐标——用于**验收**，以及在**无 API 界面**上的定位。
- **模板匹配/差分**：OpenCV（识别无文字图标、判断状态变化）。

### 2) 位置缓存（Position Caching）

- **有 API 时优先语义化调用**（`click(id)` / `call(fn,args)`），无需缓存坐标，最稳。
- **无 API 时**缓存**窗口相对区域**（概念同 my-agent 的 `maps/<app>.lua`），一次探索长期复用；
  窗口移动/缩放不影响（相对坐标锚定）。
- 命中缓存即**零推理**执行。

### 3) 动态代码生成（Dynamic Code Generation）

- 把探索结果与工作流生成**可执行 Lua 代码**：

  ```lua
  local c = require("wordcard").open()
  c:study("dict:cet4"); c:click("review.flip"); c:createTask("第3周", "abandon 放弃")
  ```

- 代码是**一等产物**：可读、可改、可 diff、可版本化、可复用。

### 4) 流程回放（Workflow Replay）

- 按脚本逐步执行：定位/调用 → 动作 → **截图验收**（OCR/差分）→ 失败重试。
- 确定性来源：API 语义 + 验收校验 ⇒ 可**无人值守**重复运行。

### 5) 探索流程（一次性前置）

1. **定位窗口**：`wmctrl -lG` / `xdotool`。
2. **视觉识别**：截图 + 读图/OCR 识别界面结构；图标用像素行暗度分析或模板匹配。
3. **交互验证**：`click`/`call` → 截图看结果**判定功能** → 记录。
4. **固化**：写入 Lua 脚本（动态代码）/ 区域映射。
5. **之后只跑脚本**；界面变动时做**增量**更新。

### 6) 四者关系

```
视觉识别 ──(探索期)──▶ 位置缓存(API / 区域) ──▶ 动态代码(脚本) ──▶ 流程回放
    ▲                                                              │
    └──────────── 运行期校验（OCR / 图像差分）◀───────────────────┘
```

> 本质：**探索期用视觉识别建立缓存**，**运行期用缓存回放脚本**；视觉只在“探索”与“校验”
> 两端出现，中间过程零推理、确定性执行——这正是把 Computer Use “编译”下来的具体做法。

---

## 附三：开发过程即高质量训练语料（带视觉 + 自验证）

> 本模式把“开发过程”本身变成**可训练的数据**：边做边攒，自产自验。
> 说明：当前项目**不训练自有模型**；此处只描述其潜在价值与记录规范，备将来使用。

### 1) 为什么质量高

1. **标签自验证**：每个动作后置校验（OCR / 图像差分）给出成败信号 → **自动 reward**，
   无需人工标注（RLVR 思路），可直接用于拒绝采样 / RL。
2. **三层信号同源**（极难得）：
   - 感知层：`screenshot → 控件（坐标/区域）` —— 教“看懂界面”；
   - 决策层：`任务 → 子目标序列` —— 教“规划”；
   - 合成层：`任务 → 可执行代码（Lua）`，且**回放器即单元测试** —— 教“程序合成”。
   一份数据同时喂视觉 / 行为 / 代码。
3. **自增长飞轮**：探索 → 映射 → 脚本 → 回放校验 → 产出更多带标签轨迹。
   数据不是“采”来的，是“**长**”出来的，且覆盖长尾真应用（微信 / Gemini / 中文 UI / 输入法坑）。

### 2) 要成为可用语料，先解决三件事

- **噪声**：OCR 错字、区域粗、坐标抖动 → 只采“**校验通过**”的轨迹，或用 reward 过滤清洗。
- **分布与隐私**：单机 / 单分辨率 / 少数 app；截图可能夹带**密钥与私聊** → 必须**脱敏**后再存。
- **结构化 schema**（否则是脏数据）：

  ```
  { task,
    obs: { screenshot, ocr | a11y, ts },
    thought?, action,
    verify: { ok, evidence },
    reward,
    artifact: <lua 脚本 / 映射> }
  ```

### 3) 落地

- `agentkit/batch`、`agentkit/record` 可增加**可选 trace 记录**：每步落
  `截图 + 动作 + 校验结果 + reward + 生成的脚本`（默认**脱敏**、可关闭）。
- 这样“开发过程”本身即在一份**带视觉、自验证、多模态**的数据集上持续积累，需要时即可取用。

---

## 附四：学习即产物 · 双层学习

> 附三说“开发过程是语料”；本附更进一步：**“学习”不等于“改权重”**——
> 本模式**已经在学习**，只是学到**外部产物**，而非权重里。

### 1) 现在就在学，只是学到产物里

- 探索一次 → 掌握：映射（位置缓存）、脚本（工作流）、记忆。
- 这种“掌握”的性质：**可读、可 diff、可回滚、可跨机迁移、不灾难性遗忘**。
  对工具型 Agent，常比改权重更划算、更可信。
- 附三所记的轨迹 `(obs, action, verify, reward, artifact)`，正是将来在线学习所需的**经验流**。

### 2) 两套时间尺度的学习

| | 快回路 | 慢回路 |
|------|--------|--------|
| 载体 | 上下文 / 外部产物 / 记忆 | 模型权重 |
| 成本 | 低、分钟级 | 高、离线 |
| 特性 | 即时、可审计、可回滚 | 泛化强，但易污染 / 遗忘 |

本模式是**快回路的极致**：边探索边掌握，无需等下线的训练。

### 3) 在线权重学习的三个硬门槛

1. **无遗忘**（稳定性-可塑性）；
2. **可信的信用分配**；
3. **可回滚 / 可审计**。

工具型 Agent 出错必须能一键退回，而权重里的“掌握”**退不回去**。因此即便在线学习成熟，
**“代码 / 映射”这层仍会作为确定性的安全网长期存在**。

### 4) 结论：双层学习

> 权重学“怎么想”，产物学“怎么做”；**探索现场**就把“怎么做”固化下来，不必等下线训练。

这比“先训练再部署”更先进：学到的东西**当场可用、可验证、可回退**。

---

## 附五：效率来源、适用前提与边界

> 把本模式从“方法”讲成“**什么时候值得用**”。

### 1) 效率来源

- Agent 从“写代码的人”变成“**拥有整个特性的人**”：设计 → 构建 → 运行 → 操作 →
  看图验证 → 迭代，**全程无需人转述**。
- 省掉的最大损耗，是“人做 UI 验收 → 口述问题 → 人再改”这一段。
- 人上移到**定目标 / 定验收**层。

### 2) 三个前提（缺一打折）

1. **可被操作的接口**：有控制面（`call()` / `state()`）最省；没有就用像素兜底
   （agentkit），但成本与脆性高一档。
2. **可被观测的结果**：能截图、能读状态。纯后端 / 无 UI 的逻辑，优势回落到普通单测。
3. **可判定的对错**：能自验证（文本 / 状态 / 图像差分）的自动化程度最高；
   而**审美、产品取舍、模糊需求**仍需人拍板。

### 3) 边界

- **大面积自动化**：能自验证的**界面 / 交互 / 集成**类功能。
- **仍归人**：**产品判断与品味**。

> 结论：这一边界，已足以改变开发的组织方式——人负责“做什么、好不好”，
> Agent 负责“做完并证明它对了”。

---

*最后更新: 2026-10-11*
