-- wordcard.lua — WordCard UI 自动化控制面的 LuaJIT FFI 封装
--
-- 通过 libwordcard_ctl.so 连接 Flutter App 的 Unix socket，用于 AI agent
-- 查询动作/状态、模拟点击。用法：
--
--   local wc = require("wordcard")
--   local c = assert(wc.open())
--   print(table.concat(c:actions(), ", "))  -- 列出可点击动作
--   c:click("review.know")                  -- 模拟点击“记得”
--   print(c:state())                        -- 读取界面状态
--   c:close()

local ffi = require("ffi")

ffi.cdef [[
typedef struct wcctl_t wcctl_t;
wcctl_t* wcctl_open(const char* path);
void     wcctl_close(wcctl_t* c);
int      wcctl_call(wcctl_t* c, const char* req, char* out, int outlen);
int      wcctl_list(wcctl_t* c, char* out, int outlen);
int      wcctl_state(wcctl_t* c, char* out, int outlen);
int      wcctl_ping(wcctl_t* c, char* out, int outlen);
int      wcctl_click(wcctl_t* c, const char* id, char* out, int outlen);
]]

local function _load()
  local root = os.getenv("WORDCARD_ROOT") or "/opt/WordCard"
  local candidates = {
    root .. "/src/libwordcard_ctl.so",
    "libwordcard_ctl.so",
  }
  local env = os.getenv("WCCTL_LIB")
  if env then table.insert(candidates, 1, env) end
  local err
  for _, p in ipairs(candidates) do
    local ok, lib = pcall(ffi.load, p)
    if ok then return lib end
    err = lib
  end
  error("cannot load libwordcard_ctl.so: " .. tostring(err))
end

local lib = _load()

local M = {}
M.__index = M
M.BUF = 1048576 -- 1 MiB

function M.open(path)
  path = path or os.getenv("WC_AUTOMATION_SOCK")
      or "/tmp/wordcard-automation.sock"
  local h = lib.wcctl_open(path)
  if h == nil then return nil, "cannot connect: " .. path end
  return setmetatable({ h = h }, M)
end

function M:raw(req)
  local out = ffi.new("char[?]", M.BUF)
  local n = lib.wcctl_call(self.h, req, out, M.BUF)
  if n < 0 then return nil end
  return ffi.string(out, n)
end

function M:list() return self:raw('{"cmd":"list"}') end
function M:state() return self:raw('{"cmd":"state"}') end
function M:ping() return self:raw('{"cmd":"ping"}') end
function M:click(id)
  return self:raw(('{"cmd":"click","id":"%s"}'):format(id))
end

-- 解析 list 响应，返回动作 id 数组
function M:actions()
  local s = self:list() or ""
  local arr = s:match('"actions":%s*%[(.-)%]')
  local t = {}
  if arr then
    for id in arr:gmatch('"([^"]+)"') do t[#t + 1] = id end
  end
  return t
end

function M:close()
  if self.h ~= nil then
    lib.wcctl_close(self.h)
    self.h = nil
  end
end

return M
