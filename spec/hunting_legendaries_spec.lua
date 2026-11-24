-- Run from repo root: `lua spec/hunting_legendaries_spec.lua` (or via tools/run-specs.py).
-- hunting-02 B1: legendary data per region (data/legendaries/<region_id>.lua, one per FhRegions id), the loader
-- (shared/legendaries.lua), chains keyed (cid, chain_id), the FhRegions.isEnabled gate, the derived pelt/trophy rows and
-- the additive event payloads. The bear's own behaviour is pinned by spec/hunting_chain_spec.lua.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local describe, it, eq, same = T.describe, T.it, T.eq, T.same
local base = here .. '../server/resources/[fh]/fh_hunting/'
local cfg = dofile(base .. 'config.lua')
FhHuntingWagon = dofile(base .. 'shared/wagon.lua')
local L = dofile(base .. 'shared/legendaries.lua')
local Chain = dofile(base .. 'shared/chain.lua')
local A = dofile(base .. 'shared/animals.lua')
local Tr = dofile(base .. 'shared/trophies.lua')
local regions = require('regions') -- the same instance the loader's gate reads

local SRC, CID = 7, 'CID123'
local ENABLED, DISABLED = 'great_plains', 'bluewater_marsh'

-- A valid raw entry (as a data file returns it), placed around (x0, y0).
local function raw(id, x0, y0, over)
    local e = {
        id = id, label = 'Test ' .. id, species_model = 'a_c_wolf', outfit = 0, scale = 1.2,
        pelt = { item = 'pelt_' .. id, label = 'Test Pelt', value = 50, weight = 20000, image = 'perfect_pelt.png' },
        trophy = { item = 'trophy_' .. id, label = 'Test Trophy', comfort = 25 },
        rumour = { coords = { x = x0, y = y0, z = 10.0 }, price = 30, label = 'Ask about it' },
        markers = {
            [2] = { label = 'Prints', coords = { x = x0 + 50, y = y0, z = 10.0 } },
            [3] = { label = 'Remains', coords = { x = x0 + 100, y = y0, z = 10.0 } },
        },
        spawn = { coords = { x = x0 + 150, y = y0, z = 10.0 } },
    }
    for k, v in pairs(over or {}) do e[k] = v end
    return e
end

-- A registry with the real bear (heartlands) plus test entries { [region_id] = raw }.
local function registry(extra)
    local reg = L.build(extra or {}, L.regionIds())
    local bear = L.byId.legendary_bear -- the real entry, the same table the default registry holds
    table.insert(reg.list, 1, bear)
    reg.byId.legendary_bear, reg.byRegion.heartlands = bear, bear
    return reg
end

