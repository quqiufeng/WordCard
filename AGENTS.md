# AGENTS.md — WordCard 开发约定（面向自动化 Agent）

> 本文件供 AI Agent 阅读，约定本项目的构建 / 运行 / **自验证**工作流与代码规范。
> 目标：Agent 能**自己设计、自己构建、自己截图验证、自己迭代**，尽量少打扰用户。

---

## 一、项目速览

- **C 核心**：`src/` → `libwordcard.so`（SM-2 引擎 + 哈希索引），`make -C src wordcard` 构建。
- **Python 管道**：解析 / 选词(ECDICT) / LLM 翻译 / OCR / TTS（`tools/`、`importer.py`、`translate.py`…）。
- **桌面 UI**：`gui/flutter/`（Flutter + Yaru，`dart:ffi` 直连 `libwordcard.so`）。
- **UI 架构文档**：`gui.md`；**总览**：`README.md`；**引擎设计**：`design.md`。
- **全自动化开发模式（Fully-Automated Mode）**：`automation.md`——Agent 能看见并使用自己做的软件，在使用中迭代验证。

---

## 二、自动化开发闭环（核心）

```
设计 → 构建 → 运行 → 截图 → 读图自检 → 迭代 → 提交
```

### 1. 构建

```bash
# 仅改 Dart/UI：
export PATH="$HOME/development/flutter/bin:$PATH"
cd gui/flutter && flutter analyze && flutter build linux --release

# 改了 C 核心：先 make -C src wordcard（或直接跑 build.sh，它会先编译 C 核心）
gui/flutter/build.sh
```

### 2. 运行（**必须在图形会话环境里跑**）

产物：`gui/flutter/build/linux/x64/release/bundle/wordcard`。

```bash
P=$(pgrep -x pcmanfm-qt | head -1)
XA=$(tr '\0' '\n' < /proc/$P/environ | sed -n 's/^XAUTHORITY=//p')
setsid env DISPLAY=:0 XAUTHORITY="$XA" XDG_RUNTIME_DIR=/run/user/1000 \
  gui/flutter/run.sh >/tmp/opencode/wc.log 2>&1 </dev/null & disown
```

- **不要用 `systemd --user` 服务启动 UI**：服务环境缺少 `XAUTHORITY`/GPU 上下文，会导致
  `Failed to create OpenGL context` → 进程起但无窗口。UI 一律**在会话内**启动。
- 桌面图标走 `gui/flutter/launch.sh`（会话内启动、单实例）。

### 3. 截图自检（**关键：Agent 能自己看图**）

`import -window <id>` 抓不了 GL 窗口；改为**全屏抓图 + 按窗口几何裁剪**：

```bash
P=$(pgrep -x pcmanfm-qt | head -1); XA=$(tr '\0' '\n' < /proc/$P/environ | sed -n 's/^XAUTHORITY=//p')
export DISPLAY=:0 XAUTHORITY="$XA"
wmctrl -a "WordCard"; sleep 1            # 置顶（避免被终端挡住）
read X Y W H < <(wmctrl -lG | grep -i WordCard | awk '{print $3,$4,$5,$6}')
import -window root /tmp/opencode/full.png
convert /tmp/opencode/full.png -crop "${W}x${H}+${X}+${Y}" +repage ~/wordcard_ui.png
# 然后用 Read 工具读 ~/wordcard_ui.png 即可看到真实界面
```

#### 3.5 把窗口移到屏幕中央（可选，截图更聚焦）

**必须先激活窗口**（点任务栏 App 图标，或 `xdotool windowactivate`），否则拖动不生效；
再拖**标题栏空白处**（避开标题文字与右侧按钮）：

```bash
HEX=$(wmctrl -lG | awk '/WordCard/{print $1; exit}'); WID=$((HEX))
xdotool windowactivate --sync "$WID"; xdotool windowraise "$WID"; sleep 1
read SW SH < <(xdotool getdisplaygeometry)
read X0 Y0 W H < <(wmctrl -lG | grep -i WordCard | awk '{print $3,$4,$5,$6}')
GX=$((X0+70)); GY=$((Y0+14))                 # 标题栏左侧空白区
TX=$(( (SW-W)/2 )); TY=$(( (SH-H)/2 ))
xdotool mousemove --sync $GX $GY; sleep 0.3; xdotool mousedown 1; sleep 0.3
xdotool mousemove --sync $((GX+TX-X0)) $((GY+TY-Y0)); sleep 0.2; xdotool mouseup 1
# 拖拽不稳时兜底：wmctrl -r "WordCard" -e "0,$TX,$TY,$W,$H"
```

