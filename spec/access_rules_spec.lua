-- Run from repo root: `python tools/run-specs.py spec/access_rules_spec.lua`.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local case = T.it
local A = require('access_rules')

local OWNER = 'license:' .. string.rep('a1', 20)
local FRIEND = 'license:' .. string.rep('b2', 20)
local ON = { fh_dev = '1', fh_dev_autoadmin = '1' }

-- Fake server: executed principal lines are the live ACL; allowed() mirrors IsPlayerAceAllowed(src, 'fh.allowlist')
-- given the server.cfg wiring (group.admin -> group.fh_allowlist -> ace fh.allowlist).
local function fakeServer(opts)
    opts = opts or {}
    local s = { calls = {}, logs = {}, acl = {}, file = opts.file or '', allowFile = opts.allow or {} }
    function s.io(license)
        return {
            execute = function(cmd)
                s.calls[#s.calls + 1] = 'execute'
                local id, grp = cmd:match('^add_principal identifier%.(%S+) (%S+)$')
                s.acl[id] = grp
            end,
            persist = function(line)
                s.calls[#s.calls + 1] = 'persist'
                if opts.failPersist and opts.failPersist() then return false end
                local add = A.appendText(s.file, line)
                if add then s.file = s.file .. add end
                return A.hasLine(s.file, line)
            end,
            isAllowed = function()
                s.calls[#s.calls + 1] = 'check'
                return s.acl[license] == A.ADMIN_GROUP or s.acl[license] == A.ALLOW_GROUP or s.allowFile[license] == true
            end,
            log = function(m) s.logs[#s.logs + 1] = m end,
        }
    end
    function s.join(state, convars, license, name, discord)
        s.calls = {}
        return A.onConnect(state, convars, { license = license, discord = discord, name = name or 'p', whitelistOn = true },
            s.io(license))
    end
    return s
end

local function count(list, pat)
    local n = 0
    for _, l in ipairs(list) do if l:find(pat, 1, true) then n = n + 1 end end
    return n
end

case('parseIdentifier: license with/without prefix, discord, rejects junk', function()
    T.eq(OWNER, A.parseIdentifier(OWNER))
    T.eq(OWNER, A.parseIdentifier(OWNER:sub(9)), 'bare hash is a license')
    T.eq(OWNER, A.parseIdentifier('  LICENSE:' .. OWNER:sub(9):upper() .. ' '), 'case/space normalised')
    T.eq('discord:123456789012345678', A.parseIdentifier('discord:123456789012345678'))
    local function bad(s) local v, e = A.parseIdentifier(s) return v == nil and e == 'fh_bad_identifier' end
    assert(bad(nil) and bad('') and bad('license:') and bad('license:xyz'))
    assert(bad(OWNER .. ' group.admin'), 'no command injection through a space')
    assert(bad(OWNER .. ';quit'), 'no ; injection')
    assert(bad('license:' .. string.rep('a', 31)) and bad('license:' .. string.rep('a', 65)))
    assert(bad('steam:110000112345678') and bad('discord:12ab') and bad('discord:123'))
end)

case('hasAdminLine / hasLine / appendText', function()
    assert(not A.hasAdminLine(''))
    assert(not A.hasAdminLine('# add_principal identifier.' .. OWNER .. ' group.admin\n'), 'comment ignored')
    assert(A.hasAdminLine('# header\r\nadd_principal identifier.' .. OWNER .. ' group.admin\r\n'))
    assert(not A.hasAdminLine('add_principal identifier.' .. OWNER .. ' group.fh_allowlist\n'))
    local line = A.principalLine(OWNER, A.ADMIN_GROUP)
    T.eq(line .. '\n', A.appendText('', line))
    T.eq('\n' .. line .. '\n', A.appendText('# h', line), 'newline added when file lacks one')
    T.eq(nil, A.appendText('# h\n  ' .. line .. '  \r\n', line), 'idempotent')
end)

case('rejectLine: one line, sanitised name, license and discord', function()
    T.eq('allowlist: rejected Bob ' .. FRIEND, A.rejectLine('Bob', { license = FRIEND }))
    T.eq('allowlist: rejected Bob ' .. FRIEND .. ' discord:123456789012345678',
        A.rejectLine('Bob', { license = FRIEND, discord = 'discord:123456789012345678' }))
    local l = A.rejectLine('Evil\ngranted group.admin to x', { license = FRIEND })
    assert(not l:find('\n'), 'no newline forging')
    T.eq(32 + #'allowlist: rejected  ' + #FRIEND, #A.rejectLine(string.rep('n', 50), { license = FRIEND }))
end)

case('first joiner: grant BEFORE the allowlist check, so an empty allowlist still admits the owner', function()
    local srv, st = fakeServer(), { locked = false }
    local r = srv.join(st, ON, OWNER)
    T.same({ 'execute', 'persist', 'check' }, srv.calls, 'order')
    assert(r.allowed and r.granted == OWNER and st.locked and st.pending == nil)
    assert(A.hasLine(srv.file, 'add_principal identifier.' .. OWNER .. ' group.admin'))
    T.eq(1, count(srv.logs, 'granted group.admin to ' .. OWNER))
    T.eq(0, count(srv.logs, 'allowlist: rejected'))
end)

case('later joiners are never auto-granted; non-allowlisted friend is rejected with one copyable line', function()
    local srv, st = fakeServer(), { locked = false }
    srv.join(st, ON, OWNER)
    local r = srv.join(st, ON, FRIEND, 'Friend')
    T.same({ 'check' }, srv.calls)
    assert(not r.allowed and r.granted == nil and srv.acl[FRIEND] == nil)
    T.eq(1, count(srv.logs, 'allowlist: rejected Friend ' .. FRIEND))
    T.eq(1, count(srv.logs, 'granted group.admin'), 'still only the owner grant')
end)

case('allowlisted friend gets in and is NOT admin', function()
    local srv, st = fakeServer(), { locked = false }
    srv.join(st, ON, OWNER)
    srv.acl[FRIEND] = A.ALLOW_GROUP -- what fh_allow executes
    local r = srv.join(st, ON, FRIEND)
    assert(r.allowed and r.granted == nil and srv.acl[FRIEND] == A.ALLOW_GROUP)
end)

case('restart: admins.cfg already has an admin line -> locked, no grant', function()
    local file = 'add_principal identifier.' .. OWNER .. ' group.admin\n'
    local srv = fakeServer({ file = file })
    local st = { locked = A.hasAdminLine(file) }
    srv.acl[OWNER] = A.ADMIN_GROUP -- exec admins.cfg
    local r = srv.join(st, ON, FRIEND)
    assert(not r.allowed and r.granted == nil)
    assert(srv.join(st, ON, OWNER).allowed)
end)

case('either convar off: no grant (whitelist then rejects the first joiner)', function()
    for _, cv in ipairs({ { fh_dev = '0', fh_dev_autoadmin = '1' }, { fh_dev = '1', fh_dev_autoadmin = '0' }, {} }) do
        local srv, st = fakeServer(), { locked = false }
        local r = srv.join(st, cv, OWNER)
        assert(r.granted == nil and not st.locked and srv.acl[OWNER] == nil)
        T.same({ 'check' }, srv.calls)
        assert(not r.allowed)
    end
    assert(A.flag('true') and A.flag('1') and not A.flag('yes') and not A.flag(nil))
end)

case('persist fails: no lock; next join retries the SAME license and grants nobody else', function()
    local fail = true
    local srv, st = fakeServer({ failPersist = function() return fail end }), { locked = false }
    local r = srv.join(st, ON, OWNER)
    assert(r.allowed, 'live grant still admits the owner this session')
    assert(not st.locked and st.pending == OWNER, 'no lock when persist fails')
    T.eq(0, count(srv.logs, 'granted group.admin'))
    T.eq(1, count(srv.logs, 'could not write admins.cfg'))
    -- a friend joins while the write is still failing: not granted, pending kept, rejected
    local r2 = srv.join(st, ON, FRIEND)
    T.same({ 'persist', 'check' }, srv.calls, 'retry persists the pending owner line, no execute for the friend')
    assert(not r2.allowed and r2.granted == nil and srv.acl[FRIEND] == nil and st.pending == OWNER)
    -- disk is back: the next join (anyone) persists the owner's line and locks
    fail = false
    local r3 = srv.join(st, ON, FRIEND)
    assert(st.locked and st.pending == nil and r3.granted == nil and srv.acl[FRIEND] == nil)
    assert(A.hasLine(srv.file, A.principalLine(OWNER, A.ADMIN_GROUP)))
    assert(not A.hasLine(srv.file, A.principalLine(FRIEND, A.ADMIN_GROUP)))
    T.eq(1, count(srv.logs, 'granted group.admin to ' .. OWNER))
end)

case('no or malformed license: no grant, rejected line still printed', function()
    local srv, st = fakeServer(), { locked = false }
    local r = srv.join(st, ON, nil, 'NoLic')
    assert(not r.allowed and not st.locked and r.line == 'allowlist: rejected NoLic license:none')
    local r2 = srv.join(st, ON, 'license:zz;quit', 'Bad')
    assert(r2.granted == nil and not st.locked)
    T.same({ 'check' }, srv.calls)
end)

case('whitelist off: nothing rejected, grant still happens', function()
    local st = { locked = false }
    local calls = {}
    local r = A.onConnect(st, ON, { license = OWNER, name = 'x', whitelistOn = false }, {
        execute = function() calls[#calls + 1] = 'execute' end,
        persist = function() calls[#calls + 1] = 'persist' return true end,
        isAllowed = function() error('must not check when whitelist is off') end,
        log = function() end,
    })
    assert(r.allowed and r.granted == OWNER and st.locked)
end)

T.finish()
