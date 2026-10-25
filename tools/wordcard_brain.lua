-- wordcard_brain.lua — 用 LuaJIT + FFI(libxdo) 打开一个可见终端，里面跑 tmux
--
-- 终端窗口里是 WordCard 专用 tmux 会话（不碰 my-agent）：
--   window 0: tui    opencode attach http://127.0.0.1:4098   ← 默认显示
--   window 1: serve  opencode serve --port 4098
--   window 2: llama  llama-server + Hunyuan-MT-7B (:8081)
-- 用 xdo.lua / x11.lua（libxdo FFI）找到终端窗口并激活/摆到屏幕右侧。

package.path = "/opt/WordCard/gui/flutter/automation/?.lua;" .. package.path
local ffi = require("ffi")
local x11 = require("x11")

ffi.cdef [[
int fork(void);
int execvp(const char *file, char *const argv[]);
int setsid(void);
]]

local ROOT = os.getenv("WORDCARD_ROOT") or "/opt/WordCard"
local SESSION = os.getenv("WORDCARD_BRAIN_SESSION") or "wordcard-brain"
local PORT = tonumber(os.getenv("WORDCARD_BRAIN_PORT") or "4098")
local URL = "http://127.0.0.1:" .. PORT
local TERM = os.getenv("WC_TERMINAL") or "xterm"

local function sh(cmd)
    local f = io.popen(cmd .. " 2>/dev/null")
    if not f then return "" end
    local out = f:read("*a") or ""
    f:close()
    return (out:gsub("%s+$", ""))
end

