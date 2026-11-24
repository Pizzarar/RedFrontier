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
    for _, id in ipairs({ 'contracts_t2', 'wagon_t2', 'fence_rare_stock', 'fence_treasure_leads', 'hire_hand',
        'wagon_t3', 'contracts_t3', 'hire_hand_2' }) do
        local u = cfg.unlocks[id]
        assert(u and cfg.tiers[u.region_id], id)
    end
end)
case('every FhRegions.isEnabled region has an ascending tier row', function()
    for id, _ in pairs(regions.regions) do
        if regions.isEnabled(id) then
            local t = cfg.tiers[id]
            assert(t, id .. ' missing tier row')
            T.eq('number', type(t.t2), id .. ' t2')
            T.eq('number', type(t.t3), id .. ' t3')
            assert(t.t3 > t.t2, id .. ' tier thresholds must ascend')
        end
    end
end)
case('every unlock names a known region with min_tier in 1..3', function()
    for id, u in pairs(cfg.unlocks) do
        assert(regions.isKnownRegion(u.region_id), id .. ' -> ' .. tostring(u.region_id))
        assert(type(u.min_tier) == 'number' and u.min_tier >= 1 and u.min_tier <= 3, id .. ' min_tier')
        assert(cfg.tiers[u.region_id], id .. ' region not configured')
    end
end)
case('wagon_t3 matches exactly', function()
    T.same({ region_id = 'heartlands', min_tier = 3 }, cfg.unlocks.wagon_t3)
end)
case('getTier climbs t1->t2->t3 in scarlett_meadows', function()
    local t = cfg.tiers.scarlett_meadows
    T.eq(1, (logic.tierForRep(cfg, 'scarlett_meadows', t.t2 - 1)))
    T.eq(2, (logic.tierForRep(cfg, 'scarlett_meadows', t.t2)))
    T.eq(3, (logic.tierForRep(cfg, 'scarlett_meadows', t.t3)))
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
    -- nil + err is an error passed through, never 0
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
    -- the call itself threw (fh_economy stopped / restarting): an error too, never 0 (no DB fallback any more)
    kind, v = logic.repExportResult(false, 'No such export getRep in resource fh_economy')
    T.eq('error', kind); T.eq('economy_unavailable', v)
end)

case('admin command is fh_rep_region (ACE command.fh_rep_region): no clash with fh_economy console fh_rep', function()
    local function commands(rel)
        local fh = assert(io.open(here .. '../server/resources/[fh]/' .. rel, 'rb'))
        local src = fh:read('a'); fh:close()
        local names = {}
        for name in src:gmatch("RegisterCommand%('([%w_]+)'") do names[#names + 1] = name end
        return names, src
    end
    local prog, src = commands('fh_progression/server/main.lua')
    T.same({ 'fh_rep_region' }, prog)
    assert(src:find("IsPlayerAceAllowed(source, 'command.fh_rep_region')", 1, true), 'ACE name')
    -- every command name across these resources is unique (FXServer keeps whichever registers last)
    local seen = {}
    for _, rel in ipairs({ 'fh_economy/server/main.lua', 'fh_progression/server/main.lua', 'fh_fence/server/main.lua',
        'fh_hands/server/main.lua' }) do
        for _, name in ipairs((commands(rel))) do
            assert(not seen[name], ('%s registered by both %s and %s'):format(name, tostring(seen[name]), rel))
            seen[name] = rel
        end
    end
    T.eq('fh_economy/server/main.lua', seen.fh_rep) -- core's console fh_rep <id> <delta> stays the only fh_rep
end)

case('parseRepCmd: valid args and every refusal code', function()
    local p = logic.parseRepCmd({ '3', 'heartlands', '-25' }, regions.isKnownRegion, 1000)
    assert(p.target == 3 and p.region_id == 'heartlands' and p.delta == -25)
    local function code(a) local _, e = logic.parseRepCmd(a, regions.isKnownRegion, 1000) return e end
    T.eq('fh_bad_target', code({ 'x', 'heartlands', '5' }))
    T.eq('fh_bad_target', code({ '0', 'heartlands', '5' }))
    T.eq('fh_bad_target', code({ '1.5', 'heartlands', '5' }))
    T.eq('unknown_region', code({ '1', 'nowhere', '5' }))
    T.eq('unknown_region', code({ '1' }))
    T.eq('invalid_delta', code({ '1', 'heartlands' }))
    T.eq('invalid_delta', code({ '1', 'heartlands', '0' }))
    T.eq('invalid_delta', code({ '1', 'heartlands', '2.5' }))
    T.eq('invalid_delta', code({ '1', 'heartlands', 'nan' }))
    T.eq('delta_too_large', code({ '1', 'heartlands', '1001' }))
    T.eq('fh_bad_target', code(nil))
end)

T.finish()
