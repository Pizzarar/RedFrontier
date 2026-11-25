-- Run from repo root: `python tools/run-specs.py spec/quests_content_spec.lua`.
-- quests-02 C5: content fill. Every region's job-template data references only ids that exist in the source configs
-- (fh_zones camps, fh_trade posts/goods, fh_hunting animals) and belong to the right region; every offer key is
-- unique across regions; every enabled region offers >=1 of each type it has data for; every region with data has a
-- board spot; disabled regions still yield 0 board offers.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local describe, it, eq, same = T.describe, T.it, T.eq, T.same
local fh = here .. '../server/resources/[fh]/'
local shared = fh .. 'fh_quests/shared/'
package.path = shared .. '?.lua;' .. package.path
local JT = dofile(shared .. 'jobtypes.lua')
local WR = require('watch_rules')
local Board = require('board')
local BS = dofile(shared .. 'board_spots.lua')
local regions = require('regions')

-- Source configs (world_config sets FhRegions/FhPlaceResolver/vector3 before the configs resolve).
dofile(here .. 'support/world_config.lua')
dofile(fh .. 'fh_zones/config.lua')
dofile(fh .. 'fh_trade/config.lua')
local animals = dofile(fh .. 'fh_hunting/shared/animals.lua')
local zones = assert(_G.FhZonesConfig, 'FhZonesConfig missing')
local trade = assert(_G.FhTradeConfig, 'FhTradeConfig missing')

local posts = {}
for _, p in ipairs(trade.posts or {}) do posts[p.id] = p end

local FIELD = {
    hunt_request = 'hunt', camp_clear = 'camps', bounty = 'bounties', supply_run = 'supply',
    survey = 'surveys', escort = 'escorts', rescue = 'rescues',
}
local FIELDS = { 'hunt', 'camps', 'bounties', 'supply', 'surveys', 'escorts', 'rescues' }

local function hasData(d)
    for _, f in ipairs(FIELDS) do if #(d[f] or {}) > 0 then return true end end
    return false
end

describe('quests content: id references exist and match the region', function()
    it('camps, rescues, supply posts/items and hunt animals all exist in their source configs', function()
        for id, d in pairs(JT.DATA) do
            for _, c in ipairs(d.camps or {}) do
                local camp = zones.camps[c.id]
                assert(camp, id .. ' camp_clear id ' .. tostring(c.id) .. ' is not an fh_zones camp')
                eq(id, camp.region, id .. ' camp ' .. c.id .. ' region')
            end
            for _, r in ipairs(d.rescues or {}) do
                local camp = zones.camps[r.camp]
                assert(camp, id .. ' rescue camp ' .. tostring(r.camp) .. ' is not an fh_zones camp')
                eq(id, camp.region, id .. ' rescue camp ' .. r.camp .. ' region')
            end
            for _, s in ipairs(d.supply or {}) do
                local post = posts[s.post]
                assert(post, id .. ' supply post ' .. tostring(s.post) .. ' is not an fh_trade post')
                eq(id, post.region, id .. ' supply post ' .. s.post .. ' region')
                assert(trade.goods[s.item], id .. ' supply item ' .. tostring(s.item) .. ' is not an fh_trade good')
            end
            for _, h in ipairs(d.hunt or {}) do
                assert(animals.byKey[h[1]], id .. ' hunt animal ' .. tostring(h[1]) .. ' is not an fh_hunting animal')
            end
        end
    end)
end)

