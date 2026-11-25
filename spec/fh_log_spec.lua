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

T.finish()
