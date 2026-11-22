-- Pure helpers for the dev client-error return (fh:dev:clientError). No natives: specced under busted.
-- Client sends { resource, msg, traceback }; the server validates, rate-limits per source and logs a line.
local M = {}

M.MAX_RESOURCE = 64
M.MAX_MSG = 512
M.MAX_TRACEBACK = 2048
M.RATE_MAX = 10      -- events per window per source
M.RATE_WINDOW = 60   -- seconds

local function clip(s, n)
    if #s > n then return s:sub(1, n) .. '...' end
    return s
end

-- One log line: no raw newlines/control chars, so a client cannot forge extra log lines.
local function oneLine(s)
    return (s:gsub('[%c]', function(c) return c == '\n' and '\92n' or c == '\t' and ' ' or '?' end))
end

---@return table|nil clean { resource, msg, traceback }
---@return string|nil err
function M.validate(p)
    if type(p) ~= 'table' then return nil, 'fh_bad_payload' end
    if type(p.resource) ~= 'string' or p.resource == '' then return nil, 'fh_bad_resource' end
    if type(p.msg) ~= 'string' then return nil, 'fh_bad_msg' end
    local tb = p.traceback
    if tb == nil then tb = '' end
    if type(tb) ~= 'string' then return nil, 'fh_bad_traceback' end
    return {
        resource = oneLine(clip(p.resource, M.MAX_RESOURCE)),
        msg = oneLine(clip(p.msg, M.MAX_MSG)),
        traceback = oneLine(clip(tb, M.MAX_TRACEBACK)),
    }
end

-- Fixed-window limiter. allow(key, now) -> boolean; `now` in seconds (caller supplies the clock).
function M.newLimiter(max, window)
    max, window = max or M.RATE_MAX, window or M.RATE_WINDOW
    local slots = {}
    local self = {}
    function self.allow(key, now)
        local s = slots[key]
        if not s or now - s.start >= window then
            s = { start = now, n = 0 }
            slots[key] = s
        end
        if s.n >= max then return false end
        s.n = s.n + 1
        return true
    end
    function self.forget(key) slots[key] = nil end
    return self
end

function M.formatLine(iso, src, clean)
    return ('%s src=%s resource=%s msg=%s traceback=%s'):format(
        tostring(iso), tostring(src), clean.resource, clean.msg, clean.traceback)
end

if GetCurrentResourceName then
    FhClientErrors = M
else
    return M
end