local function q(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function healthy()
    return os.execute(("curl -sf --max-time 2 %s/global/health >/dev/null 2>&1"):format(URL)) == 0
end

local function has_session()
    return os.execute(("tmux has-session -t %s >/dev/null 2>&1"):format(SESSION)) == 0
end

local function window_exists(name)
    return sh(("tmux list-windows -t %s -F '#{window_name}'"):format(SESSION))
        :find("\n" .. name .. "\n", 1, true) ~= nil
        or sh(("tmux list-windows -t %s -F '#{window_name}'"):format(SESSION)) == name
end

local function spawn(argv)
    local pid = ffi.C.fork()
    if pid == 0 then
        ffi.C.setsid()
        local c = ffi.new("char *[?]", #argv + 1)
        for i, a in ipairs(argv) do c[i - 1] = ffi.cast("char *", a) end
        c[#argv] = nil
        ffi.C.execvp(argv[1], c)
        os.exit(127)
    end
    return pid
end

local function term_cmd(title, geometry, body)
    if TERM:match("xterm") then
        return { TERM, "-fa", "DejaVu Sans Mono", "-fs", "11",
                 "-geometry", geometry, "-T", title,
                 "-e", "bash", "-lc", body }
    end
    return { TERM, "-w", ROOT, "-e", "bash", "-lc",
             ([[printf '\033]0;%s\007'; %s]]):format(title, body) }
end

local function find(title)
    local w = x11.window(title, { exact = true })
    if w then return w end
    -- xterm 的 WM_NAME 在不同 locale 下可能把 · 编坏；按 WM_CLASS 回退
    if title == "WordCard Brain" then
        for _, x in ipairs(x11.display():find_class("xterm")) do
            if (x.name or ""):find("WordCard", 1, true) then
                return x11.wrap(x.id, x.name):refresh()
            end
        end
    end
    return nil
end

local function opencode_bin()
    local p = sh("command -v opencode")
    return p ~= "" and p or "opencode"
end

local function serve_cmd()
    return ("tmux new-session -d -s %s -n serve %s"):format(
        SESSION,
        q(("cd %s && %s serve --port %d; echo; echo '[serve exited] press Enter'; read _")
            :format(q(ROOT), q(opencode_bin()), PORT)))
end

local function tui_cmd()
    return ("tmux new-window -d -t %s -n tui %s"):format(
        SESSION,
        q(("cd %s && %s attach %s; echo; echo '[TUI exited] press Enter'; read _")
            :format(q(ROOT), q(opencode_bin()), URL)))
end

local function ensure_session()
    if healthy() and has_session() then return end
    os.execute(("tmux kill-session -t %s 2>/dev/null"):format(SESSION))
    os.execute(serve_cmd())
    for _ = 1, 80 do
        if healthy() then break end
        os.execute("sleep 0.25")
    end
    os.execute(tui_cmd())
    -- 让 TUI 成为第一个窗口
    os.execute(("tmux swap-window -s %s:serve -t %s:tui 2>/dev/null"):format(SESSION, SESSION))
    os.execute(("tmux select-window -t %s:tui 2>/dev/null"):format(SESSION))
end

local function ensure_tui_window()
    if not has_session() then return end
    local names = sh(("tmux list-windows -t %s -F '#{window_name}'"):format(SESSION))
    if not names:find("tui", 1, true) then
        os.execute(tui_cmd())
        os.execute(("tmux swap-window -s %s:serve -t %s:tui 2>/dev/null"):format(SESSION, SESSION))
    end
    -- TUI attach 死了就重启该窗口
    local proc = sh(("pgrep -f 'opencode attach %s' | head -1"):format(URL))
    if proc == "" then
        os.execute(("tmux respawn-window -k -t %s:tui %s"):format(
            SESSION,
            q(("cd %s && %s attach %s; echo; echo '[TUI exited] press Enter'; read _")
                :format(q(ROOT), q(opencode_bin()), URL))))
    end
    os.execute(("tmux select-window -t %s:tui 2>/dev/null"):format(SESSION))
    os.execute("tmux set-option -g set-titles off 2>/dev/null")
end

local function llama_healthy()
    return os.execute("curl -sf --max-time 2 http://127.0.0.1:8081/health >/dev/null 2>&1") == 0
end

local function ensure_llama_window()
    if not has_session() then return end
    local names = sh(("tmux list-windows -t %s -F '#{window_name}'"):format(SESSION))
    local has_llama = names:find("llama", 1, true) ~= nil
    if llama_healthy() then
        if not has_llama then
            -- 已在外部启动：保留第三个 tab，作为状态窗口
            os.execute(("tmux new-window -d -t %s -n llama %s"):format(
                SESSION,
                q("echo 'llama-server already running on :8081'; echo; echo 'PID:'; pgrep -a llama-server; echo; echo 'Switch tabs: Ctrl+b 0/1/2'; read _")))
        end
        return
    end
    local app_pid = sh("pgrep -x wordcard | head -1")
    if app_pid == "" then app_pid = tostring(ffi.C.getppid()) end
    local body = ("cd %s && ./tools/llama_terminal.sh %s; echo; echo '[llama exited]'; read _")
        :format(q(ROOT), app_pid)
    if has_llama then
        os.execute(("tmux respawn-window -k -t %s:llama %s"):format(SESSION, q(body)))
    else
        os.execute(("tmux new-window -d -t %s -n llama %s"):format(SESSION, q(body)))
    end
end

local function ensure_terminal()
    local win = find("WordCard Brain")
    local clients = sh(("tmux list-clients -t %s 2>/dev/null"):format(SESSION))
    if win and clients ~= "" then return win end
    local body = ("tmux attach -t %s; echo; echo '[tmux exited] press Enter'; read _"):format(SESSION)
    spawn(term_cmd("WordCard Brain", "140x38", body))
    for _ = 1, 30 do
        win = find("WordCard Brain")
        if win then break end
        os.execute("sleep 0.5")
    end
    return win
end

local function place(w)
    if not w then return end
    w:activate()
    local sw, sh = x11.display():display_size()
    local x = math.max(0, sw - (w.w or 0) - 24)
    local y = math.max(0, math.min(60, sh - (w.h or 0) - 24))
    w:move(x, y)
    w:activate()
end

ensure_session()
ensure_tui_window()
ensure_llama_window()
local term = ensure_terminal()
place(term)

if term then
    print("Brain terminal ready: " .. tostring(term.id))
else
    print("Brain terminal not found")
end
