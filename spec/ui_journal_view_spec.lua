-- Run from repo root: `lua spec/ui_journal_view_spec.lua` (or via tools/run-specs.py).
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local case = T.it
local V = dofile(here .. '../server/resources/[fh]/fh_ui/shared/quests_view.lua')
local TX = dofile(here .. '../server/resources/[fh]/fh_quests/server/ui_text.lua')
local F = dofile(here .. '../server/resources/[fh]/fh_ui/shared/fixtures.lua')
local R = dofile(here .. '../server/resources/[fh]/fh_ui/shared/relay.lua')

local function row(id, status, updated, extra)
    local r = { quest_id = id, kind = 'line', title = 'T ' .. id, giver = nil, region_id = 'heartlands', status = status,
        step = 2, steps_total = 3, step_text = 'Do it.', count = 1, need = 3, cooldown_until = nil, updated_at = updated,
        rewards = { money = 25, rep = { region_id = 'heartlands', delta = 5 }, items = { { name = 'bread', amount = 2 } } } }
    for k, v in pairs(extra or {}) do r[k] = v end
    return r
end
local function snap(j) return { v = 1, journal = j } end

case('no journal table -> nil', function()
    assert(V.journal(nil) == nil)
    assert(V.journal({ v = 1 }) == nil)
    assert(V.journal({ journal = 'x' }) == nil)
end)
case('empty journal is an empty entries list and validates', function()
    local d = V.journal(snap({}))
    T.eq(0, #d.entries)
    assert(F.validate('journal', d))
end)
case('fields map through from the sync row', function()
    local d = V.journal(snap({ row('a', 'active', 10, { giver = 'npc_hale' }) }))
    local e = d.entries[1]
    T.eq('a', e.quest_id); T.eq('line', e.kind); T.eq('T a', e.title); T.eq('npc_hale', e.giver)
    T.eq('heartlands', e.region_id); T.eq('active', e.status); T.eq(2, e.step); T.eq(3, e.steps_total)
    T.eq('Do it.', e.step_text); T.eq(1, e.count); T.eq(3, e.need); T.eq(10, e.updated_at)
    T.eq(25, e.rewards.money); T.eq(5, e.rewards.rep.delta); T.eq(2, e.rewards.items[1].amount)
    assert(F.validate('journal', d))
end)
case('active first, then history newest first, stable on ties', function()
    local d = V.journal(snap({ row('old', 'done', 5), row('act1', 'active', 1), row('new', 'failed', 9),
        row('act2', 'active', 7), row('tie1', 'done', 5) }))
    local ids = {}
    for i, e in ipairs(d.entries) do ids[i] = e.quest_id end
    T.same({ 'act2', 'act1', 'new', 'old', 'tie1' }, ids)
end)
case('malformed rows are skipped, bad optional fields dropped', function()
    local d = V.journal(snap({ 'x', { title = 'no id' }, row('ok', 'active', 1, { step = 'two', cooldown_until = 'soon', giver = 5 }) }))
    T.eq(1, #d.entries)
    T.eq(nil, d.entries[1].step); T.eq(nil, d.entries[1].cooldown_until); T.eq(nil, d.entries[1].giver)
end)
case('journal feed is registered; fixture validates; screen relays abandon to quests', function()
    assert(V.feeds.journal == V.journal)
    assert(F.validate('journal', F.fixtures.journal))
    T.eq('quests', R.screens.journal)
    local ok, ev = R.relay(R.newLimiter(), 7, { screen = 'journal', action = 'abandon', payload = { id = 'a' } }, 0)
    assert(ok); T.eq('fh:quests:ui_abandon', ev)
end)
case('abandon notice: success, known code, fallback', function()
    local n = TX.abandonNotice(true)
    T.eq('ok', n.notice_kind); T.eq(TX.ABANDONED, n.notice)
    T.eq('You are not on that quest.', TX.abandonNotice(false, 'fh_not_active').notice)
    T.eq('error', TX.abandonNotice(false, 'fh_busy').notice_kind)
    T.eq(TX.ABANDON_DEFAULT, TX.abandonNotice(false, 'fh_made_up').notice)
    T.eq(TX.ABANDON_DEFAULT, TX.abandonNotice(nil, nil).notice)
end)
case('journal-open fallback text is its own, known codes still map', function()
    T.eq(TX.JOURNAL_OPEN_DEFAULT, TX.journalOpenText('fh_made_up'))
    T.eq(TX.JOURNAL_OPEN_DEFAULT, TX.journalOpenText(nil))
    assert(TX.JOURNAL_OPEN_DEFAULT ~= TX.ABANDON_DEFAULT)
    T.eq(TX.TEXT.fh_busy, TX.journalOpenText('fh_busy'))
end)
case('seedFor: seeds empty journal open, never over a notice or real entries, nothing without snapshot', function()
    local s = snap({ row('a', 'active', 5) })
    T.eq(1, #V.seedFor('journal', { entries = {} }, s).entries)
    T.eq(1, #V.seedFor('journal', nil, s).entries)
    assert(V.seedFor('journal', { entries = {}, notice = 'x', notice_kind = 'error' }, s) == nil)
    assert(V.seedFor('journal', { entries = { { quest_id = 'z' } } }, s) == nil)
    assert(V.seedFor('journal', { entries = {} }, nil) == nil) -- unloaded character: lastSnap cleared
    assert(V.seedFor('jobs', { offers = {} }, s) == nil)
end)
T.finish()