### 4. 驱动 UI（AI 自动化接口）

每个按钮都走 `Automation.invoke(id)`，可用 LuaJIT FFI 远程查询/点击：

```bash
luajit gui/flutter/automation/agent_demo.lua     # 示例：列出动作、点击、读状态
# 或
WORDCARD_ROOT=/opt/WordCard luajit -e 'package.path="gui/flutter/automation/?.lua;"..package.path;
  local c=require("wordcard").open(); print(c:state()); c:click("nav.tasks"); c:close()'
```

协议：Unix socket `/tmp/wordcard-automation.sock`，JSON Lines：
`{"cmd":"list|state|click|ping"}`；事件 `{"event":"click",...}`。

**对外 API（供 my-agent 语音/微信等驱动）**：除 `click` 外支持带参数命令
`{"cmd":"call","fn":"<fn>","args":{...}}`。已暴露函数：
`state` `stats` `nav.goto` `task.list` `task.words` `task.study` `task.dictate`
`task.delete` `task.create` `import.wordlist` `import.ebook` `import.image` `review.startDaily` `window.activate` `window.center` `window.move` `app.quit`。
Lua 封装 `automation/wordcard.lua` 提供 `call(fn,args_json)` 及便捷方法
`stats()/tasks()/words()/study(tag)/dictate(tag)/createTask(name,text)/importWordlist/importEbook/goto/startDaily`。

```bash
WORDCARD_ROOT=/opt/WordCard luajit -e 'package.path="gui/flutter/automation/?.lua;"..package.path;
  local c=require("wordcard").open();
  print(c:stats()); print(c:tasks()); c:study("dict:cet4"); c:close()'
```

---

## 三、环境注意事项（踩过的坑）

1. **NVIDIA 驱动版本必须匹配**：内核模块版本 = 用户态库版本，否则**所有 OpenGL 程序**建不了上下文，
   Flutter 会「进程在、无窗口」。`unattended-upgrades` 升级 nvidia 用户态后需**重启**一次。
   自查：`nvidia-smi`、`cat /proc/driver/nvidia/version`、`glxinfo -B`。
2. **桌面图标双击**：`.desktop` 需 `chmod 755`（**组/其他可写会被 GLib 判为不可信而拒绝运行**）+ `gio set metadata::trusted true`。
3. **改 UI 字体**：改了 `pubspec.yaml` 字体或系统字体后，Qt 应用需**重启进程/重登**才刷新字体列表。
4. **别用 `pkill -f llama-server`** 之类会匹配到自身命令行的模式（会杀掉执行命令的 shell）；
   用 `pkill -x` 或 `'llama-serve[r]'` 括号技巧。
5. **qterminal 字体会被运行中的实例写回覆盖** → 改配置前先关闭 qterminal。

---

## 四、设计规范（UI）

- 遵循 **Kami**（`github.com/tw93/Kami`）：暖米纸感底 `#F5F4ED`、**单一油墨蓝强调 `#1B365D`**、
  衬线字体、大量留白、**细线分隔、无渐变/无阴影**。配色常量见 `lib/theme/app_theme.dart` 的 `Kami`。
- 字体：界面/单词用 **Maple Mono NF CN**；卡片正文用 **仓耳今楷 02**（`TsangerJinKai02`）。
- 文案/标题用衬线体（`AppFonts.tsangerJinKai`）。
- 新页面请复用现有组件风格（`_section` 竖条标题、surface+hairline 卡片、inkBlue 进度/曲线）。

---

## 五、代码规范

- Dart：`flutter analyze` 必须 **No issues**（提交前必过）。
- C：`make -C src wordcard` 无 warning；改动结构体需同步更新 `engine.py`（ctypes）与 Dart `lib/ffi/structs.dart` 的布局。
- 复用而非重写：解析/翻译/查词/OCR 一律调 `tools/*.py`，UI 只经 FFI 触发与展示。
- 提交信息用约定式（`feat/fix/style/docs/chore(scope): ...`）。

---

## 六、常用命令速查

```bash
make -C src wordcard            # 构建 C 核心
gui/flutter/build.sh            # 构建 C 核心 + Flutter release
gui/flutter/run.sh              # 会话内运行（配合上面的 env）
gui/flutter/launch.sh           # 桌面图标入口（单实例）
luajit gui/flutter/automation/agent_demo.lua   # UI 自动化示例
python3 tools/ebook_extract.py <book>          # 解析电子书（复用管道）
```
