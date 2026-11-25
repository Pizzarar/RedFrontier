-- Stubbed-server spec (core x1): loads fh_core's real server/access.lua with fake natives (LoadResourceFile /
-- SaveResourceFile in memory, a fake Lua io, ExecuteCommand recorder) and drives boot, playerConnecting and fh_allow.
-- Focus: the durable claim lives in fh_core/access.txt (not server-dir io), io errors are logged, and only
-- validated principal lines ever reach ExecuteCommand. Not a substitute for a live boot.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local case = T.it
local A = require('access_rules')
local SERVER = here .. '../server/resources/[fh]/fh_core/server/access.lua'

local OWNER = 'license:' .. string.rep('a1', 20)
local FRIEND = 'license:' .. string.rep('b2', 20)
local SRV_DIR = 'C:/Users/<user>/Servers/RedFrontier/server'
local STRICT = '^add_principal identifier%.license:%x+ group%.[%w_]+$'

-- opts: store = access.txt text|nil, cfg = { ['admins.cfg'] = text } (nil entry = io.open fails), saveFails,
-- aces = { [src] = { ace = true } }, players = { src... }, convars.
local function boot(opts)
    opts = opts or {}
    local w = { files = { [A.STORE_FILE] = opts.store }, cfg = opts.cfg or {}, exec = {}, logs = {}, handlers = {},
        cmds = {}, chat = {} }
    local env = setmetatable({}, { __index = _G })
    env.FhAccessRules = A
    env.GetCurrentResourceName = function() return 'fh_core' end
    env.GetResourcePath = function() return (SRV_DIR .. '/resources/[fh]/fh_core'):gsub('/', '\\') end
    env.LoadResourceFile = function(res, name) assert(res == 'fh_core') return w.files[name] end
    env.SaveResourceFile = function(res, name, data, len)
        assert(res == 'fh_core' and len == -1)
        if opts.saveFails then return false end
        w.files[name] = data
        return true
    end
    env.io = {
        open = function(path, mode)
            local name = path:match('[^/]+$')
            if w.cfg[name] == nil then return nil, path .. ': Permission denied' end
            local f = {}
            function f.read() return w.cfg[name] end
            function f.write(_, s) w.cfg[name] = w.cfg[name] .. s return f end
            function f.close() end
            assert(mode == 'rb' or mode == 'ab')
            return f
        end,
    }
    env.ExecuteCommand = function(cmd) w.exec[#w.exec + 1] = cmd end
    local cv = opts.convars or { fh_dev = '1', fh_dev_autoadmin = '1' }
    env.GetConvar = function(k, d) return cv[k] or d end
    env.GetConvarInt = function(k, d) return tonumber(cv[k]) or d end
    w.exported = {}
    env.exports = function(name, fn) w.exported[name] = fn end
    env.GetResourceState = function() return 'missing' end -- rsg-core whitelist off: grant path only
    env.AddEventHandler = function(name, fn) w.handlers[name] = fn end
    env.lib = { addCommand = function(name, _, fn) w.cmds[name] = fn end }
    local ids = {}
    env.GetPlayerIdentifierByType = function(src, kind) return ids[src] and ids[src][kind] end
    local aces = opts.aces or {}
    env.IsPlayerAceAllowed = function(src, ace) return (aces[tonumber(src)] or {})[ace] == true end
    env.GetPlayers = function() return opts.players or {} end
    env.print = function(...) w.logs[#w.logs + 1] = table.concat({ ... }, ' ') end
    env.TriggerClientEvent = function(_, src, msg) w.chat[#w.chat + 1] = msg.args[2] end
    assert(loadfile(SERVER, 't', env))()
    function w.join(src, license, name)
        ids[src] = { license = license }
        env.source = src
        w.handlers.playerConnecting(name or 'p')
    end
    function w.allow(src, raw) w.cmds.fh_allow(src, {}, raw) end
    function w.store() return A.parseStore(w.files[A.STORE_FILE]) end
    function w.has(pat) for _, l in ipairs(w.logs) do if l:find(pat, 1, true) then return true end end return false end
    return w
end

local function strictExec(w)
    for _, c in ipairs(w.exec) do assert(c:match(STRICT), 'non-strict command reached ExecuteCommand: ' .. c) end
end

case('unreadable admins.cfg + empty store: io error logged, first joiner granted and claim persisted to access.txt', function()
    local w = boot() -- no store file, admins.cfg io.open fails
    assert(w.has('autoadmin: cannot read admins.cfg (path: ' .. SRV_DIR .. '/admins.cfg: Permission denied)'),
        'path + io error printed')
    assert(w.has('using fh_core/access.txt'))
    T.same({}, w.exec, 'nothing to re-apply')
    w.join(1, OWNER)
    T.same({ A.principalLine(OWNER, A.ADMIN_GROUP) }, w.exec)
    T.same({ OWNER }, w.store().admins, 'claim on disk in the resource file')
    assert(w.has('granted group.admin to ' .. OWNER))
    assert(w.has('could not read ' .. SRV_DIR .. '/admins.cfg: Permission denied'), 'best-effort cfg write logged')
    w.join(2, FRIEND)
    T.eq(1, #w.exec, 'second joiner never granted')
    strictExec(w)
end)

case('store with an owner: re-granted at boot (admins + allowlist) and locked', function()
    local w = boot({ store = 'admin ' .. OWNER .. '\nallow ' .. FRIEND .. '\n' })
    T.same({ A.principalLine(OWNER, A.ADMIN_GROUP), A.principalLine(FRIEND, A.ALLOW_GROUP) }, w.exec)
    assert(w.has('re-applied 1 admin and 1 allowlist entries'))
    w.join(1, FRIEND)
    w.join(2, 'license:' .. string.rep('c3', 20))
    T.eq(2, #w.exec, 'locked: no new grant')
    assert(not w.has('granted group.admin'))
end)

case('malformed store entries are logged and never reach ExecuteCommand; a bad admin line fails closed', function()
    local w = boot({ store = table.concat({
        'allow ' .. FRIEND .. ';quit',
        'allow ' .. FRIEND .. ' group.admin',
        'admin license:zz',
        'allow ' .. FRIEND,
    }, '\n') })
    T.same({ A.principalLine(FRIEND, A.ALLOW_GROUP) }, w.exec, 'only the valid line')
    assert(w.has('ignored malformed allow entry at fh_core/access.txt line 1'))
    assert(w.has('ignored malformed admin entry at fh_core/access.txt line 3'))
    assert(w.has('malformed admin entry; auto-admin is OFF'))
    w.join(1, OWNER)
    T.eq(1, #w.exec, 'bad admin line locks: nobody granted')
    -- fh_allow refuses an injection attempt before ExecuteCommand
    w.allow(0, 'fh_allow ' .. FRIEND .. ';quit')
    w.allow(0, 'fh_allow ' .. FRIEND .. ' group.admin')
    T.eq(1, #w.exec)
    strictExec(w)
end)

case('readable admins.cfg: grant goes to the store AND the cfg; an admin line in the cfg locks', function()
    local w = boot({ cfg = { ['admins.cfg'] = '# header\n' } })
    w.join(1, OWNER)
    T.same({ OWNER }, w.store().admins)
    assert(A.hasLine(w.cfg['admins.cfg'], A.principalLine(OWNER, A.ADMIN_GROUP)))
    local w2 = boot({ cfg = { ['admins.cfg'] = A.principalLine(OWNER, A.ADMIN_GROUP) .. '\n' } })
    w2.join(1, FRIEND)
    T.same({}, w2.exec)
end)

case('SaveResourceFile fails: live grant only, not locked, failure logged, nobody else granted', function()
    local w = boot({ saveFails = true })
    w.join(1, OWNER)
    T.eq(1, #w.exec)
    assert(w.has('SaveResourceFile failed') and w.has('could not save the admin claim'))
    assert(not w.has('granted group.admin'))
    w.join(2, FRIEND)
    T.eq(1, #w.exec, 'friend not granted while the owner grant is pending')
end)

case('evidence: an online player already holding group.admin locks a lost store', function()
    local w = boot({ aces = { [7] = { command = true } }, players = { '7' } })
    w.join(1, FRIEND)
    T.same({}, w.exec)
    assert(w.has('existing admin is connected'))
    local w2 = boot({ aces = { [1] = { command = true } } }) -- the joiner is an admin via exec'd admins.cfg
    w2.join(1, OWNER)
    T.same({}, w2.exec)
    T.same({}, w2.store().admins)
end)

case('fh_allow: persisted to access.txt even when allowlist.cfg io fails (error logged), re-applied next boot', function()
    local w = boot({ store = 'admin ' .. OWNER .. '\n' })
    w.allow(0, 'fh_allow ' .. FRIEND:sub(9))
    T.eq(A.principalLine(FRIEND, A.ALLOW_GROUP), w.exec[#w.exec])
    T.same({ FRIEND }, w.store().allow)
    assert(w.has('allowlist: added ' .. FRIEND) and not w.has('live only'))
    assert(w.has('could not read ' .. SRV_DIR .. '/allowlist.cfg: Permission denied'))
    local w2 = boot({ store = w.files[A.STORE_FILE] })
    T.same({ A.principalLine(OWNER, A.ADMIN_GROUP), A.principalLine(FRIEND, A.ALLOW_GROUP) }, w2.exec)
end)

case('world-04 M: canSeeIds is server-decided: admin ACE or fh_dev=1, never a bare player', function()
    local admin = boot({ convars = { fh_dev = '0' }, aces = { [5] = { command = true } } })
    local can = admin.exported.canSeeIds
    T.eq(true, can(5))   -- holds the admin ACE
    T.eq(false, can(6))  -- plain player, fh_dev off
    T.eq(false, can(nil))
    T.eq(false, can(0))  -- console has no client to show it to
    local dev = boot({ convars = { fh_dev = '1' } })
    T.eq(true, dev.exported.canSeeIds(6)) -- fh_dev=1 shows ids to everyone
end)

T.finish()
