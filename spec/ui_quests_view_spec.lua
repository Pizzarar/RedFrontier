-- Run from repo root: `lua spec/ui_quests_view_spec.lua` (or via tools/run-specs.py).
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local case = T.it
local V = dofile(here .. '../server/resources/[fh]/fh_ui/shared/quests_view.lua')
local TX = dofile(here .. '../server/resources/[fh]/fh_quests/server/ui_text.lua')
local F = dofile(here .. '../server/resources/[fh]/fh_ui/shared/fixtures.lua')

local function snap(offers, expires)
    return { v = 1, journal = {}, board = { region_id = 'heartlands', epoch = 5, expires_at = expires or 2000, offers = offers } }
end
local offer = { id = 'heartlands:5:hunt_request:wolf_2', job_type = 'hunt_request', title = 'Wolf pelt',
    text = 'Sell one.', rewards = { money = 12, rep = { region_id = 'heartlands', delta = 5 }, items = { { name = 'bread', amount = 2 } } },
    accepted = false }

case('no board in the snapshot -> nil', function()
    assert(V.jobs({ v = 1, journal = {} }, 100) == nil)
    assert(V.jobs(nil, 100) == nil)
end)
case('empty offers stay an empty list and validate', function()
    local d = V.jobs(snap({}), 100)
    T.eq(0, #d.offers)
    T.eq(false, d.expired)
    local ok, errs = F.validate('jobs', d)
    assert(ok, table.concat(errs or {}, ';'))
end)
case('offer fields and accepted flag map through', function()
    local a = {}
    for k, v in pairs(offer) do a[k] = v end
    a.id, a.accepted = 'heartlands:5:bounty:x', true
    local d = V.jobs(snap({ offer, a }), 100)
    T.eq(2, #d.offers)
    T.eq(false, d.offers[1].accepted)
    T.eq(true, d.offers[2].accepted)
    T.eq('hunt_request', d.offers[1].job_type)
    T.eq(12, d.offers[1].rewards.money)
    T.eq(2, d.offers[1].rewards.items[1].amount)
    T.eq('heartlands', d.region_id)
    T.eq(2000, d.expires_at)
    assert(F.validate('jobs', d))
end)
case('expired board shows no offers', function()
    local d = V.jobs(snap({ offer }, 2000), 2000)
    T.eq(true, d.expired)
    T.eq(0, #d.offers)
    local d2 = V.jobs(snap({ offer }, 2000), 1999)
    T.eq(false, d2.expired)
    T.eq(1, #d2.offers)
    T.eq(false, V.jobs(snap({ offer }, 2000), nil).expired) -- no clock: not judged
end)
case('malformed offers are skipped', function()
    local d = V.jobs(snap({ 'x', { title = 'no id' }, offer }), 100)
    T.eq(1, #d.offers)
end)
case('jobs feed is registered', function() assert(V.feeds.jobs == V.jobs) end)
case('fixture jobs validate', function() assert(F.validate('jobs', F.fixtures.jobs)) end)

case('accept notice: success', function()
    local n = TX.acceptNotice(true)
    T.eq('ok', n.notice_kind)
    T.eq(TX.ACCEPTED, n.notice)
end)
case('accept notice: known codes and fallback', function()
    T.eq('That job is no longer on the board.', TX.acceptNotice(false, 'fh_offer_gone').notice)
    T.eq('error', TX.acceptNotice(false, 'fh_busy').notice_kind)
    T.eq(TX.DEFAULT, TX.acceptNotice(false, 'fh_made_up').notice)
    T.eq(TX.DEFAULT, TX.acceptNotice(false, nil).notice)
    T.eq(TX.DEFAULT, TX.acceptNotice(nil, 'fh_made_up').notice)
end)
T.finish()
