-- Pure formatter for rsg-log:server:CreateLog entries. No natives: specced under spec/fh_log_spec.lua.
local M = {}

local function safeToString(v)
    if v == nil then return nil end
    local ok, s = pcall(tostring, v)
    if not ok or type(s) ~= 'string' then return '<unprintable>' end
    return s
end

-- Collapse newlines and control characters so every log entry is strictly one line.
function M.sanitize(v, fallback)
    local s = safeToString(v)
    if not s then return fallback or '' end
    s = s:gsub('[ \t]*[\r\n]+[ \t]*', ' '):gsub('[%c]', ' ')
    s = s:match('^%s*(.-)%s*$') or ''
    if s == '' and fallback ~= nil then return fallback end
    return s
end

---Format one audit log line. Never errors on nil or non-string arguments.
---@param iso any UTC ISO timestamp string
---@param channel any rsg-log channel name
---@param title any entry title
---@param color any color name/value
---@param msg any message body
---@param tagEveryone any boolean-ish flag
---@return string
function M.formatLine(iso, channel, title, color, msg, tagEveryone)
    local ts = M.sanitize(iso, '-')
    local ch = M.sanitize(channel, 'default')
    local col = M.sanitize(color, '-')
    local t = M.sanitize(title, '-')
    local m = M.sanitize(msg, '')
    local tag = (tagEveryone == true) and ' [tagEveryone]' or ''
    if m == '' then
        return ('%s [%s] (%s) %s%s'):format(ts, ch, col, t, tag)
    end
    return ('%s [%s] (%s) %s: %s%s'):format(ts, ch, col, t, m, tag)
end

if GetCurrentResourceName then
    FhLogFormat = M
else
    return M
end
