-- main.lua — WordCard GUI 主入口
-- wordcard.* 和 cache.* 已由 C 引擎注册到全局，直接调用

local gui = require("gui")

-- ====== 工具函数 ======

function mode_name(m)
    local names = { "flashcard", "choice", "fillblank", "spelling",
                    "dictation", "pronunciation", "matching", "speed_review" }
    return names[m] or "unknown"
end

-- ====== 主学习循环 ======

function run_study(app, db, user_id)
    -- 1. 获取今日学习队列
    local now = wordcard.wc_now()
    local max_count = 50
    local ids = ffi.new("uint32_t[?]", max_count)
    local modes = ffi.new("uint8_t[?]", max_count)

    -- 这里需要 FFI 调用 wc_generate_daily_queue（返回指针参数）
    -- 如果不想用 FFI，可以从 C 引擎注册一个简化版本
    local count = wc_generate_daily_queue(db, user_id, now, ids, modes, max_count)
    -- 简化：先用内置队列
    count = 3  -- 临时 demo

    -- 2. 构造队列
    local queue_items = {}
    for i = 0, count - 1 do
        table.insert(queue_items, {
            item_id = i + 1,
            question = "Sample question " .. (i + 1),
            answer = "Sample answer " .. (i + 1),
            mode = 1,
            mode_name = "flashcard",
            explanation = "",
            hint = "",
        })
    end

    gui.set_queue(app, queue_items)
    if #queue_items > 0 then
        gui.set_current_card(app, queue_items[1].item_id,
                             queue_items[1].question, queue_items[1].answer, queue_items[1].mode)
    end

    -- 3. 初始统计
    gui.set_stats(app, {
        mastered = 3, learning = 5, new_count = 10,
        streak = 7, today_reviewed = 0, today_correct = 0,
    })
end

-- ====== Timer Tick（每帧由 Rust 调用）======

local current_app = nil
local current_db = nil
local current_user = 1
local pending_action = nil

function gui_tick()
    if current_app == nil then return end

    if pending_action then
        local action = pending_action
        pending_action = nil

        if action.type == "flip" then
            gui.flip_card(current_app)

        elseif action.type == "answer" then
            -- 更新统计（demo: 暂时不调 SM-2）
            local stats = gui.get_stats(current_app)
            stats.today_reviewed = (stats.today_reviewed or 0) + 1
            if action.correct then
                stats.today_correct = (stats.today_correct or 0) + 1
            end
            gui.set_stats(current_app, stats)

            gui.set_result(current_app, {
                correct = action.correct,
                overall = action.correct and 85 or 45,
                next_interval = 1,
                repetitions = 2,
                ease_factor = 2.5,
                recommended_mode = "flashcard",
            })

        elseif action.type == "next" then
            local has_next = gui.next_card(current_app)
            if not has_next then
                print("Study session complete!")
            end
        end
    end
end

-- ====== 用户操作回调（由 C 桥接层调用）======

function on_flip_card()
    pending_action = { type = "flip" }
end

function on_submit_answer(text, quality)
    local queue = gui.get_queue(current_app)
    if #queue == 0 then return end
    pending_action = {
        type = "answer",
        correct = quality >= 3,
        item_id = queue[1].item_id or 0,
    }
end

function on_next_card()
    pending_action = { type = "next" }
end

-- ====== 启动入口 ======

function run_gui()
    -- 1. 打开数据库
    local db = wordcard.wc_db_init()
    if db == nil then
        error("Failed to init database")
    end
    current_db = db

    -- 2. 创建/查找用户
    local user_id = wordcard.wc_create_user(db, "default", "Default User")
    if user_id == 0 then
        -- 需要先查找，简化处理
        user_id = 1
    end
    current_user = user_id

    -- 3. 创建 GUI
    local app = gui.create({
        title = "WordCard - Spaced Repetition Learning",
        data_dir = ".",
    })
    current_app = app

    -- 4. 加载队列
    run_study(app, db, user_id)

    -- 5. 进入事件循环（阻塞）
    -- 实际使用时传入 lua_State*，这里简化
    -- 等 lua_engine 集成后改为 gui.run(app, L)
    -- 目前先通过 lua_engine 初始化的方式运行
end

-- 由 C 引擎调用
run_gui()
