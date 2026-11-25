-- Single-source coordinate resolver (world-02 block F, idea-809). Pure Lua, no natives.
-- fh_zones camps and fh_trade posts keep only gameplay fields in their configs; this fills the coordinate/region
-- fields they share with FhRegions at load, so no camp/post coordinate is defined in two places.
-- After resolution consumers see EXACTLY the same fields as before (camp.center vector3, post.x/y/z numbers).
local M = {}

local function vec3(c)
    if type(c) ~= 'table' or type(c.x) ~= 'number' or type(c.y) ~= 'number' or type(c.z) ~= 'number' then return nil end
    if vector3 then return vector3(c.x, c.y, c.z) end -- CfxLua
    return { x = c.x, y = c.y, z = c.z }              -- busted/spec table stand-in
end

---Fill `center` (vector3) and `region` (string) on each camp from FhRegions.territories[camp.territory].
---Camps keep `territory` (the id); a camp whose territory is missing/unknown is left untouched
---(world_spacing_spec asserts every camp resolves, so a bogus territory is caught there).
function M.resolveCamps(camps, regions)
    for _, camp in pairs(camps or {}) do
        local terr = regions and regions.territories and regions.territories[camp.territory]
        if terr then
            camp.region = terr.region
            camp.center = vec3(terr.center)
        end
    end
end

---Fill `region`, `x`, `y`, `z` on each post from FhRegions.posts[post.id].
function M.resolvePosts(posts, regions)
    for _, post in ipairs(posts or {}) do
        local p = regions and regions.posts and regions.posts[post.id]
        if p then
            post.region = p.region
            post.x, post.y, post.z = p.x, p.y, p.z
        end
    end
end

-- ------------------------------------------------------------------ world-03 J: walk-tool place index
-- Pure id -> place index plus nearest/tour/mark helpers for fh_tp / fh_tour / fh_mark (server/admin.lua).
-- No natives, no ox_lib, no I/O: specced under busted (spec/walk_tool_spec.lua). "Unverified" = verified ~= true
-- (nil counts); the index normalises `verified` to a boolean (default false) so towns/posts/territories (which carry
-- no flag) are walked too. Distances here are 2D (x,y): place z is only a snap hint, never a proximity measure.

local function finite(n) return type(n) == 'number' and n == n and n > -math.huge and n < math.huge end

---x, y, z numbers from a vector3 (userdata) or a plain {x,y,z} table, or nil. Same pcall idiom as fh_ui places.lua.
local function xyz(c)
    if c == nil then return nil end
    local ok, x, y, z = pcall(function() return c.x, c.y, c.z end)
    if ok and finite(x) and finite(y) and finite(z) then return x, y, z end
    return nil
end

