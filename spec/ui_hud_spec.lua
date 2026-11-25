-- Run from repo root: `lua spec/ui_hud_spec.lua` (or via tools/run-specs.py).
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local case = T.it
local H = dofile(here .. '../server/resources/[fh]/fh_ui/shared/hud.lua')
local R = dofile(here .. '../server/resources/[fh]/fh_ui/shared/relay.lua')

local clock = 100 -- fake clock, seconds

case('label prettifies buff ids', function()
    T.eq('Well Fed', H.label('well_fed'))
    T.eq('Rested', H.label('rested'))
    T.eq('?', H.label(nil))
end)

case('buffRows: sorted by soonest deadline, expired dropped, unknown remaining kept last', function()
    local rows = H.buffRows({
        rested = { magnitude = 1.2, remaining = 90 },
        well_fed = { magnitude = 1.1, remaining = 30 },
        warm = { magnitude = 1, remaining = 0 },
        trophy_luck = { magnitude = 1.1 },
    }, clock)
    T.eq(3, #rows)
    T.eq('well_fed', rows[1].id); T.eq(130, rows[1].deadline)
    T.eq('rested', rows[2].id)
    T.eq('trophy_luck', rows[3].id); T.eq(nil, rows[3].deadline)
end)

case('buffRows: garbage input is harmless', function()
    T.eq(0, #H.buffRows(nil, clock))
    T.eq(0, #H.buffRows('x', clock))
    T.eq(0, #H.buffRows({ [1] = {}, a = 5 }, clock))
end)

case('view: remaining counts down with the fake clock and expired rows vanish', function()
    local rows = H.buffRows({ well_fed = { remaining = 30 }, rested = { remaining = 5 } }, clock)
    local v = H.view(rows, clock)
    T.eq(2, #v); T.eq(5, v[1].remaining); T.eq(30, v[2].remaining)
    v = H.view(rows, clock + 2.2)
    T.eq(3, v[1].remaining) -- ceil(2.8)
    v = H.view(rows, clock + 5)
    T.eq(1, #v); T.eq('well_fed', v[1].id); T.eq(25, v[1].remaining)
    T.eq(0, #H.view(rows, clock + 31))
end)

case('view: unknown remaining stays listed with nil', function()
    local v = H.view(H.buffRows({ warm = {} }, clock), clock + 999)
    T.eq(1, #v); T.eq(nil, v[1].remaining)
end)

case('buffRows caps the list', function()
    local snap = {}
    for i = 1, 20 do snap['b' .. i] = { remaining = i } end
    T.eq(H.maxBuffs, #H.buffRows(snap, clock))
end)

case('bagRows: only own bags (mine == true); no ownership guessing', function()
    local list = {
        { id = 'a', x = 0, y = 100, remaining = 600, mine = true },
        { id = 'b', x = 5, y = 5, remaining = 100 },               -- no mine field (current fh_death shape)
        { id = 'c', x = 5, y = 5, remaining = 100, mine = false },
        { id = 'd', x = -100, y = 0, remaining = 300, mine = true },
    }
    local rows = H.bagRows(list, clock, { x = 0, y = 0 })
    T.eq(2, #rows)
    T.eq('d', rows[1].id); T.eq('W', rows[1].dir); T.eq(100, rows[1].dist)
    T.eq('a', rows[2].id); T.eq('N', rows[2].dir)
    T.eq(0, #H.bagRows({ { id = 'x', x = 1, y = 1, z = 1 } }, clock, { x = 0, y = 0 }))
end)

case('bagRows: countdown, expiry and missing player/remaining', function()
    local rows = H.bagRows({ { id = 'a', x = 1, y = 1, remaining = 60, mine = true } }, clock)
    T.eq(nil, rows[1].dir)
    T.eq(59, H.view(rows, clock + 1)[1].remaining)
    T.eq(0, #H.view(rows, clock + 60))
    T.eq(0, #H.bagRows({ { id = 'a', remaining = 0, mine = true } }, clock))
    rows = H.bagRows({ { id = 'a', mine = true } }, clock)
    T.eq(1, #rows); T.eq(nil, H.view(rows, clock)[1].remaining)
end)

case('retarget: ticks refresh direction/distance but never the deadline', function()
    local rows = H.bagRows({ { id = 'a', x = 0, y = 100, remaining = 60, mine = true } }, clock, { x = 0, y = 0 })
    T.eq(clock + 60, rows[1].deadline)
    for t = 1, 5 do
        H.retarget(rows, { x = 100, y = 100 }) -- 5 s ticks; clock advances but deadline must stay put
        T.eq(clock + 60, rows[1].deadline)
        T.eq(60 - t * 5, H.view(rows, clock + t * 5)[1].remaining)
    end
    T.eq('W', rows[1].dir); T.eq(100, rows[1].dist)
    H.retarget(rows, nil)
    T.eq(nil, rows[1].dir)
end)

case('compass: 8 directions, same spot', function()
    T.eq('N', H.compass(0, 0, 0, 5)); T.eq('NE', H.compass(0, 0, 5, 5)); T.eq('E', H.compass(0, 0, 5, 0))
    T.eq('SE', H.compass(0, 0, 5, -5)); T.eq('S', H.compass(0, 0, 0, -5)); T.eq('SW', H.compass(0, 0, -5, -5))
    T.eq('W', H.compass(0, 0, -5, 0)); T.eq('NW', H.compass(0, 0, -5, 5))
    T.eq('here', H.compass(1, 1, 1, 1)); T.eq(nil, H.compass(nil, 0, 1, 1))
end)

case('view output is relay-safe plain data', function()
    local rows = H.bagRows({ { id = 'a', x = 3, y = 4, remaining = 10, mine = true } }, clock, { x = 0, y = 0 })
    assert(R.measure(H.view(rows, clock)))
end)

case('relay: bags is a passive screen owned by death', function()
    T.eq('death', R.screens.bags)
    assert(R.passive.bags and R.passive.buffs)
end)

case('survivalRows: level clamped 0..3, missing needs mapped to short labels', function()
    local v = H.survivalRows({ level = 3, missing = { 'food', 'water', 'rest', 'clean', 'warmth' } })
    T.eq(3, v.level)
    T.eq(5, #v.rows)
    T.eq('food', v.rows[1].id); T.eq('Hungry', v.rows[1].label)
    T.eq('water', v.rows[2].id); T.eq('Thirsty', v.rows[2].label)
    T.eq('warmth', v.rows[5].id); T.eq('Cold', v.rows[5].label)
end)

case('survivalRows: level clamped to 0..3 and unknown keys/needs ignored', function()
    local v = H.survivalRows({ level = 9, missing = { 'food', 'mana', 'water' }, junk = true })
    T.eq(3, v.level)
    T.eq(2, #v.rows)
    T.eq('Hungry', v.rows[1].label); T.eq('Thirsty', v.rows[2].label)
    T.eq(1, H.survivalRows({ level = 1.9, missing = {} }).level) -- floored
    T.eq(0, H.survivalRows({ level = -2, missing = {} }).level)
end)

case('survivalRows: garbage input is harmless', function()
    local v = H.survivalRows(nil)
    T.eq(0, v.level); T.eq(0, #v.rows)
    v = H.survivalRows('x')
    T.eq(0, v.level); T.eq(0, #v.rows)
    v = H.survivalRows({ level = 'high', missing = { 'food', 42, {} } })
    T.eq(0, v.level); T.eq(1, #v.rows)
end)

case('survivalRows: output is relay-safe plain data', function()
    local v = H.survivalRows({ level = 2, missing = { 'rest', 'clean' } })
    assert(R.measure(v))
    T.eq('Tired', v.rows[1].label); T.eq('Dirty', v.rows[2].label)
end)

case('relay: survival is a passive screen owned by survival', function()
    T.eq('survival', R.screens.survival)
    assert(R.passive.survival)
end)

T.finish()
