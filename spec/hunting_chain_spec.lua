-- Run from repo root: `lua spec/hunting_chain_spec.lua` (or via tools/run-specs.py).
-- The real legendary-bear chain (shared/chain.lua) with fake deps: order, no skip, idempotent repeats, relog
-- resume, one spawn per chain, completion only after the skin.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local describe, it, eq, same = T.describe, T.it, T.eq, T.same
local base = here .. '../server/resources/[fh]/fh_hunting/'
local cfg = dofile(base .. 'config.lua')
local Chain = dofile(base .. 'shared/chain.lua')

local SRC, CID = 7, 'CID123'
local atTrapper = cfg.Trapper.coords
local atTrack = cfg.LegendaryBear.markers[2].coords
local atCarcass = cfg.LegendaryBear.markers[3].coords
local far = { x = 10000, y = 10000, z = 0 }

-- A fake-dep harness. `store` is the simulated DB: [cid] = persisted state (shared across "restarts").
local function fake(store)
    local D = {
        store = store or {},
        charges = {}, spawns = {}, despawns = {}, events = {},
        chargeResult = true, spawnResult = 100, spawnCalls = 0,
    }
    D.deps = {
        load = function(cid) return D.store[cid] end,
        save = function(cid, s) D.store[cid] = s; return true end,
        charge = function(src, cid, amount, reason, region)
            D.charges[#D.charges + 1] = { src = src, cid = cid, amount = amount, reason = reason, region = region }
            return D.chargeResult
        end,
        spawn = function(cid, chainCfg)
            D.spawnCalls = D.spawnCalls + 1
            D.spawns[#D.spawns + 1] = { cid = cid, chainCfg = chainCfg }
            return D.spawnResult
        end,
        despawn = function(requestId) D.despawns[#D.despawns + 1] = requestId end,
        emit = function(name, payload) D.events[#D.events + 1] = { name = name, payload = payload } end,
    }
    D.chain = Chain.new({ cfg = cfg, deps = D.deps })
    return D
end

local function names(events)
    local out = {}
    for _, e in ipairs(events) do out[#out + 1] = e.name end
    return out
end

-- Walk clue 1 (rumour) and clue 2 (track). Returns the harness.
local function toClue3(D)
    assert(D.chain.buyRumour(SRC, CID, atTrapper))
    assert(D.chain.inspect(CID, 'track', atTrack))
    return D
end

describe('hunting chain: order and no skip', function()
    it('rumour must come first; inspecting a marker before it is refused', function()
        local D = fake()
        eq('fh_chain_wrong_marker', select(2, D.chain.inspect(CID, 'track', atTrack)))
        eq('fh_chain_wrong_marker', select(2, D.chain.inspect(CID, 'carcass', atCarcass)))
        eq(0, #D.events); eq(0, #D.charges)
    end)
    it('the carcass (clue 3) cannot be inspected before the track (clue 2)', function()
        local D = fake()
        assert(D.chain.buyRumour(SRC, CID, atTrapper))
        eq('fh_chain_wrong_marker', select(2, D.chain.inspect(CID, 'carcass', atCarcass)))
        eq(1, #D.events) -- only clue_found step 1
    end)
    it('a full walk advances 1 -> 2 -> 3 -> spawned with the right clue events', function()
        local D = fake()
        local ok, res = D.chain.buyRumour(SRC, CID, atTrapper)
        assert(ok); eq(Chain.STEP_TRACK, res.step)
        ok, res = D.chain.inspect(CID, 'track', atTrack)
        assert(ok); eq(Chain.STEP_CARCASS, res.step)
        ok, res = D.chain.inspect(CID, 'carcass', atCarcass)
        assert(ok); eq(Chain.STEP_SPAWNED, res.step)
        same({ 'fh:hunting:clue_found', 'fh:hunting:clue_found', 'fh:hunting:clue_found' }, names(D.events))
        eq(1, D.events[1].payload.step); eq(2, D.events[2].payload.step); eq(3, D.events[3].payload.step)
        eq(1, D.spawnCalls)
    end)
end)

describe('hunting chain: idempotent repeats', function()
    it('buying the rumour twice pays once and refuses the second', function()
        local D = fake()
        assert(D.chain.buyRumour(SRC, CID, atTrapper))
        eq('fh_chain_rumour_done', select(2, D.chain.buyRumour(SRC, CID, atTrapper)))
        eq(1, #D.charges); eq(1, #D.events)
    end)
    it('inspecting the same track twice refuses the second (step moved on)', function()
        local D = fake()
        assert(D.chain.buyRumour(SRC, CID, atTrapper))
        assert(D.chain.inspect(CID, 'track', atTrack))
        eq('fh_chain_wrong_marker', select(2, D.chain.inspect(CID, 'track', atTrack)))
        eq(2, #D.events)
    end)
    it('inspecting the carcass twice spawns once and refuses the second', function()
        local D = toClue3(fake())
        assert(D.chain.inspect(CID, 'carcass', atCarcass))
        eq(1, D.spawnCalls)
        eq('fh_chain_spawned', select(2, D.chain.inspect(CID, 'carcass', atCarcass)))
        eq(1, D.spawnCalls)
    end)
end)

describe('hunting chain: relog resume', function()
    it('a new chain object over the same store resumes at the right step', function()
        local store = {}
        toClue3(fake(store)) -- persist clue 1 and 2
        local D2 = fake(store) -- "restart": fresh chain, same store
        local ok, res = D2.chain.inspect(CID, 'carcass', atCarcass)
        assert(ok, tostring(res)); eq(Chain.STEP_SPAWNED, res.step)
        eq(1, D2.spawnCalls)
        eq(1, #D2.events) -- clue_found step 3 only (the earlier events are not replayed)
        eq(3, D2.events[1].payload.step)
    end)
    it('a completed chain stays complete across a restart', function()
        local store = {}
        local D = toClue3(fake(store))
        assert(D.chain.inspect(CID, 'carcass', atCarcass))
        assert(D.chain.onAdopted(CID))
        assert(D.chain.onSkinned(CID))
        local D2 = fake(store)
        eq('fh_chain_complete', select(2, D2.chain.buyRumour(SRC, CID, atTrapper)))
        eq('fh_chain_complete', select(2, D2.chain.inspect(CID, 'track', atTrack)))
    end)
end)

describe('hunting chain: one spawn per chain', function()
    it('the bear spawn is requested exactly once, from the final clue', function()
        local D = toClue3(fake())
        assert(D.chain.inspect(CID, 'carcass', atCarcass))
        eq(1, D.spawnCalls)
        eq(CID, D.spawns[1].cid)
        eq(cfg.LegendaryBear, D.spawns[1].chainCfg)
        eq(100, D.chain.state(CID).spawn_request) -- the spawn dep's requestId, persisted
    end)
    it('onAdopted before any spawn is refused, and fires legendary_spawned exactly once', function()
        local D = toClue3(fake())
        eq('fh_chain_no_spawn', select(2, D.chain.onAdopted(CID)))
        assert(D.chain.inspect(CID, 'carcass', atCarcass))
        local ok = D.chain.onAdopted(CID)
        assert(ok)
        eq(true, D.chain.state(CID).spawned)
        same({ 'fh:hunting:legendary_spawned' }, { D.events[#D.events].name })
        same({ citizenid = CID, chain_id = 'legendary_bear' }, D.events[#D.events].payload)
        -- re-adopt (fh_core re-request with a new netId): no second event
        assert(D.chain.onAdopted(CID))
        eq(4, #D.events)
    end)
end)

describe('hunting chain: spawn failure resets the chain', function()
    it('onSpawnFailed resets to the carcass clue so the spawn can be retried', function()
        local D = toClue3(fake())
        assert(D.chain.inspect(CID, 'carcass', atCarcass)) -- spawn_request = 100, step = 4
        assert(D.chain.onSpawnFailed(CID, 100))
        eq(Chain.STEP_CARCASS, D.chain.state(CID).step)
        eq(nil, D.chain.state(CID).spawn_request)
        local ok = D.chain.inspect(CID, 'carcass', atCarcass)
        assert(ok); eq(2, D.spawnCalls)
    end)
    it('onSpawnFailed with a mismatched requestId is refused', function()
        local D = toClue3(fake())
        assert(D.chain.inspect(CID, 'carcass', atCarcass)) -- spawn_request = 100
        eq('fh_chain_wrong_spawn', select(2, D.chain.onSpawnFailed(CID, 999)))
        eq(100, D.chain.state(CID).spawn_request)
    end)
    it('onSpawnFailed after adoption is a no-op (the bear is already live)', function()
        local D = toClue3(fake())
        assert(D.chain.inspect(CID, 'carcass', atCarcass))
        assert(D.chain.onAdopted(CID))
        eq('fh_chain_spawned', select(2, D.chain.onSpawnFailed(CID, 100)))
        eq(true, D.chain.state(CID).spawned)
        eq(Chain.STEP_SPAWNED, D.chain.state(CID).step)
    end)
end)

describe('hunting chain: completion only after the skin', function()
    it('onSkinned before the bear is spawned is refused', function()
        local D = toClue3(fake())
        assert(D.chain.inspect(CID, 'carcass', atCarcass))
        eq('fh_chain_not_spawned', select(2, D.chain.onSkinned(CID)))
    end)
    it('skinning the spawned bear completes the chain, emits once, and despawns the request', function()
        local D = toClue3(fake())
        assert(D.chain.inspect(CID, 'carcass', atCarcass))
        assert(D.chain.onAdopted(CID))
        local ok = D.chain.onSkinned(CID)
        assert(ok)
        eq(Chain.STEP_COMPLETE, D.chain.state(CID).step)
        eq(true, D.chain.state(CID).completed)
        same({ 'fh:hunting:chain_complete' }, { D.events[#D.events].name })
        same({ citizenid = CID, chain_id = 'legendary_bear' }, D.events[#D.events].payload)
        same({ 100 }, D.despawns)
        -- idempotent: a second completion does not re-emit
        assert(D.chain.onSkinned(CID))
        eq(5, #D.events)
    end)
end)

describe('hunting chain: range and failure validation', function()
    it('the rumour is refused from too far and never charged', function()
        local D = fake()
        eq('fh_chain_too_far', select(2, D.chain.buyRumour(SRC, CID, far)))
        eq(0, #D.charges); eq(0, #D.events)
        eq(Chain.STEP_RUMOUR, D.chain.state(CID).step)
    end)
    it('a marker is refused from too far', function()
        local D = fake()
        assert(D.chain.buyRumour(SRC, CID, atTrapper))
        eq('fh_chain_too_far', select(2, D.chain.inspect(CID, 'track', far)))
        eq(Chain.STEP_TRACK, D.chain.state(CID).step)
    end)
    it('a failed rumour payment leaves the step untouched', function()
        local D = fake()
        D.chargeResult = false
        eq('fh_chain_pay_failed', select(2, D.chain.buyRumour(SRC, CID, atTrapper)))
        eq(Chain.STEP_RUMOUR, D.chain.state(CID).step)
    end)
    it('a failed spawn leaves the carcass clue re-inspectable and spawns nothing', function()
        local D = toClue3(fake())
        D.spawnResult = nil
        eq('fh_chain_spawn_failed', select(2, D.chain.inspect(CID, 'carcass', atCarcass)))
        eq(nil, D.chain.state(CID).spawn_request)
        eq(Chain.STEP_CARCASS, D.chain.state(CID).step)
        -- a later successful request goes through
        D.spawnResult = 200
        local ok = D.chain.inspect(CID, 'carcass', atCarcass)
        assert(ok); eq(200, D.chain.state(CID).spawn_request)
    end)
    it('a garbage marker id is refused', function()
        local D = fake()
        assert(D.chain.buyRumour(SRC, CID, atTrapper))
        eq('fh_chain_bad_marker', select(2, D.chain.inspect(CID, 'nope', atTrack)))
        eq('fh_chain_bad_marker', select(2, D.chain.inspect(CID, 2, atTrack)))
    end)
    it('the rumour is charged with reason hunting:rumour', function()
        local D = fake()
        assert(D.chain.buyRumour(SRC, CID, atTrapper))
        same({ { src = SRC, cid = CID, amount = cfg.LegendaryBear.rumourPrice, reason = 'hunting:rumour',
            region = cfg.LegendaryBear.region_id } }, D.charges)
    end)
end)

describe('hunting chain: default and normalise', function()
    it('defaultState starts at the rumour and normalise tolerates junk', function()
        same({ chain_id = 'legendary_bear', step = 1, spawn_request = nil, spawned = false, completed = false },
            Chain.defaultState())
        local n = Chain.normalise({ step = 3, spawn_request = 0, spawned = 1, completed = 'yes' })
        eq(3, n.step); eq(nil, n.spawn_request); eq(false, n.spawned); eq(false, n.completed)
        local n2 = Chain.normalise(nil)
        eq(Chain.STEP_RUMOUR, n2.step)
    end)
    it('state() returns a copy, not the live table', function()
        local D = fake()
        local s = D.chain.state(CID)
        s.step = 99
        eq(Chain.STEP_RUMOUR, D.chain.state(CID).step)
    end)
end)

T.finish()
