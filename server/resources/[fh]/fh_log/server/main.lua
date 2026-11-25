-- Minimal rsg-log provider: listens for server-internal rsg-log:server:CreateLog events,
-- prints one console line and appends to server/logs/audit.log (creating server/logs if missing).
-- Follows fh_core/server/dev_errors.lua's path resolution and file append approach.
-- Cfx infra used (not game natives): GetResourcePath, GetCurrentResourceName, os.date.
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

local function appendLine(line)
    resolvePaths()
    local f, err = io.open(logPath, 'a')
    if not f then
        ensureDir(logDir)
        f, err = io.open(logPath, 'a')
    end
    if not f then
        if not warnedOpen then
            warnedOpen = true
            print(('[fh_log] cannot open %s: %s'):format(logPath, tostring(err)))
        end
        return
    end
    f:write(line, '\n')
    f:close()
end

-- Server-internal only (AddEventHandler, never RegisterNetEvent) so clients cannot forge/flood audit.log.
AddEventHandler('rsg-log:server:CreateLog', function(channel, title, color, msg, tagEveryone)
    local iso = (type(os) == 'table' and type(os.date) == 'function') and os.date('!%Y-%m-%dT%H:%M:%SZ') or '-'
    local line = FhLogFormat.formatLine(iso, channel, title, color, msg, tagEveryone)
    print('[fh_log] ' .. line)
    appendLine(line)
end)
