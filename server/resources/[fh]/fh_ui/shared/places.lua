-- fh_ui place aggregation + /where picking (mapblips). Pure Lua: no natives, specced under busted
-- (spec/ui_places_spec.lua). Coordinates are read from each lane's config/shared data (gathered by the client from
-- the `@`-includes in fxmanifest) so fh_ui never hardcodes a coordinate. Coords may be a vector3 or a {x,y,z} table.
local M = {}

-- RDR2 blip sprite name per place kind. The client joaat()s these and passes them to SET_BLIP_SPRITE. Names are
-- VERIFIED against femga/rdr3_discoveries `textures/blips` (the list the alloc8or DB links to); still unverified
-- in-game (confirm each renders, then adjust).
M.SPRITES = {
    plot      = 'blip_proc_home',           -- 1586273744
    tradepost = 'blip_shop_store',          -- 1475879922
    trapper   = 'blip_shop_animal_trapper', -- -1406874050
    giver     = 'blip_ambient_npc',         -- 305281166
    board     = 'blip_proc_bounty_poster',  -- -1636832113
    camp      = 'blip_region_hideout',      -- -428972082
    station   = 'blip_shop_gunsmith',       -- -145868367
    fence     = 'blip_shop_shady_store',    -- 531267562
}

-- /where query aliases -> place kind. A query that is not an alias is matched against a place id/label instead.
M.ALIASES = {
    plot = 'plot', plots = 'plot', homestead = 'plot', home = 'plot',
    tradepost = 'tradepost', trade = 'tradepost', post = 'tradepost',
    trapper = 'trapper', hunting = 'trapper', hunt = 'trapper',
    board = 'board', jobs = 'board', job = 'board',
    camp = 'camp', outlaw = 'camp',
    giver = 'giver', givers = 'giver', quest = 'giver', quests = 'giver',
    fence = 'fence',
    station = 'station', stations = 'station', crafting = 'station', gunsmith = 'station', reload = 'station', apothecary = 'station',
}

local function finite(n) return type(n) == 'number' and n == n and n > -math.huge and n < math.huge end

---Read x, y, z from a vector3 (userdata) or a plain {x,y,z} table. Returns nil on unusable input.
function M.coords(c)
    if c == nil then return nil end
    local ok, x, y, z = pcall(function() return c.x, c.y, c.z end)
    if ok and finite(x) and finite(y) and finite(z) then return x, y, z end
    return nil
end

---Euclidean distance between two {x,y,z}-like positions, or nil when either is unusable.
function M.distance(a, b)
    local ax, ay, az = M.coords(a)
    local bx, by, bz = M.coords(b)
    if not ax or not bx then return nil end
    local dx, dy, dz = ax - bx, ay - by, az - bz
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

---The blip sprite name for a place (falls back to a generic location marker).
function M.sprite(place)
    if type(place) ~= 'table' then return nil end
    return M.SPRITES[place.kind] or 'blip_location_higher'
end