-- Fake deps; the store is keyed (cid, chain_id) like fh_hunting_chains.
local function fake(reg, store)
    local D = { store = store or {}, charges = {}, spawns = {}, despawns = {}, events = {}, loads = 0,
        chargeResult = true, spawnResult = 100 }
    local function key(cid, id) return cid .. '|' .. id end
    D.deps = {
        load = function(cid, id) D.loads = D.loads + 1; return D.store[key(cid, id)] end,
        save = function(cid, s) D.store[key(cid, s.chain_id)] = s; return true end,
        charge = function(src, cid, amount, reason, region)
            D.charges[#D.charges + 1] = { src = src, cid = cid, amount = amount, reason = reason, region = region }
            if D.onCharge then D.onCharge() end
            return D.chargeResult
        end,
        spawn = function(cid, entry) D.spawns[#D.spawns + 1] = { cid = cid, entry = entry }; return D.spawnResult end,
        despawn = function(id) D.despawns[#D.despawns + 1] = id end,
        emit = function(name, payload) D.events[#D.events + 1] = { name = name, payload = payload } end,
    }
    D.chain = Chain.new({ cfg = cfg, legendaries = reg, deps = D.deps })
    return D
end

-- Run f with a region's enabled flag set, restoring it afterwards.
local function withEnabled(rid, on, f)
    local before = regions.regions[rid].enabled
    regions.regions[rid].enabled = on
    local ok, err = pcall(f)
    regions.regions[rid].enabled = before
    if not ok then error(err, 0) end
end

local function walk(D, e)
    assert(D.chain.buyRumour(SRC, CID, e.rumour.coords, e.id))
    assert(D.chain.inspect(CID, e.markers[2].id, e.markers[2].coords, e.id))
    return D.chain.inspect(CID, e.markers[3].id, e.markers[3].coords, e.id)
end

describe('hunting legendaries: data files', function()
    it('every FhRegions id has data/legendaries/<id>.lua (15)', function()
        local n = 0
        for id in pairs(regions.regions) do
            local f = io.open(base .. 'data/legendaries/' .. id .. '.lua', 'r')
            assert(f, 'missing data/legendaries/' .. id .. '.lua')
            f:close()
            n = n + 1
        end
        eq(15, n)
        eq(15, #L.regionIds())
    end)
    it('the files load cleanly: heartlands is the only entry, the 14 stubs are ignored', function()
        same({}, L.warnings)
        eq(1, #L.list)
        eq('legendary_bear', L.list[1].id)
        for _, rid in ipairs(L.regionIds()) do
            if rid ~= 'heartlands' then eq(nil, L.byRegion[rid], rid) end
        end
    end)
    it('heartlands is the Legendary Bear with the H4 values unchanged (moved from config.LegendaryBear)', function()
        local b = L.byRegion.heartlands
        eq('legendary_bear', b.id); eq('legendary_bear', b.chain_id); eq('heartlands', b.region_id)
        eq('a_c_bear_01', b.species_model); eq(25, b.rumour.price)
        same(cfg.Trapper.coords, b.rumour.coords) -- clue 1 stays at the trapper
        same({ id = 'track', label = 'Bear tracks', coords = { x = -260.0, y = 800.0, z = 116.0 }, radius = 3.0 },
            b.markers[2])
        same({ id = 'carcass', label = 'Mauled carcass', coords = { x = -215.0, y = 812.0, z = 115.0 }, radius = 3.0 },
            b.markers[3])
        same({ x = -170.0, y = 820.0, z = 114.0, heading = 0.0 }, b.spawn.coords)
        eq(nil, cfg.LegendaryBear)
        eq(4.0, cfg.LegendaryRumourRange)
    end)
    it('every legendary uses a species with a plain animal row and an id no plain animal uses', function()
        same({}, A.warnings)
        for _, e in ipairs(L.list) do
            assert(A.byModel[e.species_model], e.id .. ': no plain row for ' .. e.species_model)
            eq(A.byLegendary[e.id], A.byKey[e.id], e.id)
        end
    end)
end)

describe('hunting legendaries: loader ignores unknown, stub and invalid entries', function()
    it('only FhRegions ids are read; a file for an unknown region is never loaded', function()
        local asked = {}
        local raw2, warnings = L.readAll(function(path)
            asked[#asked + 1] = path
            if path == L.DIR .. 'atlantis.lua' then return 'return { id = "x" }' end
            return 'return nil'
        end, L.regionIds())
        eq(15, #asked)
        for _, p in ipairs(asked) do assert(p ~= L.DIR .. 'atlantis.lua', p) end
        same({}, raw2); same({}, warnings)
        local reg = L.build({ atlantis = raw('ghost', 0, 0) }, L.regionIds())
        eq(0, #reg.list); eq(nil, reg:get('ghost'))
    end)
    it('a data file runs with no globals; a throw or a syntax error is a warning, not a crash', function()
        local ok, res = L.runChunk('return print', 'x.lua')
        eq(true, ok); eq(nil, res)
        local raw2, warnings = L.readAll(function(path)
            if path == L.DIR .. 'heartlands.lua' then return 'error("boom")' end
            if path == L.DIR .. 'bayou_nwa.lua' then return 'return {' end
            return nil
        end, L.regionIds())
        same({}, raw2)
        eq(15, #warnings) -- 13 missing + 2 broken
    end)
    it('invalid entries are skipped with a warning', function()
        local bad = {
            bayou_nwa = raw('a1', 0, 0, { pelt = { item = 'pelt_other', label = 'x', value = 1, weight = 1, image = 'i' } }),
            big_valley = raw('a2', 0, 0, { markers = { [2] = { label = 'x', coords = { x = 0, y = 0, z = 0 } } } }),
            cholla_springs = raw('Bad Id', 0, 0),
            great_plains = raw('a4', 0, 0, { spawn = { coords = { x = 0 / 0, y = 0, z = 0 } } }),
            rio_bravo = raw('a5', 0, 0, { rumour = { coords = { x = 0, y = 0, z = 0 }, price = -1, label = 'x' } }),
            tall_trees = 'not a table',
        }
        local reg = L.build(bad, L.regionIds())
        eq(0, #reg.list)
        eq(6, #reg.warnings)
    end)
    it('a duplicate id is skipped', function()
        local reg = L.build({ bayou_nwa = raw('dup', 0, 0), big_valley = raw('dup', 500, 0) }, L.regionIds())
        eq(1, #reg.list); eq('bayou_nwa', reg:get('dup').region_id); eq(1, #reg.warnings)
    end)
    it('the chain refuses unknown ids and stub regions without touching state', function()
        local D = fake(registry())
        local at = { x = 0, y = 0, z = 0 }
        for _, id in ipairs({ 'nope', 'bayou_nwa', 42 }) do
            eq('fh_chain_unknown', select(2, D.chain.buyRumour(SRC, CID, at, id)))
            eq('fh_chain_unknown', select(2, D.chain.inspect(CID, 'track', at, id)))
            eq('fh_chain_unknown', select(2, D.chain.onAdopted(CID, id)))
            eq('fh_chain_unknown', select(2, D.chain.onSpawnFailed(CID, 1, id)))
            eq('fh_chain_unknown', select(2, D.chain.onSkinned(CID, id)))
            eq(nil, D.chain.state(CID, id))
        end
        eq(0, D.loads); eq(0, #D.charges); eq(0, #D.events)
    end)
    it('animals.get: a legendary id selects that row, true is the bear, unknown ids give nil', function()
        eq('pelt_legendary_bear', A.get('a_c_bear_01', 'legendary_bear').pelt)
        eq('pelt_legendary_bear', A.get(A.joaat('a_c_bear_01'), 'legendary_bear').pelt)
        eq('pelt_legendary_bear', A.get('a_c_bear_01', true).pelt)
        eq('pelt_bear', A.get('a_c_bear_01', false).pelt)
        eq(nil, A.get('a_c_bear_01', 'nope'))
        eq(nil, A.get('a_c_bear_01', 'bear')) -- a plain key is not a legendary
    end)
end)

describe('hunting legendaries: derived item and trophy rows', function()
    it('the bear rows are the H4 ones', function()
        local r = A.byKey.legendary_bear
        same({ 'legendary_bear', 'Legendary Bear', 'a_c_bear_01', 'pelt_legendary_bear', 'cargo', 60, 30000,
            'legendary_bear_pelt.png', true, 3, 'trophy_legendary_bear' },
            { r.key, r.label, r.model, r.pelt, r.size_class, r.value, r.weight, r.image, r.legendary, r.fixedStars,
                r.trophy })
        local defs = A.itemDefs()
        same({ label = 'Legendary Bear Pelt', weight = 30000, size_class = 'cargo', stackable = false, value_base = 60,
            illicit = false, image = 'legendary_bear_pelt.png', useable = false,
            description = 'A pelt from a legendary hunt.' }, defs.pelt_legendary_bear)
        same({ label = 'Legendary Bear Trophy', weight = 4000, size_class = 'bulky', stackable = false, value_base = 0,
            illicit = false, image = 'legendary_bear_pelt.png', useable = false,
            description = 'A keepsake from the legendary bear hunt.' }, defs.trophy_legendary_bear)
    end)
    it('a new entry derives a 3-star cargo pelt row and a bulky trophy', function()
        local e = L.validate(raw('test_wolf', 0, 0), ENABLED)
        local r = A.legendaryRow(e)
        eq('test_wolf', r.key); eq('pelt_test_wolf', r.pelt); eq('cargo', r.size_class); eq(3, r.fixedStars)
        eq(true, r.legendary); eq('trophy_test_wolf', r.trophy); eq(ENABLED, r.region_id)
    end)
    it('trophy comfort comes from the data, one per legendary', function()
        local want = {}
        for _, e in ipairs(L.list) do want[e.trophy.item] = e.trophy.comfort end
        same(want, Tr.comfort)
        eq(25, Tr.getComfort('trophy_legendary_bear'))
    end)
end)

describe('hunting legendaries: two chains at once', function()
    local reg = registry({ [ENABLED] = raw('test_wolf', 1000, 1000) })
    local bear, wolf = reg:get('legendary_bear'), reg:get('test_wolf')

    it('interleaved chains keep separate state, spawns and payloads', function()
        local D = fake(reg)
        assert(D.chain.buyRumour(SRC, CID, bear.rumour.coords))      -- nil id = the bear
        assert(D.chain.buyRumour(SRC, CID, wolf.rumour.coords, 'test_wolf'))
        assert(D.chain.inspect(CID, 'track', bear.markers[2].coords))
        assert(D.chain.inspect(CID, 'track', wolf.markers[2].coords, 'test_wolf'))
        local ok, res = D.chain.inspect(CID, 'carcass', wolf.markers[3].coords, 'test_wolf')
        assert(ok, tostring(res)); eq(Chain.STEP_SPAWNED, res.step)
        eq(1, #D.spawns); eq(wolf, D.spawns[1].entry)
        eq(Chain.STEP_CARCASS, D.chain.state(CID).step) -- the bear did not move
        eq(Chain.STEP_SPAWNED, D.chain.state(CID, 'test_wolf').step)
        -- a marker of one chain is not a marker of the other: the wolf's carcass spot is too far for the bear
        eq('fh_chain_too_far', select(2, D.chain.inspect(CID, 'carcass', wolf.markers[3].coords)))
        same({ { src = SRC, cid = CID, amount = 25, reason = 'hunting:rumour', region = 'heartlands' },
            { src = SRC, cid = CID, amount = 30, reason = 'hunting:rumour', region = ENABLED } }, D.charges)
        same({ citizenid = CID, chain_id = 'test_wolf', region_id = ENABLED, legendary = 'test_wolf', step = 3 },
            D.events[5].payload)
        same({ citizenid = CID, chain_id = 'legendary_bear', region_id = 'heartlands', legendary = 'legendary_bear',
            step = 2 }, D.events[3].payload)
    end)
    it('adoption and the skin complete only their own chain', function()
        local D = fake(reg)
        walk(D, wolf)
        assert(D.chain.buyRumour(SRC, CID, bear.rumour.coords))
        eq('fh_chain_no_spawn', select(2, D.chain.onAdopted(CID))) -- the bear has no spawn
        assert(D.chain.onAdopted(CID, 'test_wolf'))
        eq('fh_chain_not_spawned', select(2, D.chain.onSkinned(CID)))
        assert(D.chain.onSkinned(CID, 'test_wolf'))
        eq(true, D.chain.state(CID, 'test_wolf').completed)
        eq(Chain.STEP_TRACK, D.chain.state(CID).step); eq(false, D.chain.state(CID).completed)
        same({ 100 }, D.despawns)
        local last = D.events[#D.events]
        eq('fh:hunting:chain_complete', last.name)
        same({ citizenid = CID, chain_id = 'test_wolf', region_id = ENABLED, legendary = 'test_wolf' }, last.payload)
    end)
    it('both chains persist under their own chain_id and resume after a restart', function()
        local store = {}
        local D = fake(reg, store)
        assert(D.chain.buyRumour(SRC, CID, bear.rumour.coords))
        walk(D, wolf)
        eq(Chain.STEP_TRACK, store[CID .. '|legendary_bear'].step)
        eq(Chain.STEP_SPAWNED, store[CID .. '|test_wolf'].step)
        local D2 = fake(reg, store)
        eq(Chain.STEP_TRACK, D2.chain.state(CID).step)
        eq(100, D2.chain.state(CID, 'test_wolf').spawn_request)
        same({ legendary_bear = { step = 2, spawned = false, completed = false },
            test_wolf = { step = 4, spawned = false, completed = false } }, D2.chain.activeStates(CID))
    end)
    it('the busy guard is per chain: another chain goes through during a charge yield, the same one does not', function()
        local D = fake(reg)
        local inner = {}
        D.onCharge = function()
            D.onCharge = nil
            inner.same = select(2, D.chain.buyRumour(SRC, CID, bear.rumour.coords))
            inner.other = D.chain.buyRumour(SRC, CID, wolf.rumour.coords, 'test_wolf')
        end
        assert(D.chain.buyRumour(SRC, CID, bear.rumour.coords))
        eq('fh_chain_busy', inner.same)
        eq(true, inner.other)
        eq(2, #D.charges)
    end)
end)

describe('hunting legendaries: the region gate', function()
    local reg = registry({ [DISABLED] = raw('test_marsh', 2000, 2000) })
    local e = reg:get('test_marsh')

    it('the test region is disabled today and its entry is not active', function()
        eq(false, regions.isEnabled(DISABLED))
        local ids = {}
        for _, a in ipairs(reg:active()) do ids[#ids + 1] = a.id end
        same({ 'legendary_bear' }, ids)
    end)
    it('a disabled region refuses all 3 clue steps and never spawns', function()
        local store = {}
        local D = fake(reg, store)
        eq('fh_chain_region_closed', select(2, D.chain.buyRumour(SRC, CID, e.rumour.coords, e.id)))
        -- a chain started before the region was disabled is frozen at whatever step it reached
        store[CID .. '|test_marsh'] = { chain_id = 'test_marsh', step = 2 }
        eq('fh_chain_region_closed', select(2, D.chain.inspect(CID, 'track', e.markers[2].coords, e.id)))
        store[CID .. '|test_marsh'] = { chain_id = 'test_marsh', step = 3 }
        local D2 = fake(reg, store)
        eq('fh_chain_region_closed', select(2, D2.chain.inspect(CID, 'carcass', e.markers[3].coords, e.id)))
        eq(0, #D.spawns + #D2.spawns); eq(0, #D.charges); eq(0, #D.events + #D2.events)
        eq(3, D2.chain.state(CID, e.id).step) -- not reset
        same({}, D2.chain.activeStates(CID).test_marsh or {})
    end)
    it('flipping enabled shows it and runs its chain with no code change', function()
        withEnabled(DISABLED, true, function()
            local ids = {}
            for _, a in ipairs(reg:active()) do ids[#ids + 1] = a.id end
            same({ 'legendary_bear', 'test_marsh' }, ids)
            local D = fake(reg)
            local ok, res = walk(D, e)
            assert(ok, tostring(res)); eq(1, #D.spawns); eq(e, D.spawns[1].entry)
            assert(D.chain.onAdopted(CID, e.id))
            eq(DISABLED, D.events[#D.events].payload.region_id)
        end)
        eq(false, regions.isEnabled(DISABLED))
    end)
    it('the real loader gate reads FhRegions live', function()
        eq(true, L.isEnabled('heartlands'))
        eq(false, L.isEnabled(DISABLED))
        eq(false, L.isEnabled('atlantis'))
        withEnabled(DISABLED, true, function() eq(true, L.isEnabled(DISABLED)) end)
    end)
end)

T.finish()
