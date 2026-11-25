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
    T.eq('blip_shop_animal_trapper', P.sprite({ kind = 'trapper' }))
    T.eq('blip_shop_gunsmith', P.sprite({ kind = 'station' }))
    T.eq('blip_shop_shady_store', P.sprite({ kind = 'fence' }))
    T.eq('blip_location_higher', P.sprite({ kind = 'madeup' }))
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

case('pick: plot skips town lots (claimable=false); all_claimed ignores lots', function()
    local home = { plots = {
        lot = { id = 'lot', name = 'Main Street lot', class = 'town_lot', claimable = false, center = { x = 0, y = 0, z = 0 } },
        claim = { id = 'claim', name = 'Creek claim', class = 'claim', center = { x = 500, y = 0, z = 0 } },
    } }
    local places = P.gather({ homestead = home })
    local byId = {}
    for _, p in ipairs(places) do byId[p.id] = p end
    T.eq('Main Street lot (coming soon)', byId.lot.label) -- the lot keeps its name in the label
    -- only the (nearby) lot is unclaimed, but it is not claimable: /where plot routes to the farther claim
    local player = { x = 0, y = 0, z = 0 }
    T.eq('claim', P.pick(places, 'plot', player).id)
    -- all claims taken, only the lot remains: /where plot reports all_claimed
    local taken = P.gather({ homestead = home }, { claimed = { claim = true } })
    local p, why = P.pick(taken, 'plot', player)
    T.eq(nil, p); T.eq('all_claimed', why)
end)

