-- Run from repo root: `~/.venvs/rf/bin/python tools/run-specs.py spec/world_readiness_spec.lua`.
-- world-03 (block I): every one of the 15 regions is ready to be switched on (fh_regions_enabled convar). Per region:
--   >=3 claims; >=1 town lot when the region has a town; >=3 camps owned (via territory) by a gang faction
--   (kind='outlaw'); >=1 trade post; >=2 ambush nodes; a law and a gang faction in regions[].factions; every id
--   resolving (camp<->territory<->faction, plot/post/territory<->region); and the world-01/03 spacing rules
--   (same thresholds as world_spacing_spec and homestead_sites_spec). Prints a per-region table (ready / missing X).
-- Thresholds are the plan's; if data is short, fix the data, never the numbers here.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local case = T.it
local fh = here .. '../server/resources/[fh]/'

local regions = dofile(here .. 'support/world_config.lua')
dofile(fh .. 'fh_zones/config.lua')
dofile(fh .. 'fh_homestead/config.lua')
dofile(fh .. 'fh_trade/config.lua')
local zones = assert(_G.FhZonesConfig, 'FhZonesConfig missing')
local homestead = assert(_G.FhHomesteadConfig, 'FhHomesteadConfig missing')
local trade = assert(_G.FhTradeConfig, 'FhTradeConfig missing')

local MIN = { claims = 3, lots = 1, camps = 3, posts = 1, ambush = 2 }
local CAMP_GAP, AMBUSH_GAP, CLAIM_GAP = 200.0, 200.0, 150.0 -- world_spacing_spec / homestead_sites_spec

