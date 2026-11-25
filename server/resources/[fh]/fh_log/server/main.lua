-- Minimal rsg-log provider: listens for server-internal rsg-log:server:CreateLog events,
-- prints one console line and appends to server/logs/audit.log (creating server/logs if missing; buffered, size-capped
-- with one rotation to audit.log.1). Follows fh_core/server/dev_errors.lua's path resolution and file append approach.
-- Cfx infra used (not game natives): GetResourcePath, GetCurrentResourceName, GetConvarInt, SetTimeout, os.date.
local logDir
local logPath
local dirChecked = false
local warnedOpen = false

local function resolvePaths()
    if logPath then return end
    -- resource lives in server/resources/[fh]/fh_log: walk up to the server dir
    local base = (GetResourcePath(GetCurrentResourceName()):gsub('\\', '/'))
    local root = base:match('^(.*)/resources/') or base
    logDir = root .. '/logs'
    logPath = logDir .. '/audit.log'
end

local function ensureDir(dir)
    if dirChecked then return end
    dirChecked = true
    if type(os) ~= 'table' or type(os.execute) ~= 'function' then return end
    local isWin = type(package) == 'table' and type(package.config) == 'string' and package.config:sub(1, 1) == '\\'
    local cmd
    if isWin then
        cmd = 'mkdir "' .. dir:gsub('/', '\\') .. '" >nul 2>&1'
    else
        cmd = "mkdir -p '" .. dir:gsub("'", "'\\''") .. "' >/dev/null 2>&1"
    end
    pcall(os.execute, cmd)
end

-- core-09 N1: lines are buffered and written in one open/write/close per flush (every FLUSH_MS, when the buffer reaches
-- FLUSH_LINES, and on fh_log's onResourceStop), not one per event. audit.log is capped: a flush that would take it past
-- maxBytes first moves it to audit.log.1 (an older .1 is overwritten), so the logs never hold more than ~2x the cap.
-- Cap in KB from the convar fh_log_max_kb (default 5120 = 5 MB).
local FLUSH_MS = 2000
local FLUSH_LINES = 500
local pending, scheduled = {}, false
local warnedRotate = false

local function maxBytes()
    local kb = (type(GetConvarInt) == 'function') and tonumber(GetConvarInt('fh_log_max_kb', 5120)) or 5120
    if not kb or kb < 1 then kb = 5120 end
    return math.floor(kb) * 1024
end

local function warnOpen(err)
    if warnedOpen then return end
    warnedOpen = true
    print(('[fh_log] cannot open %s: %s'):format(logPath, tostring(err)))
end

local function openAppend()
    local f, err = io.open(logPath, 'a')
    if not f then
        ensureDir(logDir)
        f, err = io.open(logPath, 'a')
    end
    return f, err
end

-- one rotation: audit.log -> audit.log.1 (os.rename does not replace an existing target on Windows: remove it first)
local function rotate()
    local old = logPath .. '.1'
    pcall(os.remove, old)
    local ok, renamed, err = pcall(os.rename, logPath, old)
    if ok and renamed then return true end
    if not warnedRotate then
        warnedRotate = true
        print(('[fh_log] cannot rotate %s: %s'):format(logPath, tostring(ok and err or renamed)))
    end
    return false
end

local function flush()
    scheduled = false
    if #pending == 0 then return end
    local chunk = table.concat(pending, '\n') .. '\n'
    pending = {}
    resolvePaths()
    local f, err = openAppend()
    if not f then
        warnOpen(err)
        return
    end
    local size = f:seek('end') or 0
    if size > 0 and size + #chunk > maxBytes() then
        f:close()
        rotate() -- if it fails, keep appending to the same file (warned once) rather than drop lines
        f, err = openAppend()
        if not f then
            warnOpen(err)
            return
        end
    end
    f:write(chunk)
    f:close()
end

local function appendLine(line)
    pending[#pending + 1] = line
    if #pending >= FLUSH_LINES then
        flush()
    elseif not scheduled then
        scheduled = true
        SetTimeout(FLUSH_MS, flush)
    end
end

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then flush() end
end)

-- Server-internal only (AddEventHandler, never RegisterNetEvent) so clients cannot forge/flood audit.log.
AddEventHandler('rsg-log:server:CreateLog', function(channel, title, color, msg, tagEveryone)
    local iso = (type(os) == 'table' and type(os.date) == 'function') and os.date('!%Y-%m-%dT%H:%M:%SZ') or '-'
    local line = FhLogFormat.formatLine(iso, channel, title, color, msg, tagEveryone)
    print('[fh_log] ' .. line)
    appendLine(line)
end)
