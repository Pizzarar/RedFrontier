-- Run from repo root: `lua spec/ui_fixtures_spec.lua` (or via tools/run-specs.py).
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local case = T.it
local R = dofile(here .. '../server/resources/[fh]/fh_ui/shared/relay.lua')
local F = dofile(here .. '../server/resources/[fh]/fh_ui/shared/fixtures.lua')

local expectLane = { heat = 'heat', insurance = 'death', jobs = 'quests', journal = 'quests', station = 'homestead', fence = 'fence' }
local passive = { heat = true }

case('every fixture validates against its schema', function()
    local n = 0
    for screen, data in pairs(F.fixtures) do
        n = n + 1
        local ok, errs = F.validate(screen, data)
        assert(ok, screen .. ': ' .. table.concat(errs or {}, '; '))
    end
    T.eq(6, n)
end)
case('schema checker rejects bad data', function()
    local bad = { title = 'x', fee = 'free', delay_minutes = 1 }
    local ok, errs = F.validate('insurance', bad)
    assert(not ok and #errs == 2) -- fee wrong type, target_chest missing
    assert(not F.validate('heat', { factions = { { id = 'a' } } }))
    assert(not F.validate('nope', {}))
end)
case('every fixture screen is whitelisted with the right lane and focus', function()
    for screen in pairs(F.fixtures) do
        T.eq(expectLane[screen], R.screens[screen], screen)
        T.eq(passive[screen] or nil, R.passive[screen], screen .. ' passive')
    end
end)
case('fixture actions relay (confirm/cancel/accept/craft/buy/sell/close)', function()
    for screen, act in pairs({ insurance = 'confirm', jobs = 'accept', journal = 'abandon', station = 'craft', fence = 'buy' }) do
        assert(R.validate({ screen = screen, action = act, payload = { id = 'x', qty = 1 } }), screen)
    end
end)
case('jobs fixture shows an open and an accepted offer', function()
    local seen = {}
    for _, o in ipairs(F.fixtures.jobs.offers) do seen[o.accepted and 'yes' or 'no'] = true end
    assert(seen.yes and seen.no)
end)
case('parseDemo', function()
    T.same({ action = 'open', screen = 'fence' }, F.parseDemo({ 'Fence' }))
    T.same({ action = 'close' }, F.parseDemo({ 'close' }))
    T.same({ action = 'close', screen = 'heat' }, F.parseDemo({ 'close', 'heat' }))
    T.eq('fh_ui_demo_usage', select(2, F.parseDemo({})))
    T.eq('fh_ui_demo_usage', select(2, F.parseDemo(nil)))
    T.eq('fh_ui_demo_unknown_screen', select(2, F.parseDemo({ 'buffs' })))
    T.eq('fh_ui_demo_unknown_screen', select(2, F.parseDemo({ 'close', 'zzz' })))
end)

T.finish()
