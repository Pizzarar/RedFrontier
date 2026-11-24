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
    T.eq(1, count(srv.logs, 'could not save the admin claim'))
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

case('hasAdminLine: trailing comments still count, commented-out lines never do', function()
    local adm = 'add_principal identifier.' .. OWNER .. ' group.admin'
    assert(A.hasAdminLine(adm .. ' # owner, added by first-run\n'), 'trailing # comment')
    assert(A.hasAdminLine(adm .. '# no space\n'), 'trailing # without a space')
    assert(A.hasAdminLine('  ' .. adm .. '\t// note\r\n'), 'trailing // comment')
    assert(not A.hasAdminLine('# ' .. adm .. '\n'), '# commented out')
    assert(not A.hasAdminLine('  #' .. adm .. ' # x\n'), 'indented # commented out')
    assert(not A.hasAdminLine('// ' .. adm .. '\n'), '// commented out')
    assert(not A.hasAdminLine('add_principal identifier.' .. OWNER .. ' group.fh_allowlist # group.admin\n'),
        'group.admin only inside the comment')
    assert(A.hasLine(adm .. ' # note\n', A.principalLine(OWNER, A.ADMIN_GROUP)), 'hasLine agrees')
    assert(not A.hasLine('# ' .. adm .. '\n', A.principalLine(OWNER, A.ADMIN_GROUP)))
end)

case('initialState: unreadable admins.cfg FAILS CLOSED (locked, no grant, one error); empty -> unlocked', function()
    local st, err = A.initialState(nil)
    assert(st.locked and st.unreadable and st.pending == nil, 'nil content -> locked')
    assert(err and err:find('admins.cfg', 1, true) and err:find('start-server.ps1', 1, true)
        and err:find('permissions', 1, true) and not err:find('\n'), 'one clear console line naming the fix')
    local srv = fakeServer()
    local r = srv.join(st, ON, FRIEND)
    T.same({ 'check' }, srv.calls, 'no execute, no persist')
    assert(not r.allowed and r.granted == nil and srv.acl[FRIEND] == nil and st.pending == nil)
    local r2 = srv.join(st, ON, OWNER)
    assert(r2.granted == nil and srv.acl[OWNER] == nil, 'not even the owner is auto-granted')

    local st2, err2 = A.initialState('')
    assert(not st2.locked and err2 == nil, "'' -> unlocked")
    local st3 = A.initialState('# Admins (first joiner is added here)\n')
    assert(not st3.locked, 'comments only -> unlocked')
    local st4, err4 = A.initialState('add_principal identifier.' .. OWNER .. ' group.admin # owner\n')
    assert(st4.locked and not st4.unreadable and err4 == nil, 'admin line -> locked')
    local srv2 = fakeServer()
    assert(srv2.join(st2, ON, OWNER).granted == OWNER and st2.locked, 'empty file: first joiner granted')
end)

