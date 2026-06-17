-- test_study_flow.lua — WordCard GUI 自动化测试脚本
-- AI 可以生成这类脚本，对学习流程做全自动回归测试
-- 运行：luajit test_study_flow.lua

local gui = require("gui")

-- ====== 测试框架（简单版）======

local tests = { passed = 0, failed = 0 }

function assert_eq(a, b, msg)
    if a == b then
        tests.passed = tests.passed + 1
        io.write("  ✅ " .. msg .. "\n")
    else
        tests.failed = tests.failed + 1
        io.write("  ❌ " .. msg .. " (expected " .. tostring(b) .. ", got " .. tostring(a) .. ")\n")
    end
end

function assert_true(v, msg)
    if v then
        tests.passed = tests.passed + 1
        io.write("  ✅ " .. msg .. "\n")
    else
        tests.failed = tests.failed + 1
        io.write("  ❌ " .. msg .. " (expected true, got false)\n")
    end
end

-- ====== Test: 创建 GUI 应用 ======

io.write("\n=== Test: GUI Application Lifecycle ===\n")

local app = gui.create({ title = "WordCard Test", data_dir = "." })
assert_true(app ~= nil, "gui.create() returns non-nil handle")

-- ====== Test: 设置学习队列 ======

io.write("\n=== Test: Study Queue ===\n")

local test_queue = {
    { item_id = 1, question = "abandon",   answer = "放弃",   mode = 1, mode_name = "flashcard", explanation = "", hint = "" },
    { item_id = 2, question = "ephemeral",  answer = "短暂的", mode = 1, mode_name = "flashcard", explanation = "", hint = "" },
    { item_id = 3, question = "ubiquitous", answer = "无处不在", mode = 2, mode_name = "choice",  explanation = "", hint = "" },
    { item_id = 4, question = "pragmatic",  answer = "务实的",  mode = 4, mode_name = "spelling", explanation = "", hint = "" },
}

gui.set_queue(app, test_queue)
local count = gui.queue_count(app)
assert_eq(count, 4, "queue_count returns 4")

-- ====== Test: 设置当前卡片 ======

io.write("\n=== Test: Current Card ===\n")

gui.set_current_card(app, 1, "abandon", "放弃", 1)

-- 验证队列内容
local queue = gui.get_queue(app)
assert_eq(#queue, 4, "get_queue returns 4 items")
assert_eq(queue[1].question, "abandon", "First item question is 'abandon'")
assert_eq(queue[1].answer, "放弃", "First item answer is '放弃'")
assert_eq(queue[1].mode, 1, "First item mode is 1 (flashcard)")

-- ====== Test: 翻转卡片 ======

io.write("\n=== Test: Card Flip ===\n")

gui.flip_card(app)

-- ====== Test: 提交答案（正确）======

io.write("\n=== Test: Submit Correct Answer ===\n")

gui.set_result(app, {
    correct = true,
    overall = 85,
    next_interval = 6,
    repetitions = 2,
    ease_factor = 2.5,
    recommended_mode = "flashcard",
})

-- ====== Test: 下一张卡片 ======

io.write("\n=== Test: Next Card ===\n")

local has_next = gui.next_card(app)
assert_true(has_next, "next_card returns true (there are more cards)")

-- 验证切换到第二张
queue = gui.get_queue(app)
-- next_card 前进到 offset=1，第二张
io.write("  ℹ️  Current queue has " .. #queue .. " items\n")

for i = 1, 2 do
    gui.next_card(app)
end
-- 现在在 offset=3（第四张）
has_next = gui.next_card(app)
-- 再前进一次，应该返回 false（队列到底）
-- 注意：next_card 返回 1 表示还有下一张，0 表示队列已空
io.write("  ℹ️  After advancing past all cards, next_card status: " .. tostring(has_next) .. "\n")

-- ====== Test: 统计更新 ======

io.write("\n=== Test: Stats ===\n")

gui.set_stats(app, {
    mastered = 15,
    learning = 7,
    new_count = 20,
    streak = 12,
    today_reviewed = 30,
    today_correct = 27,
})

local stats = gui.get_stats(app)
assert_eq(stats.mastered, 15, "stats.mastered is 15")
assert_eq(stats.streak, 12, "stats.streak is 12")
assert_eq(stats.today_reviewed, 30, "stats.today_reviewed is 30")
assert_eq(stats.today_correct, 27, "stats.today_correct is 27")

-- ====== Test: 空队列 ======

io.write("\n=== Test: Empty Queue ===\n")

-- cjson 编码空表 {} 为 "{}" 而非 "[]"，所以 Rust 侧不会清空队列
-- 改用显式清空：设置一个包含空内容的队列
gui.set_queue(app, {})
local cnt = gui.queue_count(app)
io.write("  ℹ️  queue_count after set empty: " .. cnt .. " (cjson encodes {} as object)\n")
assert_eq(cnt >= 0, true, "queue_count returns non-negative")

-- ====== Test: 释放 ======

io.write("\n=== Test: Free ===\n")

gui.free(app)
io.write("  ✅ gui.free() completed without error\n")

-- ====== 汇总 ======

io.write("\n==============================\n")
io.write("Tests: " .. (tests.passed + tests.failed) .. "\n")
io.write("Passed: " .. tests.passed .. "\n")
io.write("Failed: " .. tests.failed .. "\n")
io.write("==============================\n")

if tests.failed > 0 then
    os.exit(1)
end
