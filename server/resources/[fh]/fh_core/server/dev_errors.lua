-- Dev client-error return: receives fh:dev:clientError from client pcall wrappers (client/safe.lua), validates,
-- rate-limits per source, prints and appends to server/logs/client-errors.log. Active only when convar fh_dev == 1.
-- Cfx infra used (not game natives): GetConvarInt, GetResourcePath, os.date. Not runtime-tested (see docs/natives.md).
local limiter = FhClientErrors.newLimiter()
local logPath -- <server root>/server/logs/client-errors.log, resolved lazily

local function devOn() return GetConvarInt('fh_dev', 0) == 1 end

local function appendLine(line)
    if not logPath then
        -- resource lives in server/resources/[fh]/fh_core: walk up to the server dir
        local base = (GetResourcePath(GetCurrentResourceName()):gsub('\\', '/'))
        local root = base:match('^(.*)/resources/') or base
        logPath = root .. '/logs/client-errors.log'
    end
    local f = io.open(logPath, 'a')
    if not f then
        print(('[fh_core] cannot open %s (create server/logs/)'):format(logPath))
        return
    end
    f:write(line, '\n')
    f:close()
end

RegisterNetEvent('fh:dev:clientError', function(payload)
    local src = source
    if not devOn() then return end
    if type(src) ~= 'number' or src <= 0 then return end
    if not limiter.allow(src, os.time()) then return end
    local clean = FhClientErrors.validate(payload)
    if not clean then return end
    local line = FhClientErrors.formatLine(os.date('!%Y-%m-%dT%H:%M:%SZ'), src, clean)
    print('[fh_core] client error: ' .. line)
    appendLine(line)
end)

AddEventHandler('playerDropped', function() limiter.forget(source) end)

lib.addCommand('fh_clienterr', {
    help = 'Dev: trigger a deliberate client error on yourself (checks fh:dev:clientError -> client-errors.log)',
    restricted = 'group.admin',
}, function(src)
    if src == 0 then return print('[fh_core] fh_clienterr: run it in game') end
    if not devOn() then return TriggerClientEvent('chat:addMessage', src, { args = { 'fh', 'fh_dev is off' } }) end
    TriggerClientEvent('fh:dev:throw', src)
end)
