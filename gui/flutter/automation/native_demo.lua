-- native_demo.lua — LuaJIT 原生窗口控制演示（不启动 xdotool/wmctrl）
--
--   luajit gui/flutter/automation/native_demo.lua
--
-- 依次：定位窗口 → 激活 → 居中 → 读取几何 → 截图。

local dir = arg[0]:match("^(.*)/[^/]+$") or "."
package.path = dir .. "/?.lua;" .. package.path

local wc = require("wordcard")
local c = assert(wc.open())

local w = assert(c:window(), "WordCard 窗口未找到")
print(("窗口 id=%d  %dx%d @ %d,%d"):format(w.id, w.w, w.h, w.x, w.y))

w:activate():center()
print(("居中后 @ %d,%d"):format(w.x, w.y))

local ok, path = w:capture("/tmp/opencode/wordcard_ui.png")
print(ok and ("截图: " .. path) or "截图失败")

c:close()
