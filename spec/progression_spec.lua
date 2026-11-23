-- Run from repo root: `lua spec/progression_spec.lua`.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
package.path = here .. '../server/resources/[fh]/fh_progression/shared/?.lua;' .. package.path
local case = T.it
local logic = require('progression_logic')
local regions = require('regions')

-- the real config sets a global when run as a chunk
assert(loadfile(here .. '../server/resources/[fh]/fh_progression/config.lua'))()
local cfg = FhProgressionConfig

case('config regions and unlock ids are known / seeded', function()
    for r in pairs(cfg.tiers) do assert(regions.isKnownRegion(r), r) end
    for _, id in ipairs({ 'contracts_t2', 'wagon_t2', 'fence_rare_stock', 'fence_treasure_leads', 'hire_hand' }) do
        local u = cfg.unlocks[id]
        assert(u and cfg.tiers[u.region_id], id)
    end
end)
case('tierForRep thresholds', function()
    local t = cfg.tiers.heartlands
    T.eq(1, (logic.tierForRep(cfg, 'heartlands', 0)))
    T.eq(1, (logic.tierForRep(cfg, 'heartlands', t.t2 - 1)))
    T.eq(2, (logic.tierForRep(cfg, 'heartlands', t.t2)))
    T.eq(3, (logic.tierForRep(cfg, 'heartlands', t.t3)))
    T.eq(1, (logic.tierForRep(cfg, 'heartlands', -50)))
end)
case('tierForRep unknown region / bad value never errors', function()
    local tier, why = logic.tierForRep(cfg, 'nowhere', 999)
    T.eq(1, tier); T.eq('unknown_region', why)
    tier, why = logic.tierForRep(cfg, 'heartlands', nil)
    T.eq(1, tier); T.eq('bad_value', why)
    T.eq(1, (logic.tierForRep(nil, 'heartlands', 5)))
end)
case('canUnlock gates on tier', function()
    local ok, why = logic.canUnlock(cfg, { heartlands = 0 }, 'contracts_t2')
    T.eq(false, ok); T.eq('tier_too_low', why)
    T.eq(true, (logic.canUnlock(cfg, { heartlands = cfg.tiers.heartlands.t2 }, 'contracts_t2')))
    ok = logic.canUnlock(cfg, { heartlands = cfg.tiers.heartlands.t2 }, 'fence_treasure_leads')
    T.eq(false, ok)
    T.eq(true, (logic.canUnlock(cfg, { heartlands = cfg.tiers.heartlands.t3 }, 'fence_treasure_leads')))
end)
case('canUnlock unknown unlock / missing rep / bad cfg -> false + reason', function()
    local ok, why = logic.canUnlock(cfg, {}, 'nope')
    T.eq(false, ok); T.eq('unknown_unlock', why)
    ok, why = logic.canUnlock(cfg, nil, 'contracts_t2')
    T.eq(false, ok); T.eq('tier_too_low', why)
    local bad = { tiers = {}, unlocks = { x = { region_id = 'zz', min_tier = 2 } } }
    ok, why = logic.canUnlock(bad, {}, 'x')
    T.eq(false, ok); T.eq('unknown_region', why)
    ok = logic.canUnlock(nil, {}, 'x')
    T.eq(false, ok)
end)

case('NaN / non-number rep is bad_value, tier 1, no error', function()
    for _, bad in ipairs({ 0/0, 'x', true, {} }) do
        local tier, why = logic.tierForRep(cfg, 'heartlands', bad)
        T.eq(1, tier); T.eq('bad_value', why)
    end
    local ok, why = logic.canUnlock(cfg, { heartlands = 0/0 }, 'contracts_t2')
    T.eq(false, ok); T.eq('bad_value', why)
end)
case('crossing: up, down, same tier, unknown old', function()
    local t = cfg.tiers.heartlands
    local c, o, n = logic.crossing(cfg, 'heartlands', t.t2 - 1, t.t2)
    T.eq(true, c); T.eq(1, o); T.eq(2, n)
    c, o, n = logic.crossing(cfg, 'heartlands', t.t3, t.t2)
    T.eq(true, c); T.eq(3, o); T.eq(2, n)
    c = logic.crossing(cfg, 'heartlands', 1, 5)
    T.eq(false, c)
    c, o, n = logic.crossing(cfg, 'heartlands', nil, t.t3)
    T.eq(false, c); T.eq(3, n)
    c = logic.crossing(cfg, 'heartlands', 0/0, t.t3)
    T.eq(false, c)
    c = logic.crossing(cfg, 'nowhere', 0, 999)
    T.eq(false, c)
end)

case('crossing: bad new value / unknown region never crosses (no spurious drop)', function()
    local high = cfg.tiers.heartlands.t2 + 50
    local c, o, n = logic.crossing(cfg, 'heartlands', high, nil)
    T.eq(false, c); T.eq(1, o); T.eq(1, n)
    for _, bad in ipairs({ 0/0, 'x', true }) do
        c, o, n = logic.crossing(cfg, 'heartlands', high, bad)
        T.eq(false, c); T.eq(1, o); T.eq(1, n)
    end
    T.eq(false, (logic.crossing(cfg, 'nowhere', 999, 0)))
end)

case('repExportResult follows getRep(who, region_id) -> integer|nil, err', function()
    local kind, v = logic.repExportResult(true, 120)
    T.eq('value', kind); T.eq(120, v)
    kind, v = logic.repExportResult(true, 0)
    T.eq('value', kind); T.eq(0, v)
    -- nil + err is an error passed through, never 0 and never the fallback
    for _, err in ipairs({ 'unknown_region', 'no_player', 'ledger_failed' }) do
        kind, v = logic.repExportResult(true, nil, err)
        T.eq('error', kind); T.eq(err, v)
    end
    kind, v = logic.repExportResult(true, nil)
    T.eq('error', kind); T.eq('read_failed', v)
    for _, bad in ipairs({ 0/0, math.huge, -math.huge, '5', {} }) do
        kind, v = logic.repExportResult(true, bad)
        T.eq('error', kind); T.eq('bad_value', v)
    end
    -- the call itself failed (no getRep export yet): only then the read-only fallback
    kind, v = logic.repExportResult(false, 'No such export getRep in resource fh_economy')
    T.eq('fallback', kind); T.eq(nil, v)
end)

T.finish()
