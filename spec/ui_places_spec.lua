-- Run from repo root: `lua spec/ui_places_spec.lua` (or via tools/run-specs.py).
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local case = T.it
local P = dofile(here .. '../server/resources/[fh]/fh_ui/shared/places.lua')

-- Synthetic lane configs in the same shapes as the real shared configs.
local function homesrc()
    return {
        plots = {
            heartlands_01 = { id = 'heartlands_01', center = { x = -300, y = 790, z = 118 } },
            heartlands_02 = { id = 'heartlands_02', center = { x = -150, y = 790, z = 118 } },
        },
    }
end

local function sources()
    return {
        homestead = homesrc(),
        trade = { posts = { { id = 'valentine_post', label = 'Valentine Trade Post', x = -176, y = 630, z = 114, radius = 6 } } },
        hunting = { Trapper = { label = 'Trapper', coords = { x = -299, y = 792, z = 118.2 } } },
        zones = { camps = { heartlands_t1_01 = { center = { x = -145, y = 845, z = 117 } } } },
        crafting = { devStations = { gunsmith = { x = -280, y = 805, z = 119 }, apothecary = { x = -286, y = 805, z = 119 } } },
        fence = { stops = {
            heartlands_road = { label = 'Roadside Fence', coords = { x = -280, y = 800, z = 118 } },
            heartlands_camp = { label = 'Camp-Edge Fence', coords = { x = -170, y = 830, z = 117 } },
        } },
        quests = {
            givers = {
                npc_hale = { label = 'Ruth Hale', coords = { x = -296, y = 788, z = 118.2 } },
                npc_marrow = { label = 'Sheriff Marrow', coords = { x = -280, y = 805, z = 118.5 } },
                ORDER = { 'npc_hale', 'npc_marrow' },
            },
            boards = { spots = { { id = 'heartlands_board', region_id = 'heartlands', label = 'Jobs board', coords = { x = -297, y = 795, z = 118 } } } },
        },
    }
end

case('coords reads {x,y,z} tables and rejects bad input', function()
    local x, y, z = P.coords({ x = 1, y = 2, z = 3 })
    T.eq(1, x); T.eq(2, y); T.eq(3, z)
    T.eq(nil, P.coords(nil))
    T.eq(nil, P.coords({ x = 1, y = 2 }))          -- no z
    T.eq(nil, P.coords({ x = 1, y = 2, z = 'a' })) -- non-number
    T.eq(nil, P.coords({ x = 1, y = 2, z = 0/0 })) -- NaN
end)

case('distance is euclidean and nil on unusable input', function()
    T.eq(5, P.distance({ x = 0, y = 0, z = 0 }, { x = 3, y = 4, z = 0 }))
    T.eq(0, P.distance({ x = 1, y = 1, z = 1 }, { x = 1, y = 1, z = 1 }))
    T.eq(nil, P.distance(nil, { x = 0, y = 0, z = 0 }))
    T.eq(nil, P.distance({ x = 0, y = 0, z = 0 }, { x = 0, y = 0 }))
end)

case('sprite returns per-kind name and a generic fallback', function()
    T.eq('blip_shop_trapper', P.sprite({ kind = 'trapper' }))
    T.eq('blip_shop_gunsmith', P.sprite({ kind = 'station' }))
    T.eq('blip_location_area', P.sprite({ kind = 'madeup' }))
    T.eq(nil, P.sprite(nil))
end)

