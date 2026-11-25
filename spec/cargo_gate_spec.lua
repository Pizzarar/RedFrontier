-- Run from repo root: `lua spec/cargo_gate_spec.lua` (or via tools/run-specs.py).
-- R8 (roads-02): the wagon-tier rep-unlock gate. Covers the pure FhCargoRules.wagonTierGate/unlockForTier and loads
-- the real fh_cargo server/main.lua under stubbed natives/exports to drive exports.fh_cargo:spawnWagon with a stubbed
-- fh_progression: allowed (t2 + t3) / tier_too_low / not started / throws / t1 bypass / unknown_unlock, plus the
-- post-yield character re-check and a drift check that the UNLOCKS ids resolve in the real fh_progression config.
-- Not a substitute for a live boot: exports are captured in-process, the wheel tick thread is not run.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local case = T.it
local CARGO = here .. '../server/resources/[fh]/fh_cargo/'
local R = dofile(CARGO .. 'shared/cargo_rules.lua') -- GetCurrentResourceName unset: returns M

local COORDS = { x = 0, y = 0, z = 0, h = 0 }

---Boot a fresh copy of server/main.lua (plus its shared rules + config) in one env. opts configures the stubbed
---fh_progression canUnlock: `ok`/`reason` (returned), `nilReturn` (returns nil, like a not-started resource),
---`throw` (raises), `changeCharOnUnlock`/`dropOnUnlock` (the player's character changes / goes nil while canUnlock
---runs, to exercise the post-yield re-check). Returns { exported, canUnlock, spawns, char }.
local function newEnv(opts)
    opts = opts or {}
    local B = { exported = {}, canUnlock = {}, spawns = {}, char = { cid = 'CID1' } }
    local exportsT = setmetatable({
        ['rsg-core'] = { GetCoreObject = function() return { Functions = {
            GetPlayer = function(src) if src ~= 7 then return nil end local c = B.char.cid return c and { PlayerData = { citizenid = c } } or nil end,
        }, Shared = { Items = {} } } end },
        fh_core = {
            requestSpawn = function(_, spec)
                B.spawns[#B.spawns + 1] = spec
                return 1
            end,
            despawn = function() end,
            registerContainer = function() return true end,
        },
        fh_progression = {
            canUnlock = function(_, src, id)
                B.canUnlock[#B.canUnlock + 1] = { src = src, id = id }
                if opts.changeCharOnUnlock then B.char.cid = opts.changeCharOnUnlock end
                if opts.dropOnUnlock then B.char.cid = nil end
                if opts.throw then error('boom') end
                if opts.nilReturn then return nil end
                return opts.ok, opts.reason
            end,
        },
    }, { __call = function(_, name, fn) B.exported[name] = fn end })
    local env = setmetatable({
        exports = exportsT,
        lib = { addCommand = function() end },
        GetCurrentResourceName = function() return 'fh_cargo' end,
        RegisterNetEvent = function() end,
        AddEventHandler = function() end,
        CreateThread = function() end,
        Wait = function() end,
        TriggerEvent = function() end,
        TriggerClientEvent = function() end,
        GetPlayers = function() return {} end,
        GetConvar = function() return 'true' end,
        GetGameTimer = function() return 0 end,
    }, { __index = _G })
    env._G = env
    for _, p in ipairs({ CARGO .. 'shared/cargo_rules.lua', CARGO .. 'config.lua', CARGO .. 'server/main.lua' }) do
        local fh = assert(io.open(p, 'rb')); local src = fh:read('a'); fh:close()
        assert(load(src, '@' .. p, 't', env))()
    end
    return B
end

case('pure: unlockForTier maps t2/t3 to their unlocks; t1 has none', function()
    T.eq('wagon_t2', R.unlockForTier('t2'))
    T.eq('wagon_t3', R.unlockForTier('t3'))
    T.eq(nil, R.unlockForTier('t1'))
    T.eq(nil, R.unlockForTier('nope'))
end)

case('pure: wagonTierGate allows and surfaces the returned reason', function()
    assert(R.wagonTierGate('t2', true, true, nil) == true)
    local ok, why = R.wagonTierGate('t2', true, false, 'tier_too_low')
    assert(ok == false and why == 'tier_too_low')
    ok, why = R.wagonTierGate('t3', true, false, 'unknown_unlock')
    assert(ok == false and why == 'unknown_unlock')
end)

case('pure: wagonTierGate fails closed on a throw, a not-started export, or no reason', function()
    local ok, why = R.wagonTierGate('t2', false, 'boom', nil) -- threw
    assert(ok == false and why == 'fh_locked')
    ok, why = R.wagonTierGate('t2', true, nil, nil)           -- not started: returns nil
    assert(ok == false and why == 'fh_locked')
    ok, why = R.wagonTierGate('t2', true, false, nil)         -- false with no reason
    assert(ok == false and why == 'fh_locked')
    ok, why = R.wagonTierGate('t2', true, false, '')          -- false with empty reason
    assert(ok == false and why == 'fh_locked')
end)

case('pure: t1 bypasses the gate even when the call would throw or refuse', function()
    assert(R.wagonTierGate('t1', false, 'boom', nil) == true)
    assert(R.wagonTierGate('t1', true, false, 'tier_too_low') == true)
end)

case('spawnWagon: t2 allowed when canUnlock(wagon_t2) is true', function()
    local B = newEnv({ ok = true })
    local id, err = B.exported.spawnWagon(7, 't2', COORDS)
    assert(id == 'CID1:t2', tostring(id))
    T.eq(1, #B.canUnlock); T.eq('wagon_t2', B.canUnlock[1].id); T.eq(7, B.canUnlock[1].src)
    T.eq(1, #B.spawns); T.eq('wagon', B.spawns[1].kind); T.eq('CID1:t2', B.spawns[1].owner.id)
end)

case('spawnWagon: t3 allowed when canUnlock(wagon_t3) is true', function()
    local B = newEnv({ ok = true })
    local id, err = B.exported.spawnWagon(7, 't3', COORDS)
    assert(id == 'CID1:t3', tostring(id))
    T.eq(1, #B.canUnlock); T.eq('wagon_t3', B.canUnlock[1].id); T.eq(7, B.canUnlock[1].src)
    T.eq(1, #B.spawns); T.eq('CID1:t3', B.spawns[1].owner.id)
end)

case('spawnWagon: t2 refused with the returned reason (tier_too_low)', function()
    local B = newEnv({ ok = false, reason = 'tier_too_low' })
    local id, err = B.exported.spawnWagon(7, 't2', COORDS)
    assert(id == nil and err == 'tier_too_low', tostring(err))
    T.eq(1, #B.canUnlock); T.eq(0, #B.spawns)
end)

case('spawnWagon: t2 refused fh_locked when fh_progression is not started (export returns nil)', function()
    local B = newEnv({ nilReturn = true })
    local id, err = B.exported.spawnWagon(7, 't2', COORDS)
    assert(id == nil and err == 'fh_locked', tostring(err))
    T.eq(1, #B.canUnlock); T.eq(0, #B.spawns)
end)

case('spawnWagon: t2 refused fh_locked when canUnlock throws', function()
    local B = newEnv({ throw = true })
    local id, err = B.exported.spawnWagon(7, 't2', COORDS)
    assert(id == nil and err == 'fh_locked', tostring(err))
    T.eq(1, #B.canUnlock); T.eq(0, #B.spawns)
end)

case('spawnWagon: t1 bypasses the gate even when fh_progression would throw', function()
    local B = newEnv({ throw = true })
    local id, err = B.exported.spawnWagon(7, 't1', COORDS)
    assert(id == 'CID1:t1', tostring(id))
    T.eq(0, #B.canUnlock, 't1 never calls canUnlock')
    T.eq(1, #B.spawns)
end)

case('spawnWagon: a returned unknown_unlock is surfaced (id drift / missing config fails closed)', function()
    local B = newEnv({ ok = false, reason = 'unknown_unlock' })
    local id, err = B.exported.spawnWagon(7, 't3', COORDS)
    assert(id == nil and err == 'unknown_unlock', tostring(err))
    T.eq(1, #B.canUnlock); T.eq('wagon_t3', B.canUnlock[1].id); T.eq(0, #B.spawns)
end)

case('spawnWagon: character changes or leaves during canUnlock -> fh_no_character, nothing spawned', function()
    local B = newEnv({ ok = true, changeCharOnUnlock = 'CID2' })
    local id, err = B.exported.spawnWagon(7, 't2', COORDS)
    assert(id == nil and err == 'fh_no_character', tostring(err))
    T.eq(1, #B.canUnlock); T.eq(0, #B.spawns)

    local B2 = newEnv({ ok = true, dropOnUnlock = true })
    local id2, err2 = B2.exported.spawnWagon(7, 't2', COORDS)
    assert(id2 == nil and err2 == 'fh_no_character', tostring(err2))
    T.eq(1, #B2.canUnlock); T.eq(0, #B2.spawns)
end)

case('UNLOCKS ids resolve in the real fh_progression config (catches id drift)', function()
    assert(loadfile(here .. '../server/resources/[fh]/fh_progression/config.lua'))()
    local cfg = FhProgressionConfig
    for _, tierKey in ipairs({ 't2', 't3' }) do
        local id = R.unlockForTier(tierKey)
        local u = cfg.unlocks[id]
        assert(u, ('%s unlock %s missing from fh_progression'):format(tierKey, id))
        assert(cfg.tiers[u.region_id], id .. ' region not configured')
        T.eq(R.TIERS[tierKey].tier, u.min_tier, tierKey .. ' min_tier matches the wagon tier number')
    end
end)

T.finish()
