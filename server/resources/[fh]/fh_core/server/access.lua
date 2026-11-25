-- Private-server access (B-access): first-joiner auto-admin and the friend allowlist. Rules: shared/access_rules.lua.
-- Natives / Cfx functions: GetPlayerIdentifierByType, GetPlayerName, IsPlayerAceAllowed, GetPlayers, ExecuteCommand,
-- GetConvar, GetResourcePath, LoadResourceFile, SaveResourceFile (see docs/natives.md: unverified in-game).
--
-- Durable claim (x1 fix): fh_core/access.txt via LoadResourceFile/SaveResourceFile. Lua io on the server dir failed
-- live on Windows (admins.cfg existed but io.open returned nil), so success never depends on io. At resource start
-- every valid store entry is re-applied with ExecuteCommand('add_principal ...') (server.cfg grants
-- resource.fh_core command.add_principal). admins.cfg / allowlist.cfg stay owner-editable overrides that server.cfg
-- execs at boot; fh_core reads admins.cfg (if it can) for the lock and best-effort appends to both, logging io errors.
--
-- Connect order: the playerConnecting handler below does the grant (ExecuteCommand + verified write) synchronously,
-- before any yield. rsg-core's handler yields (Wait(0), rsg-core/server/events.lua:139) before its whitelist check
-- (events.lua:141), so whichever handler the runtime calls first, the grant lands before rsg-core checks.
-- Rejection is rsg-core's alone (deferrals.done(locale 'error.not_whitelisted')); this handler never defers, it only
-- prints the `allowlist: rejected` console line so the owner can copy the ID.
-- Only server events trigger a grant; there is no net event.
local R = FhAccessRules
local RES = GetCurrentResourceName()
local state
local serverDir

local function log(msg) print('[fh_core] ' .. msg) end

local function dir()
    if not serverDir then
        local base = (GetResourcePath(RES):gsub('\\', '/'))
        serverDir = base:match('^(.*)/resources/') or base
    end
    return serverDir
end

-- Lua's io error string usually starts with the path already; always return 'path: error'.
local function ioErr(path, err)
    err = tostring(err)
    if err:sub(1, #path) == path then return err end
    return path .. ': ' .. err
end

-- Server-dir cfg read. Returns text, or nil + 'path: error' (callers log it; never swallowed).
local function readCfg(name)
    local path = dir() .. '/' .. name
    local f, err = io.open(path, 'rb')
    if not f then return nil, ioErr(path, err) end
    local text = f:read('a')
    f:close()
    if text == nil then return nil, path .. ': read failed' end
    return text
end

-- Best-effort append of a principal line to a server-dir cfg (idempotent). Logs every io error; the result is
-- informational only, the store write decides success.
local function appendCfg(name, line)
    local text, rerr = readCfg(name)
    if not text then
        log('access: could not read ' .. rerr .. ' (entry kept in fh_core/' .. R.STORE_FILE .. ')')
        return false
    end
    local add = R.appendText(text, line)
    if not add then return true end
    local path = dir() .. '/' .. name
    local f, err = io.open(path, 'ab')
    if not f then
        log('access: could not write ' .. ioErr(path, err) .. ' (entry kept in fh_core/' .. R.STORE_FILE .. ')')
        return false
    end
    local ok, werr = f:write(add)
    f:close()
    if not ok then
        log('access: could not write ' .. ioErr(path, werr) .. ' (entry kept in fh_core/' .. R.STORE_FILE .. ')')
        return false
    end
    return true
end

local function loadStore()
    return R.parseStore(LoadResourceFile(RES, R.STORE_FILE))
end

-- Adds kind/id to the resource store and verifies it by re-reading. Returns true only when the entry is on disk.
local function storeAdd(kind, id)
    local store = loadStore()
    local added, err = R.storeAdd(store, kind, id)
    if added == nil then
        log('access: refused to store ' .. kind .. ' entry: ' .. tostring(err))
        return false
    end
    if added and not SaveResourceFile(RES, R.STORE_FILE, R.storeText(store), -1) then
        log('access: SaveResourceFile failed for fh_core/' .. R.STORE_FILE)
        return false
    end
    if not R.storeHas(loadStore(), kind, id) then -- a failed re-read is a failed persist
        log('access: fh_core/' .. R.STORE_FILE .. ' re-read does not contain ' .. kind .. ' ' .. tostring(id))
        return false
    end
    return true
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

-- Boot: re-apply the store, then compute the lock (store decides; admins.cfg is read only if it can be).
do
    local store = loadStore()
    for _, b in ipairs(store.bad) do
        log(('access: ignored malformed %s entry at fh_core/%s line %d'):format(b.kind, R.STORE_FILE, b.line))
    end
    for _, line in ipairs(R.bootLines(store)) do ExecuteCommand(line) end
    if #store.admins + #store.allow > 0 then
        log(('access: re-applied %d admin and %d allowlist entries from fh_core/%s'):format(#store.admins,
            #store.allow, R.STORE_FILE))
    end
    local cfg, cfgErr = readCfg('admins.cfg')
    if cfgErr then log('autoadmin: cannot read admins.cfg (path: ' .. cfgErr .. ')') end
    local msg
    state, msg = R.initialState(cfg, store)
    if msg then log(msg) end
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
        persist = function(line, license)
            local ok = storeAdd('admin', license)
            appendCfg('admins.cfg', line)
            return ok
        end,
        isAllowed = function() return ace ~= nil and IsPlayerAceAllowed(src, ace) end,
        adminExists = function()
            if IsPlayerAceAllowed(src, R.ADMIN_ACE) then return true end
            for _, p in ipairs(GetPlayers()) do
                if IsPlayerAceAllowed(p, R.ADMIN_ACE) then return true end
            end
            return false
        end,
        log = function(msg) print(msg) end,
    })
end)

local function reply(src, msg)
    if src == 0 then print('[fh_core] ' .. msg) else TriggerClientEvent('chat:addMessage', src, { args = { 'fh', msg } }) end
end

-- fh_allow <license:hash | hash | discord:id>: owner-only, applies live and persists to fh_core/access.txt
-- (best-effort copy in allowlist.cfg).
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
    local ok = storeAdd('allow', id)
    appendCfg('allowlist.cfg', line)
    if ok then
        print('allowlist: added ' .. id)
        reply(src, 'fh_allow: added ' .. id .. '; they can reconnect now')
    else
        print('allowlist: added ' .. id .. ' live only; could not save fh_core/' .. R.STORE_FILE)
        reply(src, 'fh_allow: ' .. id .. ' allowed until restart (could not save fh_core/' .. R.STORE_FILE .. ')')
    end
end)

-- world-04 M: may this player see place ids in /where and fh_tour? Decided here, on the server: an admin (holds
-- R.ADMIN_ACE) or any player while convar fh_dev == 1. The client only receives the answer; it never supplies it.
local function canSeeIds(src)
    src = tonumber(src)
    if not src then return false end
    if GetConvarInt('fh_dev', 0) == 1 then return true end
    return src > 0 and IsPlayerAceAllowed(src, R.ADMIN_ACE) == true
end
exports('canSeeIds', canSeeIds)
