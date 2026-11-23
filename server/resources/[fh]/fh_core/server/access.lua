-- Private-server access (B-access): first-joiner auto-admin and the friend allowlist. Rules: shared/access_rules.lua.
-- Natives / Cfx functions: GetPlayerIdentifierByType, GetPlayerName, IsPlayerAceAllowed, ExecuteCommand, GetConvar,
-- GetResourcePath (see docs/natives.md: unverified in-game). Lua io writes admins.cfg / allowlist.cfg in the
-- server dir (the cwd that server.cfg `exec`s them from).
--
-- Connect order: the playerConnecting handler below does the grant (ExecuteCommand + verified write) synchronously,
-- before any yield. rsg-core's handler yields (Wait(0), rsg-core/server/events.lua:139) before its whitelist check
-- (events.lua:141), so whichever handler the runtime calls first, the grant lands before rsg-core checks.
-- Rejection is rsg-core's alone (deferrals.done(locale 'error.not_whitelisted')); this handler never defers, it only
-- prints the `allowlist: rejected` console line so the owner can copy the ID.
-- Only server events trigger a grant; there is no net event.
local R = FhAccessRules
local state
local serverDir

local function dir()
    if not serverDir then
        local base = (GetResourcePath(GetCurrentResourceName()):gsub('\\', '/'))
        serverDir = base:match('^(.*)/resources/') or base
    end
    return serverDir
end

local function readFile(name)
    local f = io.open(dir() .. '/' .. name, 'rb')
    if not f then return nil end
    local text = f:read('a')
    f:close()
    return text
end

-- Appends `line` (idempotent) and re-reads the file to verify. Returns true only when the line is on disk.
local function persistLine(name, line)
    local add = R.appendText(readFile(name) or '', line)
    if add then
        local f = io.open(dir() .. '/' .. name, 'ab')
        if not f then return false end
        local ok = f:write(add)
        f:close()
        if not ok then return false end
    end
    return R.persistVerified(readFile(name), line) -- a failed re-read is a failed persist
end

local function convars()
    return { fh_dev = GetConvar('fh_dev', '0'), fh_dev_autoadmin = GetConvar('fh_dev_autoadmin', '0') }
end

local function rsgWhitelist()
    if GetResourceState('rsg-core') ~= 'started' then return false, nil end
    local ok, core = pcall(function() return exports['rsg-core']:GetCoreObject() end)
    local cfg = ok and core and core.Config and core.Config.Server
    if not cfg then return false, nil end
    return cfg.Whitelist == true, cfg.WhitelistPermission
end

do
    local err
    state, err = R.initialState(readFile('admins.cfg')) -- nil (missing/unreadable) fails closed: locked, no grant
    if err then print('[fh_core] ' .. err .. ' (path: ' .. dir() .. '/admins.cfg)') end
end

AddEventHandler('playerConnecting', function(name)
    local src = source
    local whitelistOn, ace = rsgWhitelist()
    R.onConnect(state, convars(), {
        license = GetPlayerIdentifierByType(src, 'license'),
        discord = GetPlayerIdentifierByType(src, 'discord'),
        name = name,
        whitelistOn = whitelistOn,
    }, {
        execute = function(cmd) ExecuteCommand(cmd) end,
        persist = function(line) return persistLine('admins.cfg', line) end,
        isAllowed = function() return ace ~= nil and IsPlayerAceAllowed(src, ace) end,
        log = function(msg) print(msg) end,
    })
end)

local function reply(src, msg)
    if src == 0 then print('[fh_core] ' .. msg) else TriggerClientEvent('chat:addMessage', src, { args = { 'fh', msg } }) end
end

-- fh_allow <license:hash | hash | discord:id>: owner-only, applies live and persists to allowlist.cfg.
lib.addCommand('fh_allow', {
    help = 'Allowlist a friend: fh_allow <license:hash | hash | discord:id> (copy it from the "allowlist: rejected" line)',
    restricted = 'group.admin',
}, function(src, args, raw)
    local toks = {}
    for tok in tostring(raw or ''):gmatch('%S+') do toks[#toks + 1] = tok end
    if #toks ~= 2 then return reply(src, 'fh_allow: usage fh_allow <license:hash>') end
    local id, err = R.parseIdentifier(toks[2])
    if not id then return reply(src, 'fh_allow: ' .. err) end
    local line = R.principalLine(id, R.ALLOW_GROUP)
    ExecuteCommand(line)
    if persistLine('allowlist.cfg', line) then
        print('allowlist: added ' .. id)
        reply(src, 'fh_allow: added ' .. id .. '; they can reconnect now')
    else
        print('allowlist: added ' .. id .. ' live only; could not write allowlist.cfg')
        reply(src, 'fh_allow: ' .. id .. ' allowed until restart (could not write allowlist.cfg)')
    end
end)