local function dist2d(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

local ids = {}
for id in pairs(regions.regions) do ids[#ids + 1] = id end
table.sort(ids)

-- report[region] = { counts..., missing = { 'reason', ... } }
local report = {}
for _, id in ipairs(ids) do report[id] = { claims = 0, lots = 0, camps = 0, posts = 0, ambush = 0, missing = {} } end
local orphans = {} -- problems that do not belong to any known region (a bad region id)
local function miss(region, why)
    local r = report[region]
    if r then r.missing[#r.missing + 1] = why else orphans[#orphans + 1] = tostring(region) .. ': ' .. why end
end

-- ---------------------------------------------------------------- plots (plot <-> region)
local claims, lots = {}, {}
for pid, p in pairs(homestead.plots) do
    if not regions.isKnownRegion(p.region) then
        miss(p.region, 'plot ' .. pid .. ' has unknown region')
    elseif p.class == 'claim' then
        claims[pid] = p
        report[p.region].claims = report[p.region].claims + 1
    elseif p.class == 'town_lot' then
        lots[pid] = p
        report[p.region].lots = report[p.region].lots + 1
    end
end

-- ---------------------------------------------------------------- camps (camp <-> territory <-> faction <-> region)
for cid, c in pairs(zones.camps) do
    local t = regions.getTerritory(c.territory)
    local f = t and regions.getFaction(t.faction)
    if not t then
        miss(c.region, 'camp ' .. cid .. ' territory ' .. tostring(c.territory) .. ' unresolved')
    elseif not regions.isKnownRegion(t.region) then
        miss(t.region, 'territory ' .. t.id .. ' has unknown region')
    elseif c.region ~= t.region then
        miss(t.region, 'camp ' .. cid .. ' region ' .. tostring(c.region) .. ' ~= territory region')
    elseif not f then
        miss(t.region, 'territory ' .. t.id .. ' faction ' .. tostring(t.faction) .. ' unresolved')
    elseif f.kind ~= 'outlaw' then
        miss(t.region, 'camp ' .. cid .. ' owned by non-gang ' .. f.id)
    else
        report[t.region].camps = report[t.region].camps + 1
    end
end

-- every territory listed by a region resolves back to that region, and has a camp
local campByTerritory = {}
for cid, c in pairs(zones.camps) do campByTerritory[c.territory] = cid end
for _, id in ipairs(ids) do
    for _, tid in ipairs(regions.regions[id].territories or {}) do
        local t = regions.getTerritory(tid)
        if not t then miss(id, 'territory ' .. tid .. ' unresolved')
        elseif t.region ~= id then miss(id, 'territory ' .. tid .. ' points at ' .. tostring(t.region))
        elseif not campByTerritory[tid] then miss(id, 'territory ' .. tid .. ' has no camp') end
    end
end
for tid, t in pairs(regions.territories) do
    local listed = false
    for _, x in ipairs((regions.regions[t.region] or {}).territories or {}) do if x == tid then listed = true end end
    if not listed then miss(t.region, 'territory ' .. tid .. ' not listed in regions[].territories') end
end

-- ---------------------------------------------------------------- posts (registry <-> fh_trade <-> region)
local tradeIds = {}
for _, p in ipairs(trade.posts) do tradeIds[p.id] = true end
for pid, p in pairs(regions.posts) do
    if not regions.isKnownRegion(p.region) then miss(p.region, 'post ' .. pid .. ' has unknown region')
    elseif not tradeIds[pid] then miss(p.region, 'post ' .. pid .. ' not in FhTradeConfig.posts')
    else report[p.region].posts = report[p.region].posts + 1 end
end
for _, p in ipairs(trade.posts) do
    if not regions.getPost(p.id) then orphans[#orphans + 1] = 'trade post ' .. p.id .. ' not in FhRegions.posts' end
end

-- ---------------------------------------------------------------- per-region counts, factions, ambush
for _, id in ipairs(ids) do
    local r, rep = regions.regions[id], report[id]
    rep.ambush = #(r.ambush or {})
    local law, gang = false, false
    for _, fid in ipairs(r.factions or {}) do
        local f = regions.getFaction(fid)
        if not f then miss(id, 'faction ' .. fid .. ' unresolved')
        elseif f.kind == 'law' then law = true
        elseif f.kind == 'outlaw' then gang = true end
    end
    if not law then miss(id, 'law faction') end
    if not gang then miss(id, 'gang faction') end
    if rep.claims < MIN.claims then miss(id, ('claims %d/%d'):format(rep.claims, MIN.claims)) end
    if #(r.towns or {}) >= 1 and rep.lots < MIN.lots then miss(id, ('lots %d/%d'):format(rep.lots, MIN.lots)) end
    if rep.camps < MIN.camps then miss(id, ('gang camps %d/%d'):format(rep.camps, MIN.camps)) end
    if rep.posts < MIN.posts then miss(id, ('posts %d/%d'):format(rep.posts, MIN.posts)) end
    if rep.ambush < MIN.ambush then miss(id, ('ambush %d/%d'):format(rep.ambush, MIN.ambush)) end
end

-- ---------------------------------------------------------------- spacing (blamed on the region of the moved thing)
local towns = {}
for _, r in pairs(regions.regions) do for _, t in ipairs(r.towns or {}) do towns[#towns + 1] = t end end

local function keepsGap(region, what, pos, gap, skipClaim)
    for cid, p in pairs(claims) do
        if cid ~= skipClaim and dist2d(pos, p.center) < gap then miss(region, what .. ' <' .. gap .. ' m from claim ' .. cid) end
    end
    for _, t in ipairs(towns) do
        if dist2d(pos, t) < gap then miss(region, what .. ' <' .. gap .. ' m from town ' .. tostring(t.id)) end
    end
end

for cid, c in pairs(zones.camps) do
    if regions.isKnownRegion(c.region) and c.center then
        keepsGap(c.region, 'camp ' .. cid, c.center, CAMP_GAP)
        for lid, p in pairs(lots) do
            if dist2d(c.center, p.center) < CAMP_GAP then miss(c.region, 'camp ' .. cid .. ' <200 m from lot ' .. lid) end
        end
    end
end
for _, id in ipairs(ids) do
    for _, a in ipairs(regions.regions[id].ambush or {}) do
        keepsGap(id, 'ambush ' .. tostring(a.id), a, AMBUSH_GAP)
        for lid, p in pairs(lots) do
            if dist2d(a, p.center) < AMBUSH_GAP then miss(id, 'ambush ' .. tostring(a.id) .. ' <200 m from lot ' .. lid) end
        end
        for tid, t in pairs(regions.territories) do
            if dist2d(a, t.center) < t.radius then miss(id, 'ambush ' .. tostring(a.id) .. ' inside territory ' .. tid) end
        end
    end
end
for cid, p in pairs(claims) do keepsGap(p.region, 'claim ' .. cid, p.center, CLAIM_GAP, cid) end
local tids = {}
for tid in pairs(regions.territories) do tids[#tids + 1] = tid end
table.sort(tids)
for i = 1, #tids do
    for j = i + 1, #tids do
        local a, b = regions.territories[tids[i]], regions.territories[tids[j]]
        if dist2d(a.center, b.center) < a.radius + b.radius then miss(a.region, 'territory ' .. tids[i] .. ' overlaps ' .. tids[j]) end
    end
end
for lid, p in pairs(lots) do
    for oid, o in pairs(homestead.plots) do
        if oid ~= lid then
            local d = math.sqrt((p.center.x - o.center.x) ^ 2 + (p.center.y - o.center.y) ^ 2 + (p.center.z - o.center.z) ^ 2)
            if d <= p.radius + o.radius then miss(p.region, 'lot ' .. lid .. ' overlaps ' .. oid) end
        end
    end
end

-- ---------------------------------------------------------------- table
local function render()
    local lines = { ('%-18s %-3s %6s %4s %5s %5s %6s  %s'):format('region', 'on', 'claims', 'lots', 'camps', 'posts', 'ambush', 'status') }
    for _, id in ipairs(ids) do
        local rep = report[id]
        local status = #rep.missing == 0 and 'ready' or ('missing ' .. table.concat(rep.missing, '; '))
        lines[#lines + 1] = ('%-18s %-3s %6d %4d %5d %5d %6d  %s'):format(id, regions.regions[id].enabled and 'y' or '-',
            rep.claims, rep.lots, rep.camps, rep.posts, rep.ambush, status)
    end
    for _, o in ipairs(orphans) do lines[#lines + 1] = 'orphan: ' .. o end
    return table.concat(lines, '\n')
end
print(render())

case('the registry has all 15 regions', function()
    T.eq(15, #ids, 'region count')
end)

case('every region is ready (see the table above)', function()
    local bad = {}
    for _, id in ipairs(ids) do
        if #report[id].missing > 0 then bad[#bad + 1] = id .. ': ' .. table.concat(report[id].missing, '; ') end
    end
    for _, o in ipairs(orphans) do bad[#bad + 1] = 'orphan ' .. o end
    assert(#bad == 0, 'not ready:\n' .. table.concat(bad, '\n'))
end)

T.finish()