local function push(places, id, kind, label, x, y, z)
    places[#places + 1] = { id = id, kind = kind, label = label, x = x, y = y, z = z }
end

---Build the canonical place list from the lane configs. sources = {
---  homestead = FhHomesteadConfig, trade = FhTradeConfig, hunting = FhHuntingConfig, zones = FhZonesConfig,
---  crafting = FhCraftingConfig, fence = FhFenceConfig, quests = { givers = FhQuestsGivers, boards = FhQuestsBoardSpots } }.
--- Any source (or nested field) may be nil; missing data is skipped, never an error.
--- opts = { claimed = { [plot_id] = true }, mine = <own plot_id> } marks homestead plots (for /where plot and sprites).
function M.gather(sources, opts)
    local places = {}
    sources = sources or {}
    opts = opts or {}
    local claimed = type(opts.claimed) == 'table' and opts.claimed or {}
    local mine = opts.mine

    -- Homestead plots (fh_homestead/config.lua: plots[id].center).
    local hs = sources.homestead
    if type(hs) == 'table' and type(hs.plots) == 'table' then
        for id, p in pairs(hs.plots) do
            if type(p) == 'table' then
                local x, y, z = M.coords(p.center)
                if x then
                    local place = { id = id, kind = 'plot', label = 'Homestead plot', x = x, y = y, z = z }
                    if claimed[id] then place.claimed = true end
                    if type(mine) == 'string' and mine == id then place.mine = true end
                    places[#places + 1] = place
                end
            end
        end
    end

    -- Trade posts (fh_trade/config.lua: posts[i] = { id, label, x, y, z, radius }).
    local tr = sources.trade
    if type(tr) == 'table' and type(tr.posts) == 'table' then
        for _, post in ipairs(tr.posts) do
            if type(post) == 'table' then
                local x, y, z = M.coords(post)
                if x then push(places, post.id, 'tradepost', post.label or 'Trade Post', x, y, z) end
            end
        end
    end

    -- Trapper (fh_hunting/config.lua: Trapper.coords / label).
    local hu = sources.hunting
    if type(hu) == 'table' and type(hu.Trapper) == 'table' then
        local x, y, z = M.coords(hu.Trapper.coords)
        if x then push(places, 'trapper', 'trapper', hu.Trapper.label or 'Trapper', x, y, z) end
    end

    -- Outlaw camps (fh_zones/config.lua: camps[id].center).
    local zn = sources.zones
    if type(zn) == 'table' and type(zn.camps) == 'table' then
        for id, camp in pairs(zn.camps) do
            if type(camp) == 'table' then
                local x, y, z = M.coords(camp.center)
                if x then push(places, id, 'camp', 'Outlaw camp', x, y, z) end
            end
        end
    end

    -- Crafting/dev stations (fh_crafting/config.lua: devStations). Dev-only placeholders; real crafting stations are
    -- per-plot on the homestead, so they have no fixed coordinate to blip.
    local cr = sources.crafting
    if type(cr) == 'table' and type(cr.devStations) == 'table' then
        local names = { gunsmith = 'Gunsmith', reload = 'Reload bench', apothecary = 'Apothecary' }
        for id, c in pairs(cr.devStations) do
            local x, y, z = M.coords(c)
            if x then push(places, id, 'station', names[id] or 'Crafting station', x, y, z) end
        end
    end

    -- Fence stops (fh_fence/config.lua: stops[id] = { label, coords }). The fence roves between stops; both are blipped.
    local fe = sources.fence
    if type(fe) == 'table' and type(fe.stops) == 'table' then
        for id, stop in pairs(fe.stops) do
            if type(stop) == 'table' then
                local x, y, z = M.coords(stop.coords)
                if x then push(places, id, 'fence', stop.label or 'Fence', x, y, z) end
            end
        end
    end

    -- Family quest givers (fh_quests/shared/givers.lua: M[id] = { label, coords }).
    local gv = sources.quests and sources.quests.givers
    if type(gv) == 'table' then
        local order = type(gv.ORDER) == 'table' and gv.ORDER or {}
        for _, id in ipairs(order) do
            local g = gv[id]
            if type(g) == 'table' then
                local x, y, z = M.coords(g.coords)
                if x then push(places, id, 'giver', g.label or 'Quest giver', x, y, z) end
            end
        end
    end

    -- Jobs board (fh_quests/shared/board_spots.lua: spots[i] = { id, region_id, label, coords }).
    local bs = sources.quests and sources.quests.boards
    if type(bs) == 'table' and type(bs.spots) == 'table' then
        for _, b in ipairs(bs.spots) do
            if type(b) == 'table' then
                local x, y, z = M.coords(b.coords)
                if x then push(places, b.id or b.region_id, 'board', b.label or 'Jobs board', x, y, z) end
            end
        end
    end

    return places
end

---Nearest place of a kind; for unclaimedOnly, skips claimed places. player = {x,y,z}.
function M.nearest(places, kind, player, unclaimedOnly)
    local best, bestD = nil, nil
    for _, p in ipairs(places or {}) do
        if p.kind == kind and not (unclaimedOnly and p.claimed) then
            local d = M.distance(p, player)
            if d ~= nil and (bestD == nil or d < bestD) then
                best, bestD = p, d
            end
        end
    end
    return best
end

local function normalize(query)
    if type(query) ~= 'string' then return '' end
    return query:lower():gsub('^%s+', ''):gsub('%s+$', '')
end

---Resolve a /where query to a place. Returns place | nil, reason.
--- reason = 'list' (no/empty query), 'all_claimed', 'none' (kind has no places), 'unknown' (no match).
--- `plot` resolves to the nearest unclaimed homestead plot; other aliases resolve to the nearest place of that kind.
function M.pick(places, query, player)
    local q = normalize(query)
    if q == '' or q == 'list' then return nil, 'list' end
    local kind = M.ALIASES[q]
    if kind == 'plot' then
        local place = M.nearest(places, 'plot', player, true)
        if place then return place end
        return nil, 'all_claimed'
    end
    if kind then
        local place = M.nearest(places, kind, player, false)
        if place then return place end
        return nil, 'none'
    end
    for _, p in ipairs(places) do
        if p.id == q or p.id == query or (p.label and p.label:lower() == q) then return p end
    end
    return nil, 'unknown'
end

---Rows sorted by distance ascending (unusable player => dist nil, sorted last). For /where with no argument.
function M.list(places, player)
    local rows = {}
    for _, p in ipairs(places or {}) do
        rows[#rows + 1] = { id = p.id, kind = p.kind, label = p.label, x = p.x, y = p.y, z = p.z, dist = M.distance(p, player) }
    end
    table.sort(rows, function(a, b)
        if a.dist == nil then return false end
        if b.dist == nil then return true end
        return a.dist < b.dist
    end)
    return rows
end

if GetCurrentResourceName then
    FhUiPlaces = M
else
    return M
end