local function dist2d(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return math.sqrt(dx * dx + dy * dy)
end

---Build the walk-tool place index (world-03 J). Returns two views of the same entries:
---  places = array of { id, x, y, z, kind, region, verified, label?, class? }, deterministically sorted by (kind, id);
---  byId   = map id -> same entry. A camp resolves to the SAME entry as its territory (both ids work for fh_tp; the
---  physical spot is listed once), so fh_tour never visits one place twice.
---Covers FhRegions towns/territories/posts/ambush, fh_homestead plots (class 'town_lot' -> kind 'lot', else 'claim')
---and resolved fh_zones camps. Any absent table (ambush, homestead, zones) is skipped, never an error.
---sources = { homestead = FhHomesteadConfig, zones = FhZonesConfig } (both optional).
function M.index(regions, sources)
    local places, byId = {}, {}
    local byCoord = {}
    sources = sources or {}
    local function coordKey(x, y, z) return tostring(x) .. ',' .. tostring(y) .. ',' .. tostring(z) end
    local function put(id, kind, label, x, y, z, region, verified, class)
        if type(id) ~= 'string' or id == '' then return end
        if not (finite(x) and finite(y) and finite(z)) then return end
        if byId[id] then return end
        local key = coordKey(x, y, z)
        local existing = byCoord[key]
        if existing then
            byId[id] = existing -- alias: same physical spot (a camp and its territory), listed once
            return
        end
        local p = { id = id, kind = kind, x = x, y = y, z = z, region = region, verified = verified == true }
        if class ~= nil then p.class = class end
        if type(label) == 'string' and label ~= '' then p.label = label end
        byId[id] = p
        byCoord[key] = p
        places[#places + 1] = p
    end

    for _, region in pairs((regions and regions.regions) or {}) do
        for _, town in ipairs(region.towns or {}) do
            put(town.id, 'town', town.label, town.x, town.y, town.z, region.id, town.verified)
        end
        for _, amb in ipairs(region.ambush or {}) do -- block H adds ambush in parallel; absent -> skipped
            put(amb.id, 'ambush', amb.label, amb.x, amb.y, amb.z, region.id, amb.verified)
        end
    end
    for _, t in pairs((regions and regions.territories) or {}) do
        local x, y, z = xyz(t.center)
        if x then put(t.id, 'camp', t.label, x, y, z, t.region, t.verified) end
    end
    for _, post in pairs((regions and regions.posts) or {}) do
        put(post.id, 'post', post.label, post.x, post.y, post.z, post.region, post.verified)
    end

    local hs = sources.homestead
    if type(hs) == 'table' and type(hs.plots) == 'table' then
        for id, plot in pairs(hs.plots) do
            if type(plot) == 'table' then
                local x, y, z = xyz(plot.center)
                if x then put(id, plot.class == 'town_lot' and 'lot' or 'claim', plot.name, x, y, z, plot.region,
                    plot.verified, plot.class) end
            end
        end
    end

    local zn = sources.zones
    if type(zn) == 'table' and type(zn.camps) == 'table' then
        for id, camp in pairs(zn.camps) do
            if type(camp) == 'table' then
                local x, y, z = xyz(camp.center)
                if x then put(id, 'camp', camp.name, x, y, z, camp.region, camp.verified) end
            end
        end
    end

    -- Deterministic order: sort by kind then id (ids are unique, so this is total and stable regardless of the
    -- pairs() iteration order above). Makes nearest tie-breaks and the tour's greedy order reproducible.
    table.sort(places, function(a, b)
        if a.kind ~= b.kind then return a.kind < b.kind end
        return a.id < b.id
    end)
    return places, byId
end

---Nearest place within maxDist (inclusive) of `player` ({x,y,z} or vector3), 2D. Returns place, distance | nil.
function M.nearest(places, player, maxDist)
    local px, py = xyz(player)
    if not px then return nil end
    local best, bestD
    for _, p in ipairs(places or {}) do
        local d = dist2d(p.x, p.y, px, py)
        if (maxDist == nil or d <= maxDist) and (bestD == nil or d < bestD) then
            best, bestD = p, d
        end
    end
    return best, bestD
end

---Greedy nearest-neighbour riding order for a region's unverified places (world-03 J). Starts from the region's first
---town (the first 'town' entry in `places`, deterministic since `places` is sorted by kind then id), which is the origin
---and not part of the order; with no town it starts from the first candidate. Returns an array of places (empty when the
---region has none).
function M.tour(places, region)
    local start
    for _, p in ipairs(places or {}) do
        if p.kind == 'town' and p.region == region then start = p; break end
    end
    local pending = {}
    for _, p in ipairs(places or {}) do
        if p.region == region and p.verified ~= true and not (start and p.id == start.id) then
            pending[#pending + 1] = p
        end
    end
    local order, cur = {}, start
    while #pending > 0 do
        local best, bestI, bestD
        for i, p in ipairs(pending) do
            local d = cur and dist2d(cur.x, cur.y, p.x, p.y) or 0
            if bestD == nil or d < bestD then best, bestI, bestD = p, i, d end
        end
        if not best then break end
        order[#order + 1] = best
        table.remove(pending, bestI)
        cur = best
    end
    return order
end

---Advance a tour state to the next place. Mutates state.index. Returns the next place, or nil when the tour is done
---(index has run past the end) — the caller drops the state on nil.
function M.advanceTour(state)
    if type(state) ~= 'table' or type(state.order) ~= 'table' then return nil end
    state.index = (state.index or 0) + 1
    if state.index > #state.order then return nil end
    return state.order[state.index]
end

M.MAX_MARKS = 2000

---Build a mark record (world-03 J) from the standing place + player state. Pure; the server passes ts (os.time) and
---by (source id). Shape: { id, verdict, note, x, y, z, ts, by } (note omitted when nil, as JSON drops nils).
function M.markRecord(place, verdict, note, coords, ts, by)
    return {
        id = place and place.id, verdict = verdict, note = note,
        x = coords and coords.x, y = coords and coords.y, z = coords and coords.z,
        ts = ts, by = by,
    }
end

---Append a mark record to a list (append-only), keeping the last `cap` entries (default M.MAX_MARKS). Pure, no I/O.
function M.appendMark(entries, record, cap)
    local out = {}
    if type(entries) == 'table' then
        for i = 1, #entries do out[i] = entries[i] end
    end
    out[#out + 1] = record
    local n = (type(cap) == 'number' and cap >= 1 and cap == math.floor(cap)) and cap or M.MAX_MARKS
    if #out > n then
        local kept = {}
        for i = #out - n + 1, #out do kept[#kept + 1] = out[i] end
        return kept
    end
    return out
end

---Read-append-write one mark via injected I/O (world-03 J). deps = { load = fn()->raw|nil, save = fn(str),
---encode = fn(entries)->str, decode = fn(raw)->entries }. The server injects LoadResourceFile/SaveResourceFile + json;
---this file stays native-free (specced under busted). Returns the new entries, or nil, '<error>'.
function M.recordWalkMark(deps, record, cap)
    if type(deps) ~= 'table' or type(deps.load) ~= 'function' or type(deps.save) ~= 'function'
        or type(deps.encode) ~= 'function' or type(deps.decode) ~= 'function' then
        return nil, 'fh_mark_bad_deps'
    end
    local raw = deps.load()
    local entries = {}
    if type(raw) == 'string' and raw ~= '' then
        local ok, decoded = pcall(deps.decode, raw)
        if ok and type(decoded) == 'table' then entries = decoded end
    end
    local out = M.appendMark(entries, record, cap)
    deps.save(deps.encode(out))
    return out
end

if GetCurrentResourceName then
    FhPlaceResolver = M
else
    return M
end
