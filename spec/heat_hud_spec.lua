-- Run from repo root: `lua spec/heat_hud_spec.lua` (or via tools/run-specs.py).
-- Pure spec for shared/heat_hud.lua: getAll(src) map -> fh_ui `heat` screen data. Read-only, no natives.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local case = T.it
local H = dofile(here .. '../server/resources/[fh]/fh_heat/shared/heat_hud.lua')
local regions = require('regions')

local factions = regions.factions

case('build maps heat>0 factions to {id,label,level,tier}, skips zero, sorted by id', function()
    local data = H.build({
        outlaws = { heat = 55, level = 'wanted' },
        lawmen  = { heat = 18, level = nil },
        raiders = { heat = 0,  level = nil },
        settlers = { heat = 0, level = 'watched' }, -- a stray level on zero heat is still dropped
    }, factions)
    T.eq(2, #data.factions)
    T.eq('lawmen', data.factions[1].id); T.eq('Lawmen', data.factions[1].label)
    T.eq(18, data.factions[1].level); T.eq(nil, data.factions[1].tier)
    T.eq('outlaws', data.factions[2].id); T.eq('Mountain Gang', data.factions[2].label)
    T.eq(55, data.factions[2].level); T.eq('wanted', data.factions[2].tier)
end)

case('build: empty, nil or junk getAll -> empty factions (widget hides)', function()
    T.eq(0, #H.build(nil, factions).factions)
    T.eq(0, #H.build({}, factions).factions)
    T.eq(0, #H.build('x', factions).factions)
    T.eq(0, #H.build({ outlaws = { heat = 0, level = nil } }, factions).factions)
    T.eq(0, #H.build({ outlaws = { heat = -5, level = nil } }, factions).factions)
end)

case('build: unknown faction keeps its id and falls back to the id as label', function()
    local d = H.build({ mystery = { heat = 3, level = nil } }, {})
    T.eq(1, #d.factions)
    T.eq('mystery', d.factions[1].id); T.eq('mystery', d.factions[1].label)
    T.eq(3, d.factions[1].level); T.eq(nil, d.factions[1].tier)
end)

case('build: every real faction is labelled; tier is the threshold name or nil', function()
    local all = {}
    for id in pairs(regions.factions) do all[id] = { heat = 0, level = nil } end
    all.outlaws = { heat = 100, level = 'hunted' }
    all.traders = { heat = 50,  level = 'wanted' }
    all.desert_gang = { heat = 25, level = 'watched' }
    local d = H.build(all, factions)
    T.eq(3, #d.factions)
    local by = {}
    for _, r in ipairs(d.factions) do by[r.id] = r end
    T.eq('Mountain Gang', by.outlaws.label); T.eq(100, by.outlaws.level); T.eq('hunted', by.outlaws.tier)
    T.eq('Traders Guild', by.traders.label); T.eq('wanted', by.traders.tier)
    T.eq('Desert Gang', by.desert_gang.label); T.eq('watched', by.desert_gang.tier)
end)

case('build: lay_low is always inactive (no player-level lay-low to report)', function()
    T.same({ active = false }, H.build({ outlaws = { heat = 10, level = nil } }, factions).lay_low)
    T.same({ active = false }, H.build(nil, factions).lay_low)
end)

case('build: read-only — the getAll map and faction registry are never mutated', function()
    local all = { outlaws = { heat = 55, level = 'wanted' }, raiders = { heat = 0, level = nil } }
    local snapshot = { outlaws = { heat = 55, level = 'wanted' }, raiders = { heat = 0, level = nil } }
    H.build(all, factions)
    T.same(snapshot, all)
end)

T.finish()