case('gather pulls every place kind from the lane configs', function()
    local places = P.gather(sources())
    local byKind = {}
    for _, p in ipairs(places) do byKind[p.kind] = (byKind[p.kind] or 0) + 1 end
    T.eq(2, byKind.plot)
    T.eq(1, byKind.tradepost)
    T.eq(1, byKind.trapper)
    T.eq(1, byKind.camp)
    T.eq(2, byKind.station)
    T.eq(2, byKind.fence)
    T.eq(2, byKind.giver)
    T.eq(1, byKind.board)
    T.eq(12, #places)
end)

case('gather marks claimed and own homestead plots', function()
    local places = P.gather({ homestead = homesrc() }, { claimed = { heartlands_02 = true }, mine = 'heartlands_01' })
    local byId = {}
    for _, p in ipairs(places) do byId[p.id] = p end
    T.eq(nil, byId.heartlands_01.claimed)
    T.eq(true, byId.heartlands_01.mine)
    T.eq(true, byId.heartlands_02.claimed)
    T.eq(nil, byId.heartlands_02.mine)
end)

case('gather tolerates missing sources and nested fields', function()
    T.eq(0, #P.gather(nil))
    T.eq(0, #P.gather({ homestead = { plots = { broken = { center = { x = 1 } } } } })) -- no y/z
    T.eq(2, #P.gather({ homestead = homesrc() })) -- only homestead present
end)

case('pick resolves aliases to the nearest place of that kind', function()
    local places = P.gather(sources())
    local player = { x = -295, y = 790, z = 118 }
    T.eq('valentine_post', P.pick(places, 'tradepost', player).id)
    T.eq('valentine_post', P.pick(places, 'trade', player).id)
    T.eq('trapper', P.pick(places, 'trapper', player).id)
    T.eq('heartlands_t1_01', P.pick(places, 'camp', player).id)
    T.eq('heartlands_board', P.pick(places, 'board', player).id)
    T.eq('npc_hale', P.pick(places, 'giver', player).id) -- hale is nearest of the two givers
    T.eq('apothecary', P.pick(places, 'station', player).id)
    T.eq('heartlands_road', P.pick(places, 'fence', player).id)
end)

case('pick: plot = nearest unclaimed; all claimed reports all_claimed', function()
    local places = P.gather({ homestead = homesrc() }, { claimed = { heartlands_02 = true } })
    local near1 = { x = -150, y = 790, z = 118 } -- nearest is heartlands_02, but it is claimed
    T.eq('heartlands_01', P.pick(places, 'plot', near1).id)
    local all = P.gather({ homestead = homesrc() }, { claimed = { heartlands_01 = true, heartlands_02 = true } })
    local p, why = P.pick(all, 'plot', near1)
    T.eq(nil, p); T.eq('all_claimed', why)
end)

case('pick: exact id/label match and unknown/missing kinds', function()
    local places = P.gather(sources())
    T.eq('npc_marrow', P.pick(places, 'npc_marrow', { x = 0, y = 0, z = 0 }).id)
    T.eq('trapper', P.pick(places, 'Trapper', { x = 0, y = 0, z = 0 }).id) -- label match
    local p, why = P.pick(places, 'nope', { x = 0, y = 0, z = 0 })
    T.eq(nil, p); T.eq('unknown', why)
    local p2, why2 = P.pick({}, 'plot', { x = 0, y = 0, z = 0 })
    T.eq(nil, p2); T.eq('all_claimed', why2) -- no plots at all => all_claimed
    local p3, why3 = P.pick(places, 'trapper', nil)
    T.eq(nil, p3) -- no player position: nearest cannot be computed
    T.eq('none', why3)
end)

case('pick: empty query is list mode', function()
    local p, why = P.pick({}, '', { x = 0, y = 0, z = 0 })
    T.eq(nil, p); T.eq('list', why)
    local p2, why2 = P.pick({}, '  list  ', nil)
    T.eq(nil, p2); T.eq('list', why2)
end)

case('list sorts by distance ascending, nil dist last', function()
    local places = P.gather(sources())
    local rows = P.list(places, { x = -295, y = 790, z = 118 })
    T.eq('npc_hale', rows[1].id) -- closest
    local d = rows[1].dist
    for i = 2, #rows do T.eq(true, rows[i].dist == nil or rows[i].dist >= d); d = rows[i].dist end
    local noPlayer = P.list(places, nil)
    T.eq(nil, noPlayer[1].dist)
    T.eq(#rows, #noPlayer)
end)

T.finish()
