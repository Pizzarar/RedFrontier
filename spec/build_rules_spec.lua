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
    assert(c.money == 150 and c.items.lumber == 20)
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
case('65 plots, unique ids/centers, all slot configs valid', function()
    local n, seen = 0, {}
    for id, p in pairs(cfg.plots) do
        n = n + 1
        assert(p.id == id)
        local key = p.center.x .. ',' .. p.center.y
        assert(not seen[key], 'duplicate center')
        seen[key] = true
        local bad = R.validatePlot(p)
        assert(#bad == 0, id .. ': ' .. table.concat(bad, '; '))
        -- H9: slots by class (claim = full template, town_lot = chest_2 + station_1)
        local want = p.class == 'town_lot' and { 'chest_2', 'station_1' }
            or { 'cabin', 'fence', 'station_1', 'station_2', 'station_3', 'trophy_wall', 'chest_2', 'chest_3' }
        for _, sid in ipairs(want) do
            assert(p.slots[sid], id .. ' missing ' .. sid)
        end
    end
    assert(n == 65)
    assert(#R.validatePlot({ slots = { x = { maxTier = 1, tiers = {} } } }) > 0)
end)
case('no two plots overlap at max fenced radius', function()
    local function maxR(p)
        local r = p.radius
        for _, slot in pairs(p.slots) do
            for tier = 1, slot.maxTier do r = r + ((R.unlocks(slot, tier) or {}).safeRadiusBonus or 0) end
        end
        return r
    end
    assert(maxR(cfg.plots.heartlands_01) == 35.0)
    local ids = {}
    for id in pairs(cfg.plots) do ids[#ids + 1] = id end
    table.sort(ids)
    for i = 1, #ids do
        for j = i + 1, #ids do
            local a, b = cfg.plots[ids[i]], cfg.plots[ids[j]]
            local d = math.sqrt((a.center.x - b.center.x) ^ 2 + (a.center.y - b.center.y) ^ 2 + (a.center.z - b.center.z) ^ 2)
            assert(d > maxR(a) + maxR(b), ids[i] .. ' overlaps ' .. ids[j])
        end
    end
end)
-- ---- H9: per-class slot templates (plan homestead-02) ----
local function keys(t) local o = {} for k in pairs(t) do o[#o + 1] = k end table.sort(o) return o end
case('H9 town_lot template: chest_2 + station_1 workbench only, no cabin/fence/trophy wall, valid', function()
    local lot = cfg.slotTemplates.town_lot()
    T.same({ 'chest_2', 'station_1' }, keys(lot))
    assert(lot.cabin == nil and lot.fence == nil and lot.trophy_wall == nil)
    T.eq('workbench', lot.station_1.stationType)
    T.eq(nil, lot.chest_2.requires, 'no cabin on a lot: chest_2 has no prerequisite')
    local lp = { id = 'lot_x', class = 'town_lot', center = { x = 0, y = 0, z = 0 }, radius = 14.0, slots = lot }
    T.same({}, R.validatePlot(lp))
    T.eq('fh_unknown_slot', select(2, R.canBuild(lp, 'cabin', {}, 'A', 'A')))
    T.eq('fh_unknown_slot', select(2, R.canBuild(lp, 'fence', {}, 'A', 'A')))
    assert(R.canBuild(lp, 'chest_2', {}, 'A', 'A'))
    assert(R.canBuild(lp, 'station_1', {}, 'A', 'A'))
    T.same({ 'workbench' }, R.unlockedState(lp, { station_1 = 1 }).stations)
    -- fresh tables per call: editing one lot's template never leaks into another plot or the claim template
    lot.station_1.maxTier = 9
    T.eq(1, cfg.slotTemplates.town_lot().station_1.maxTier)
    T.eq(1, cfg.slotTemplates.claim().station_1.maxTier)
end)
case('H9 claim template unchanged: every claim plot carries exactly slotTemplates.claim()', function()
    local claimT = cfg.slotTemplates.claim()
    T.same({ 'cabin', 'chest_2', 'chest_3', 'fence', 'garden', 'station_1', 'station_2', 'station_3', 'trophy_wall' }, keys(claimT))
    T.eq('garden', claimT.garden.stationType) -- H19: claims only (the town lot template has no garden)
    T.eq(nil, cfg.slotTemplates.town_lot().garden)
    T.same({ cabin = 1 }, claimT.chest_2.requires)
    for id, p in pairs(cfg.plots) do
        if (p.class or 'claim') == 'claim' then T.same(claimT, p.slots, id) end
    end
end)
case('H9 config applies the template by class (a lot entry listing claim slots still gets the lot template)', function()
    local saved = FhHomesteadConfig
    local fh = assert(io.open(dir .. 'config.lua', 'rb')); local src = fh:read('a'); fh:close()
    -- inject two test entries into a fresh copy of the plots table (real lot entries come from @world block B)
    src = src:gsub('    plots = {\n', "    plots = {\n        t_lot = { id = 't_lot', class = 'town_lot', slots = slotTemplate() },\n"
        .. "        t_lot2 = { id = 't_lot2', class = 'town_lot' },\n        t_odd = { id = 't_odd', class = 'mystery' },\n", 1)
    assert(load(src, '@config.lua', 't', _ENV))()
    local c = FhHomesteadConfig
    FhHomesteadConfig = saved
    T.same({ 'chest_2', 'station_1' }, keys(c.plots.t_lot.slots))
    T.same({ 'chest_2', 'station_1' }, keys(c.plots.t_lot2.slots))
    T.same({}, c.plots.t_odd.slots, 'unknown class: no slots')
    T.same(c.slotTemplates.claim(), c.plots.heartlands_01.slots)
end)
case('H9 every world town_lot entry gets the lot template (chest_2 + station_1 only)', function()
    local n = 0
    for id, p in pairs(cfg.plots) do
        if p.class == 'town_lot' then
            n = n + 1
            T.same({ 'chest_2', 'station_1' }, keys(p.slots), id)
            T.same(cfg.slotTemplates.town_lot(), p.slots, id)
        end
    end
    assert(n > 0, 'config has town lots')
end)
case('H9 safeRadiusFor: claim = base + fence; town lot = plot.radius, no fence bonus', function()
    T.eq(25.0, R.safeRadiusFor(plot, {}, cfg.baseSafeRadius))
    T.eq(35.0, R.safeRadiusFor(plot, { fence = 1 }, cfg.baseSafeRadius))
    local lp = { class = 'town_lot', radius = 13.0, slots = cfg.slotTemplates.claim() }
    T.eq(13.0, R.safeRadiusFor(lp, {}, cfg.baseSafeRadius))
    T.eq(13.0, R.safeRadiusFor(lp, { fence = 1 }, cfg.baseSafeRadius), 'even a stray fence row adds nothing')
    T.eq(0, R.safeRadiusFor(nil, {}, 25))
end)
T.finish()
