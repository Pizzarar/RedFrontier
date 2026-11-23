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

T.finish()