describe('quests content: keys and coverage', function()
    it('every offer key is unique across regions for its job type', function()
        for _, jt in ipairs(JT.TYPES) do
            local seen = {}
            for id in pairs(JT.DATA) do
                for _, o in ipairs(JT.offers(jt, id)) do
                    assert(not seen[o.key], jt .. ' key ' .. o.key .. ' appears in both ' .. tostring(seen[o.key]) .. ' and ' .. id)
                    seen[o.key] = id
                end
            end
        end
    end)
    it('every region (enabled or not) builds one offer per data entry, for every job type', function()
        for id, d in pairs(JT.DATA) do
            for _, jt in ipairs(JT.TYPES) do
                local want = #(d[FIELD[jt]] or {})
                eq(want, #JT.offers(jt, id), id .. ' ' .. jt .. ' offers vs data entries')
            end
        end
    end)
    it('escort/survey points stay at least activationRadius+25 m from EVERY fh_zones camp', function()
        local function check(id, what, p)
            for cid, camp in pairs(zones.camps) do
                local need = (camp.activationRadius or 0) + 25.0
                local dx, dy = p.x - camp.center.x, p.y - camp.center.y
                local dist = math.sqrt(dx * dx + dy * dy)
                assert(dist >= need, ('%s %s (%.0f,%.0f) is %.1f m from camp %s, need >= %.0f'):format(
                    id, what, p.x, p.y, dist, cid, need))
            end
        end
        local n = 0
        for id, d in pairs(JT.DATA) do
            for _, sv in ipairs(d.surveys or {}) do
                for i, p in ipairs(sv.points) do check(id, 'survey ' .. sv.key .. ' point ' .. i, p); n = n + 1 end
            end
            for _, e in ipairs(d.escorts or {}) do
                check(id, 'escort ' .. e.key .. ' start', e.start)
                check(id, 'escort ' .. e.key .. ' destination', e.destination)
                n = n + 2
            end
        end
        assert(n > 0, 'no survey/escort points checked')
    end)
    it('survey point pairs are more than 2x the effective watch radius apart', function()
        local pairs_checked = 0
        local bad = {}
        for id, d in pairs(JT.DATA) do
            for _, sv in ipairs(d.surveys or {}) do
                local pts = sv.points or {}
                for i = 1, #pts - 1 do
                    for j = i + 1, #pts do
                        local a, b = pts[i], pts[j]
                        local ra = a.radius or sv.radius or WR.DEFAULT_RADIUS
                        local rb = b.radius or sv.radius or WR.DEFAULT_RADIUS
                        local need = ra + rb
                        local dx, dy = a.x - b.x, a.y - b.y
                        local dist = math.sqrt(dx * dx + dy * dy)
                        if not (dist > need) then
                            bad[#bad + 1] = ('%s survey %s points %d & %d are %.1f m apart, need > %.1f'):format(
                                id, sv.key, i, j, dist, need)
                        end
                        pairs_checked = pairs_checked + 1
                    end
                end
            end
        end
        assert(pairs_checked > 0, 'no survey point pairs checked')
        assert(#bad == 0, table.concat(bad, '\n'))
    end)
    it('every enabled region offers at least one of each type it has data for', function()
        for id, d in pairs(JT.DATA) do
            if regions.isEnabled(id) then
                for _, jt in ipairs(JT.TYPES) do
                    if #(d[FIELD[jt]] or {}) > 0 then
                        assert(#JT.offers(jt, id) >= 1, id .. ' has ' .. jt .. ' data but offers none')
                    end
                end
            end
        end
    end)
    it('every enabled region offers at least one contract at each tier 1, 2, 3 (by min_tier)', function()
        local enabledCount = 0
        for id in pairs(JT.DATA) do
            if regions.isEnabled(id) then
                enabledCount = enabledCount + 1
                local byTier = { [1] = 0, [2] = 0, [3] = 0 }
                local hasT2Camp = false
                for _, jt in ipairs(JT.TYPES) do
                    for _, o in ipairs(JT.offers(jt, id)) do
                        assert(o.min_tier == 1 or o.min_tier == 2 or o.min_tier == 3,
                            id .. ' ' .. jt .. ':' .. o.key .. ' invalid min_tier ' .. tostring(o.min_tier))
                        byTier[o.min_tier] = byTier[o.min_tier] + 1
                        if jt == 'camp_clear' and o.min_tier >= 2 and type(o.camp_id) == 'string' and o.camp_id:find('_t2_', 1, true) then
                            hasT2Camp = true
                        end
                    end
                end
                for tier = 1, 3 do
                    assert(byTier[tier] >= 1, id .. ' has ' .. byTier[tier] .. ' tier-' .. tier .. ' offers (need >= 1)')
                end
                assert(hasT2Camp, id .. ' has no tier-2+ camp_clear on an existing _t2_ camp')
            end
        end
        assert(enabledCount >= 4, 'expected at least 4 enabled regions, got ' .. enabledCount)
    end)
    it('every region with data has a board spot (and every spot names a known region)', function()
        local spots = {}
        for _, s in ipairs(BS.spots) do
            assert(regions.regions[s.region_id], 'board spot region ' .. tostring(s.region_id) .. ' is unknown')
            spots[s.region_id] = true
        end
        for id, d in pairs(JT.DATA) do
            if hasData(d) then assert(spots[id], id .. ' has data but no board spot') end
        end
    end)
    it('disabled regions still yield 0 board offers', function()
        local jts = {}
        for _, name in ipairs(JT.TYPES) do
            jts[name] = { hooks = { offers = function(r) return JT.offers(name, r) end } }
        end
        for id in pairs(JT.DATA) do
            if not regions.isEnabled(id) then
                local lists = Board.collect(id, jts, regions.isEnabled)
                assert(next(lists) == nil, id .. ' (disabled) collected offers')
            end
        end
    end)
end)

T.finish()
