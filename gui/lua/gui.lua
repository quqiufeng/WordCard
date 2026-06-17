-- gui.lua — WordCard GUI LuaJIT FFI 绑定层
-- 加载 libwordcard_gui.so，提供 Lua 调用的 GUI 接口

local ffi = require("ffi")

-- ====== C ABI 声明（对应 libwordcard_gui.so 导出符号）======

ffi.cdef[[
    // 生命周期
    void* gui_app_create(const char* config_json);
    void  gui_app_free(void* app);
    int   gui_run(void* app, void* lua_state);

    // 学习队列
    void  gui_set_queue(void* app, const char* queue_json);
    char* gui_get_queue(void* app);
    void  gui_set_current_card(void* app, uint32_t item_id,
                               const char* question, const char* answer, uint8_t mode);
    void  gui_flip_card(void* app);
    void  gui_set_answer(void* app, const char* text);
    void  gui_submit_answer(void* app);
    void  gui_set_result(void* app, const char* result_json);
    int   gui_next_card(void* app);
    int   gui_queue_count(void* app);

    // 统计
    void  gui_set_stats(void* app, const char* stats_json);
    char* gui_get_stats(void* app);

    // C -> Lua 回调（由 timer tick 驱动）
    void wordcard_gui_tick(void* lua_state);
    void wordcard_gui_on_flip(void* lua_state);
    void wordcard_gui_on_answer(void* lua_state, const char* text, int quality);
    void wordcard_gui_on_next(void* lua_state);
    void free(void* ptr);
]]

-- ====== 加载共享库 ======

-- 先用 RTLD_GLOBAL 加载 C bridge（提供 wordcard_gui_tick 符号）
ffi.cdef[[int dlopen(const char*, int);]]
local RTLD_GLOBAL = 0x100
local RTLD_NOW = 2
pcall(ffi.C.dlopen, "./libwordcard_tick_stub.so", RTLD_GLOBAL + RTLD_NOW)
pcall(ffi.C.dlopen, "libwordcard_tick_stub.so", RTLD_GLOBAL + RTLD_NOW)

-- 再加载 Rust GUI 库
local loaded, lib = pcall(ffi.load, "libwordcard_gui")
if not loaded then
    loaded, lib = pcall(ffi.load, "./libwordcard_gui.so")
end
if not loaded then
    loaded, lib = pcall(ffi.load, "gpui/target/release/libwordcard_gui.so")
end
if not loaded then
    error("Cannot load libwordcard_gui.so")
end

-- ====== 回调引用保护（防止 Lua GC 回收 C 函数指针）======

local app_handles = {}

-- ====== 应用生命周期 ======

local M = {}

function M.create(config)
    config = config or {}
    local json = require("json").encode(config)
    local handle = lib.gui_app_create(json)
    if handle == nil then
        error("gui_app_create failed")
    end
    app_handles[handle] = { handle = handle }
    return handle
end

function M.free(handle)
    lib.gui_app_free(handle)
    app_handles[handle] = nil
end

function M.run(handle, lua_state)
    return lib.gui_run(handle, lua_state)
end

-- ====== 学习队列 ======

function M.set_queue(handle, items)
    local json = require("json").encode(items)
    lib.gui_set_queue(handle, json)
end

function M.get_queue(handle)
    local cstr = lib.gui_get_queue(handle)
    if cstr == nil then return {} end
    local s = ffi.string(cstr)
    ffi.C.free(cstr)  -- Rust 用 CString::into_raw，需用 C free
    local ok, val = pcall(require("json").decode, s)
    if ok then return val else return {} end
end

function M.set_current_card(handle, item_id, question, answer, mode)
    lib.gui_set_current_card(handle, item_id, question, answer, mode)
end

function M.flip_card(handle)
    lib.gui_flip_card(handle)
end

function M.set_answer(handle, text)
    lib.gui_set_answer(handle, text)
end

function M.submit_answer(handle)
    lib.gui_submit_answer(handle)
end

function M.set_result(handle, result)
    local json = require("json").encode(result)
    lib.gui_set_result(handle, json)
end

function M.next_card(handle)
    local ret = lib.gui_next_card(handle)
    return ret ~= 0  -- true=还有下一张, false=队列已空
end

function M.queue_count(handle)
    return tonumber(lib.gui_queue_count(handle))
end

-- ====== 统计 ======

function M.set_stats(handle, stats)
    local json = require("json").encode(stats)
    lib.gui_set_stats(handle, json)
end

function M.get_stats(handle)
    local cstr = lib.gui_get_stats(handle)
    if cstr == nil then return {} end
    local s = ffi.string(cstr)
    ffi.C.free(cstr)
    local ok, val = pcall(require("json").decode, s)
    if ok then return val else return {} end
end

return M