case('persistVerified: a nil re-read is a failed persist (no lock, nobody else granted)', function()
    local line = A.principalLine(OWNER, A.ADMIN_GROUP)
    assert(not A.persistVerified(nil, line), 'nil re-read')
    assert(not A.persistVerified('', line), 'line missing')
    assert(A.persistVerified('# h\n' .. line .. '\n', line))
    local st, acl, logs = { locked = false }, {}, {}
    local function join(license)
        return A.onConnect(st, ON, { license = license, name = 'p', whitelistOn = true }, {
            execute = function(cmd) acl[cmd:match('identifier%.(%S+)')] = true end,
            persist = function(l) return A.persistVerified(nil, l) end, -- write ok, read-back fails
            isAllowed = function() return acl[license] == true end,
            log = function(m) logs[#logs + 1] = m end,
        })
    end
    local r = join(OWNER)
    assert(r.allowed and not st.locked and st.pending == OWNER)
    local r2 = join(FRIEND)
    assert(not r2.allowed and r2.granted == nil and acl[FRIEND] == nil and not st.locked and st.pending == OWNER)
    T.eq(0, count(logs, 'granted group.admin'))
end)

case('parseStore: valid admin/allow entries, comments, dedupe; malformed entries never reach the lists', function()
    local st = A.parseStore(table.concat({
        '# header',
        'admin ' .. OWNER .. ' # owner',
        'admin ' .. OWNER,
        'allow ' .. FRIEND:upper():gsub('^LICENSE', 'license'),
        'allow discord:123456789012345678',
        'admin discord:123456789012345678', -- admin must be a license
        'allow ' .. FRIEND .. ';quit',
        'admin ' .. OWNER .. ' group.admin', -- extra token: injection attempt
        'grant ' .. OWNER,
        '',
    }, '\r\n'))
    T.same({ OWNER }, st.admins)
    T.same({ FRIEND, 'discord:123456789012345678' }, st.allow)
    T.same({ { line = 6, kind = 'admin' }, { line = 7, kind = 'allow' }, { line = 8, kind = 'admin' }, { line = 9, kind = '?' } },
        st.bad)
    T.same({ admins = {}, allow = {}, bad = {} }, A.parseStore(nil), 'missing file -> empty store')
end)

case('storeAdd / storeText / bootLines round-trip; invalid ids refused', function()
    local st = A.parseStore(nil)
    T.eq(true, A.storeAdd(st, 'admin', OWNER))
    T.eq(false, A.storeAdd(st, 'admin', OWNER:sub(9)), 'idempotent (bare hash normalised)')
    T.eq(true, A.storeAdd(st, 'allow', FRIEND))
    T.eq(nil, A.storeAdd(st, 'admin', 'discord:123456789012345678'))
    T.eq(nil, A.storeAdd(st, 'allow', FRIEND .. ' group.admin'))
    T.eq(nil, A.storeAdd(st, 'owner', OWNER))
    local back = A.parseStore(A.storeText(st))
    T.same({ OWNER }, back.admins)
    T.same({ FRIEND }, back.allow)
    T.same({}, back.bad, 'header lines are comments')
    assert(A.storeHas(back, 'admin', OWNER) and not A.storeHas(back, 'admin', FRIEND) and A.storeHas(back, 'allow', FRIEND))
    T.same({ A.principalLine(OWNER, A.ADMIN_GROUP), A.principalLine(FRIEND, A.ALLOW_GROUP) }, A.bootLines(back))
    T.same({}, A.bootLines({ admins = { 'license:zz' }, allow = { FRIEND .. ' x' } }), 'bootLines re-validates')
end)

case('initialState with store: store owner locks; empty store decides unreadable cfg; bad admin line fails closed', function()
    local empty = A.parseStore('')
    local st, msg = A.initialState(nil, empty)
    assert(not st.locked and st.unreadable and msg and msg:find('access.txt', 1, true) and not msg:find('\n'))
    local owned = A.parseStore('admin ' .. OWNER .. '\n')
    local st2, msg2 = A.initialState(nil, owned)
    assert(st2.locked and msg2 == nil, 'store owner locks even with admins.cfg unreadable')
    assert(A.initialState('', owned).locked)
    assert(A.initialState('add_principal identifier.' .. OWNER .. ' group.admin\n', empty).locked, 'cfg admin locks')
    assert(not A.initialState('# comments\n', empty).locked)
    local st3, msg3 = A.initialState('', A.parseStore('admin license:nothex\n'))
    assert(st3.locked and st3.badStore and msg3:find('malformed admin', 1, true), 'malformed admin line -> locked')
    assert(not A.initialState('', A.parseStore('allow junk\n')).locked, 'a bad allow line does not lock')
    assert(A.initialState(nil).locked, 'no store passed: unreadable cfg alone still fails closed')
end)

case('adminExists evidence: locks instead of granting a new first joiner; skipped while a grant is pending', function()
    local st, calls, logs = { locked = false }, {}, {}
    local function io(exists)
        return {
            execute = function() calls[#calls + 1] = 'execute' end,
            persist = function() calls[#calls + 1] = 'persist' return false end,
            isAllowed = function() return true end,
            adminExists = function() calls[#calls + 1] = 'evidence' return exists end,
            log = function(m) logs[#logs + 1] = m end,
        }
    end
    local r = A.onConnect(st, ON, { license = FRIEND, name = 'f', whitelistOn = false }, io(true))
    assert(r.granted == nil and st.locked)
    T.same({ 'evidence' }, calls)
    T.eq(1, count(logs, 'existing admin is connected'))
    -- pending: our own live grant must not count as evidence
    calls = {}
    local st2 = { locked = false, pending = OWNER }
    A.onConnect(st2, ON, { license = FRIEND, name = 'f', whitelistOn = false }, io(true))
    T.same({ 'persist' }, calls, 'retry persist, no evidence check')
    assert(not st2.locked and st2.pending == OWNER)
end)

T.finish()