case('pick: a claimable town lot (H10) is labelled "(town lot)" and never routes /where plot', function()
    local home = { plots = {
        lot = { id = 'lot', name = 'Main Street lot', class = 'town_lot', claimable = true, center = { x = 0, y = 0, z = 0 } },
        claim = { id = 'claim', name = 'Creek claim', class = 'claim', center = { x = 500, y = 0, z = 0 } },
    } }
    local places = P.gather({ homestead = home })
    local byId = {}
    for _, p in ipairs(places) do byId[p.id] = p end
    T.eq('Main Street lot (town lot)', byId.lot.label) -- claimable lot: '(town lot)', not '(coming soon)'
    -- the nearby claimable lot is skipped for /where plot: it routes to the farther claim
    local player = { x = 0, y = 0, z = 0 }
    T.eq('claim', P.pick(places, 'plot', player).id)
    -- all claims taken, only the (now claimable) lot remains: /where plot reports all_claimed (lots don't count)
    local taken = P.gather({ homestead = home }, { claimed = { claim = true } })
    local p, why = P.pick(taken, 'plot', player)
    T.eq(nil, p); T.eq('all_claimed', why)
end)

case('pick: /where lot = nearest unowned claimable town lot; skips owned, claimable=false, disabled region, claims', function()
    local home = { plots = {
        lot_near_owned = { id = 'lot_near_owned', name = 'Owned lot', class = 'town_lot', claimable = true, region = 'heartlands', center = { x = 1, y = 0, z = 0 } },
        lot_soon       = { id = 'lot_soon', name = 'Soon lot', class = 'town_lot', claimable = false, region = 'heartlands', center = { x = 2, y = 0, z = 0 } },
        lot_off        = { id = 'lot_off', name = 'Off lot', class = 'town_lot', claimable = true, region = 'offregion', center = { x = 3, y = 0, z = 0 } },
        claim_near     = { id = 'claim_near', name = 'Creek claim', class = 'claim', claimable = true, region = 'heartlands', center = { x = 4, y = 0, z = 0 } },
        lot_far        = { id = 'lot_far', name = 'Far lot', class = 'town_lot', claimable = true, region = 'heartlands', center = { x = 50, y = 0, z = 0 } },
        lot_farther    = { id = 'lot_farther', name = 'Farther lot', class = 'town_lot', claimable = true, region = 'heartlands', center = { x = 90, y = 0, z = 0 } },
    } }
    local player = { x = 0, y = 0, z = 0 }
    local places = P.gather({ homestead = home }, { claimed = { lot_near_owned = true },
        isEnabled = function(r) return r ~= 'offregion' end })
    for _, alias in ipairs({ 'lot', 'lots', 'townlot', 'town_lot', ' LOT ' }) do
        local p = P.pick(places, alias, player)
        T.eq('lot_far', p.id)
        T.eq('Far lot (town lot)', p.label)
    end
    -- /where plot is unchanged: nearest unclaimed claim-class plot, never a lot
    T.eq('claim_near', P.pick(places, 'plot', player).id)
    -- take the last two lots: only claims remain => no_lot; /where plot still works
    local taken = P.gather({ homestead = home }, { claimed = { lot_near_owned = true, lot_far = true, lot_farther = true },
        isEnabled = function(r) return r ~= 'offregion' end })
    local p, why = P.pick(taken, 'lot', player)
    T.eq(nil, p); T.eq('no_lot', why)
    T.eq('claim_near', P.pick(taken, 'plot', player).id)
    -- a claims-only world has no lot to offer
    local p2, why2 = P.pick(P.gather({ homestead = homesrc() }), 'lot', player)
    T.eq(nil, p2); T.eq('no_lot', why2)
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

case('enabled gate: gather drops places in disabled regions, keeps regionless places', function()
    local src = { homestead = { plots = {
        a = { id = 'a', center = { x = 0, y = 0, z = 0 }, region = 'heartlands' },
        b = { id = 'b', center = { x = 10, y = 0, z = 0 }, region = 'tall_trees' },
        c = { id = 'c', center = { x = 20, y = 0, z = 0 } }, -- no region: never gated
    } } }
    local enabled = { heartlands = true, tall_trees = false }
    local places = P.gather(src, { isEnabled = function(id) return enabled[id] == true end })
    local ids = {}
    for _, p in ipairs(places) do ids[p.id] = true end
    T.eq(true, ids.a)
    T.eq(nil, ids.b)  -- disabled region dropped
    T.eq(true, ids.c) -- no region kept
    T.eq(3, #P.gather(src)) -- without isEnabled nothing is dropped
end)

case('gather carries region and verified onto region-associated places', function()
    local src = {
        homestead = { plots = { h1 = { id = 'h1', center = { x = 0, y = 0, z = 0 }, region = 'heartlands', verified = false } } },
        zones = { camps = { c1 = { center = { x = 1, y = 0, z = 0 }, region = 'heartlands', verified = false } } },
        trade = { posts = { { id = 'p1', label = 'Post', x = 2, y = 0, z = 0, region = 'heartlands', verified = false } } },
        quests = { boards = { spots = { { id = 'b1', region_id = 'heartlands', label = 'Board', coords = { x = 3, y = 0, z = 0 } } } } },
    }
    local places = P.gather(src)
    local byId = {}
    for _, p in ipairs(places) do byId[p.id] = p end
    T.eq('heartlands', byId.h1.region)
    T.eq(false, byId.h1.verified)
    T.eq(false, byId.c1.verified)
    T.eq(false, byId.p1.verified)
    T.eq('heartlands', byId.b1.region) -- board region comes from region_id
    T.eq(nil, byId.b1.verified)
end)

case('tag appends "(unverified)" only for verified == false', function()
    T.eq(' (unverified)', P.tag({ verified = false }))
    T.eq('', P.tag({ verified = true }))
    T.eq('', P.tag({}))
    T.eq('', P.tag(nil))
end)

case('list rows carry verified for the /where tag', function()
    local src = { homestead = { plots = { h1 = { id = 'h1', center = { x = 0, y = 0, z = 0 }, verified = false } } } }
    local rows = P.list(P.gather(src), { x = 0, y = 0, z = 0 })
    T.eq(false, rows[1].verified)
end)

case('gather labels a camp with its name, else "Outlaw camp"; unverified tag survives', function()
    local src = { zones = { camps = {
        named = { center = { x = 0, y = 0, z = 0 }, name = 'Hill Haven camp', region = 'scarlett_meadows', verified = false },
        unnamed = { center = { x = 10, y = 0, z = 0 }, region = 'heartlands', verified = false },
    } } }
    local places = P.gather(src)
    local byId = {}
    for _, p in ipairs(places) do byId[p.id] = p end
    T.eq('Hill Haven camp', byId.named.label)
    T.eq('Outlaw camp', byId.unnamed.label)
    T.eq(' (unverified)', P.tag(byId.named))
    T.eq(' (unverified)', P.tag(byId.unnamed))
end)

case('world-04 M: line() keeps the player label byte-identical; showIds gives "label [id]"', function()
    local pl = { id = 'heartlands_02', label = 'Cotorra Bend claim', verified = false }
    T.eq('Cotorra Bend claim (unverified) (heartlands_02)', P.line(pl, false))
    T.eq('Cotorra Bend claim (unverified) (heartlands_02)', P.line(pl, nil))
    T.eq('Cotorra Bend claim (unverified) [heartlands_02]', P.line(pl, true))
    T.eq('Cotorra Bend claim [heartlands_02]', P.line({ id = 'heartlands_02', label = 'Cotorra Bend claim' }, true))
    T.eq('', P.idTag(pl, false))
    T.eq(' [heartlands_02]', P.idTag(pl, true))
    T.eq('', P.idTag(nil, true))
end)

T.finish()
