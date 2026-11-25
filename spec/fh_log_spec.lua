-- Run from repo root: `lua spec/fh_log_spec.lua` (or via busted / tools/run-specs.py).
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
package.path = here .. '../server/resources/[fh]/fh_log/server/?.lua;' .. package.path
local case = T.it
local F = require('format')

case('formatLine: standard rsg-log entry', function()
    local line = F.formatLine('2026-11-25T00:00:00Z', 'admin', 'Admin command', 'orange', '/tp 1 2 3', false)
    T.eq('2026-11-25T00:00:00Z [admin] (orange) Admin command: /tp 1 2 3', line)
end)

case('formatLine: appends [tagEveryone] only when true', function()
    local tagged = F.formatLine('2026-11-25T00:00:00Z', 'anticheat', 'Anti-Cheat', 'red', 'banned', true)
    T.eq('2026-11-25T00:00:00Z [anticheat] (red) Anti-Cheat: banned [tagEveryone]', tagged)
    local strTrue = F.formatLine('2026-11-25T00:00:00Z', 'anticheat', 'Anti-Cheat', 'red', 'banned', 'yes')
    T.eq('2026-11-25T00:00:00Z [anticheat] (red) Anti-Cheat: banned', strTrue)
end)

case('formatLine: strips CR/LF and control chars to keep one line', function()
    local line = F.formatLine('2026-11-25T00:00:00Z', 'join\nleave', 'Drop\r\nped', 'red\t', 'Alice left..\n **Reason:** timeout\r\nbye\0x')
    assert(not line:find('[\r\n\t%z]'), 'control char remained: ' .. line)
    T.eq('2026-11-25T00:00:00Z [join leave] (red) Drop ped: Alice left.. **Reason:** timeout bye x', line)
end)

case('formatLine: never errors on nil, empty, or odd argument types', function()
    T.eq('- [default] (-) -', F.formatLine())
    T.eq('2026-11-25T00:00:00Z [default] (-) -', F.formatLine('2026-11-25T00:00:00Z', '', '   ', nil, nil, nil))
    local weird = setmetatable({}, { __tostring = function() error('boom') end })
    local line = F.formatLine('2026-11-25T00:00:00Z', 42, true, {}, weird, 1)
    assert(type(line) == 'string' and not line:find('[\r\n]'))
    assert(line:find('%[42%]') and line:find('<unprintable>'), line)
end)

-- core-09 N1: server/main.lua buffering + rotation, with a temp server dir and stubbed Cfx infra.
local MAIN = here .. '../server/resources/[fh]/fh_log/server/main.lua'

local function readAll(path)
    local f = io.open(path, 'rb')
    if not f then return nil end
    local s = f:read('a') f:close()
    return s
end

local function bootLog(capKb)
    local root = os.tmpname()
    os.remove(root)
    assert(os.execute("mkdir -p '" .. root .. "/logs'"))
    local w = { handlers = {}, timers = {}, prints = {}, root = root, path = root .. '/logs/audit.log' }
    local env = setmetatable({}, { __index = _G })
    env.FhLogFormat = F
    env.GetCurrentResourceName = function() return 'fh_log' end
    env.GetResourcePath = function() return root .. '/resources/[fh]/fh_log' end
    env.GetConvarInt = function(name, def) if name == 'fh_log_max_kb' then return capKb or def end return def end
    env.SetTimeout = function(ms, fn) w.timers[#w.timers + 1] = { ms = ms, fn = fn } end
    env.AddEventHandler = function(n, fn) w.handlers[n] = fn end
    env.print = function(...) w.prints[#w.prints + 1] = table.concat({ ... }, ' ') end
    assert(loadfile(MAIN, 't', env))()
    function w.log(msg) w.handlers['rsg-log:server:CreateLog']('admin', 'T', 'red', msg, false) end
    function w.tick() local t = w.timers w.timers = {} for _, x in ipairs(t) do x.fn() end end
    function w.cleanup() os.execute("rm -rf '" .. root .. "'") end
    return w
end

case('fh_log: events are buffered, written on the ~2 s timer in one flush (one timer per burst)', function()
    local w = bootLog()
    w.log('one') w.log('two\nline')
    T.eq(nil, readAll(w.path), 'nothing written before the flush')
    T.eq(1, #w.timers) T.eq(2000, w.timers[1].ms)
    T.eq(2, #w.prints, 'console lines are still immediate')
    w.tick()
    local s = readAll(w.path)
    assert(s and s:find('one\n') and s:find('two line\n'), tostring(s))
    local _, n = s:gsub('\n', '') T.eq(2, n)
    w.log('three') T.eq(1, #w.timers, 'next event schedules a new flush')
    w.tick()
    assert(readAll(w.path):find('three\n'))
    w.cleanup()
end)

case('fh_log: onResourceStop for fh_log flushes the buffer; another resource stopping does not', function()
    local w = bootLog()
    w.log('pending')
    w.handlers.onResourceStop('rsg-core')
    T.eq(nil, readAll(w.path))
    w.handlers.onResourceStop('fh_log')
    assert(readAll(w.path):find('pending\n'))
    w.tick() -- the leftover timer is a no-op
    local _, n = readAll(w.path):gsub('\n', '') T.eq(1, n)
    w.cleanup()
end)

case('fh_log: audit.log rotates to audit.log.1 at the cap; a second rotation overwrites the old .1', function()
    local w = bootLog(1) -- 1 KB
    local big = string.rep('a', 600)
    w.log('A' .. big) w.tick()
    T.eq(nil, readAll(w.path .. '.1'), 'under the cap: no rotation')
    w.log('B' .. big) w.tick() -- would pass 1024 bytes: rotate first
    local one, cur = readAll(w.path .. '.1'), readAll(w.path)
    assert(one and one:find('A' .. big, 1, true) and not one:find('B', 1, true), 'old lines in .1')
    assert(cur and cur:find('B' .. big, 1, true) and not cur:find('A' .. big, 1, true), 'new lines in audit.log')
    w.log('C' .. big) w.tick()
    one, cur = readAll(w.path .. '.1'), readAll(w.path)
    assert(one:find('B' .. big, 1, true) and not one:find('A' .. big, 1, true), '.1 overwritten, A gone')
    assert(cur:find('C' .. big, 1, true) and #cur <= 1024)
    w.cleanup()
end)

case('fh_log: a 500-line burst flushes without waiting for the timer', function()
    local w = bootLog()
    for i = 1, 500 do w.log('x' .. i) end
    local s = readAll(w.path)
    local _, n = (s or ''):gsub('\n', '') T.eq(500, n)
    w.cleanup()
end)

T.finish()
