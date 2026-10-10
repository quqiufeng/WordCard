-- agent_demo.lua — 演示 AI agent 通过 LuaJIT 驱动 WordCard
--
--   luajit gui/flutter/automation/agent_demo.lua
--
-- 逻辑：列出动作 → 依次「翻卡 → 记得」若干张 → 打印状态。

-- 让 require 找到同目录的 wordcard.lua
local dir = arg[0]:match("^(.*)/[^/]+$") or "."
package.path = dir .. "/?.lua;" .. package.path

local wc = require("wordcard")

local c = assert(wc.open())
print("== 可用动作 ==")
for _, id in ipairs(c:actions()) do print("  " .. id) end

print("\n== 状态 ==")
print("  " .. tostring(c:state()))

print("\n== 模拟复习 5 张（翻卡 → 记得） ==")
for i = 1, 5 do
  local before = c:state() or ""
  local word = before:match('"word":"([^"]*)"')
  c:click("review.flip")
  c:click("review.know")
  local after = c:state() or ""
  local done = after:match('"done":(%d+)')
  print(string.format("  #%d  %s  done=%s", i, tostring(word), tostring(done)))
end

c:close()
print("\n完成。")
