-- Run from repo root: `lua spec/admin_args_spec.lua` (or via busted).
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local case = T.it
local A = require('admin_args')
local containers = require('containers')
local known = function(n) return n == 'bread' end

case('parseGive: defaults count to 1 and checks the registry', function()
    local p = A.parseGive({ '3', 'bread' }, known)
    assert(p.target == 3 and p.item == 'bread' and p.count == 1)
    assert(A.parseGive({ '3', 'bread', '5' }, known).count == 5)
end)
case('parseGive: error codes', function()
    local function code(args) local _, e = A.parseGive(args, known) return e end
    assert(code({ 'x', 'bread' }) == 'fh_bad_target')
    assert(code({ '0', 'bread' }) == 'fh_bad_target')
    assert(code({ '3' }) == 'fh_bad_item')
    assert(code({ '3', 'bread', '0' }) == 'fh_bad_count')
    assert(code({ '3', 'bread', '1.5' }) == 'fh_bad_count')
    assert(code({ '3', 'bread', tostring(A.MAX_GIVE + 1) }) == 'fh_bad_count')
    assert(code({ '3', 'nothing' }) == 'fh_unknown_item')
end)
case('parseHeat: validates range', function()
    assert(A.parseHeat({ '2', '50' }).value == 50)
    local function code(args) local _, e = A.parseHeat(args) return e end
    assert(code({ '2', '101' }) == 'fh_bad_value')
    assert(code({ '2', '-1' }) == 'fh_bad_value')
    assert(code({ '2', 'nan' }) == 'fh_bad_value')
    assert(code({ '2' }) == 'fh_bad_value')
    assert(code({ 'q', '5' }) == 'fh_bad_target')
end)
case('parseTp: coords or player id', function()
    local c = A.parseTp({ '1.5', '-2', '30' }).coords
    assert(c.x == 1.5 and c.y == -2 and c.z == 30)
    assert(A.parseTp({ '7' }).target == 7)
    local function code(args) local _, e = A.parseTp(args) return e end
    assert(code({ '1', '2' }) == 'fh_bad_coords')
    assert(code({ '1', 'b', '3' }) == 'fh_bad_coords')
    assert(code({ 'inf', '1', '1' }) == 'fh_bad_coords')
    assert(code({}) == 'fh_bad_target')
end)
case('parseDump: carried types need a numeric id, others a string id', function()
    local p = A.parseDump({ 'backpack', '4' }, containers)
    assert(p.ref.type == 'backpack' and p.ref.id == 4)
    p = A.parseDump({ 'chest', 'fh:chest:h1:1' }, containers)
    assert(p.ref.id == 'fh:chest:h1:1')
    local function code(args) local _, e = A.parseDump(args, containers) return e end
    assert(code({ 'bogus', '1' }) == 'fh_unknown_container')
    assert(code({ 'backpack', 'abc' }) == 'fh_bad_ref')
    assert(code({ 'chest' }) == 'fh_bad_ref')
    assert(code({}) == 'fh_unknown_container')
end)
T.finish()
