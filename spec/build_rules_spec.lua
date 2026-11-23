local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local case = T.it
local dir = here .. '../server/resources/[fh]/fh_homestead/'
local R = dofile(dir .. 'shared/build_rules.lua')
dofile(dir .. 'config.lua') -- outside CfxLua there is no vector3: config falls back to {x,y,z}
local cfg = FhHomesteadConfig
local plot = cfg.plots.heartlands_01

local function why(slot, tiers, cid, owner, target) local _, e = R.canBuild(plot, slot, tiers, cid, owner, target) return e end

case('owner can build the first tier; stranger/none/free plot refused', function()
    assert(R.canBuild(plot, 'cabin', {}, 'A', 'A'))
    assert(why('cabin', {}, 'B', 'A') == 'fh_not_owner')
    assert(why('cabin', {}, nil, 'A') == 'fh_no_character')
    assert(why('cabin', {}, 'A', nil) == 'fh_plot_free')
    local _, e = R.canBuild(nil, 'cabin', {}, 'A', 'A')
    assert(e == 'fh_no_plot')
end)
case('tier order: next tier only, no skipping', function()
    assert(R.canBuild(plot, 'cabin', { cabin = 1 }, 'A', 'A', 2))
    assert(why('cabin', {}, 'A', 'A', 2) == 'fh_tier_order')
    assert(why('cabin', { cabin = 1 }, 'A', 'A', 1) == 'fh_tier_order')
    assert(R.nextTier(plot.slots.cabin, 0) == 1 and R.nextTier(plot.slots.cabin, 1) == 2)
end)
case('max tier', function()
    assert(why('cabin', { cabin = 2 }, 'A', 'A') == 'fh_max_tier')
    assert(why('fence', { fence = 1 }, 'A', 'A') == 'fh_max_tier')
    assert(R.nextTier(plot.slots.cabin, 2) == nil)
end)
case('prerequisite chests need cabin tier', function()
    assert(why('chest_2', {}, 'A', 'A') == 'fh_prereq_missing')
    assert(R.canBuild(plot, 'chest_2', { cabin = 1 }, 'A', 'A'))
    assert(why('chest_3', { cabin = 1 }, 'A', 'A') == 'fh_prereq_missing')
    assert(R.canBuild(plot, 'chest_3', { cabin = 2 }, 'A', 'A'))
end)
case('cost lookup', function()
    local c = R.costFor(plot.slots.cabin, 1)
    assert(c.money == 150 and c.items.wood == 20)
    assert(R.costFor(plot.slots.cabin, 3) == nil and R.costFor(plot.slots.cabin, 0) == nil)
    assert(R.costFor(nil, 1) == nil)
end)
case('unknown slot', function()
    assert(why('nope', {}, 'A', 'A') == 'fh_unknown_slot')
    assert(why(nil, {}, 'A', 'A') == 'fh_unknown_slot')
end)
case('unlocks, comfort, aggregate state', function()
    assert(R.unlocks(plot.slots.cabin, 1).chests[1] == 'chest_2')
    assert(R.unlocks(plot.slots.cabin, 9) == nil)
    local tiers = { cabin = 2, fence = 1, station_2 = 1, trophy_wall = 1 }
    local u = R.unlockedState(plot, tiers)
    assert(#u.chests == 2 and u.safeRadiusBonus == 10.0 and u.stations[1] == 'campfire' and u.trophyComfort)
    assert(R.totalComfort(plot, tiers) == 10 + 15 + 5 + 3 + 5)
    assert(R.totalComfort(plot, {}) == 0)
end)
case('propFor: fallback unless verifiedProps and a verified prop exists', function()
    assert(cfg.verifiedProps == false)
    local s = { prop = { model = 'a' }, propVerified = { model = 'b' } }
    assert(R.propFor(s, false).model == 'a' and R.propFor(s, true).model == 'b')
    assert(R.propFor({ prop = { model = 'a' } }, true).model == 'a')
end)
case('4 plots, unique ids/centers, all slot configs valid', function()
    local n, seen = 0, {}
    for id, p in pairs(cfg.plots) do
        n = n + 1
        assert(p.id == id)
        local key = p.center.x .. ',' .. p.center.y
        assert(not seen[key], 'duplicate center')
        seen[key] = true
        local bad = R.validatePlot(p)
        assert(#bad == 0, id .. ': ' .. table.concat(bad, '; '))
        for _, sid in ipairs({ 'cabin', 'fence', 'station_1', 'station_2', 'station_3', 'trophy_wall', 'chest_2', 'chest_3' }) do
            assert(p.slots[sid], id .. ' missing ' .. sid)
        end
    end
    assert(n == 4)
    assert(#R.validatePlot({ slots = { x = { maxTier = 1, tiers = {} } } }) > 0)
end)
T.finish()
