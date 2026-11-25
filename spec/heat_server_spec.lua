-- Stubbed-server spec (idea-669 LOW1, idea-864, idea-848): loads fh_heat's real server/main.lua and
-- server/roadblocks.lua with a fake MySQL, rsg-core, fh_core and fh_economy.
-- Covers: awaited heat write (saveAwait), citizenid-keyed credit refund across drops / character switches / credit
-- failure logging, and roadblock faction resolution (id / alias / kind / neutral log-once).
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local R = here .. '../server/resources/[fh]/'

local rows, exported, charges, credits, pays, logs, handlers, spawns = {}, {}, {}, {}, {}, {}, {}, {}
local db = { result = { affectedRows = 1 }, throws = false, beforeWrite = nil }
local economy = { state = 'started', creditOk = true, creditErr = nil, creditMode = nil, creditThrows = false }
local players = { [1] = 'CID1' }

local MySQL = { query = setmetatable({
    await = function(q, v)
        assert(q:find('fh_heat', 1, true), q)
        if q:find('^SELECT') then
            local out = {}
            for k, h in pairs(rows) do
                local cid, f = k:match('^(.-)|(.*)$')
                if cid == v[1] then out[#out + 1] = { faction = f, heat = h } end
            end
            return out
        end
        if db.beforeWrite then db.beforeWrite() end
        if db.throws then error('db down') end
        if db.result then rows[v[1] .. '|' .. v[2]] = v[3] end -- a falsy result means the write did not land
        return db.result
    end,
}, { __call = function(_, _, v) rows[v[1] .. '|' .. v[2]] = v[3] end }) } -- fire-and-forget save()

local function isOnline(cid)
    for _, c in pairs(players) do if c == cid then return true end end
    return false
end

local exportsT = setmetatable({
    ['rsg-core'] = { GetPlayer = function(_, src)
        local cid = players[src]
        return cid and { PlayerData = { citizenid = cid } } or nil
    end },
    fh_economy = {
        charge = function(_, src, amount) charges[#charges + 1] = amount return true, nil, #charges end,
        pay = function(_, src, amount) pays[#pays + 1] = amount return true end,
        credit = function(_, cid, amount, reason, region)
            if economy.creditThrows then error('credit boom') end
            local mode = economy.creditMode or (isOnline(cid) and 'paid' or 'pending')
            credits[#credits + 1] = { cid = cid, amount = amount, reason = reason, region = region, mode = mode }
            if not economy.creditOk then return false, economy.creditErr or 'ledger_failed' end
            return true, nil, mode
        end,
    },
    fh_core = {
        requestSpawn = function(_, spec)
            spawns[#spawns + 1] = spec
            return 'req_' .. #spawns
        end,
        despawn = function() end,
    },
}, { __call = function(_, name, fn) exported[name] = fn end })

local env = setmetatable({
    exports = exportsT, MySQL = MySQL, GetCurrentResourceName = function() return 'fh_heat' end,
    GetResourceState = function(name)
        if name == 'fh_economy' then return economy.state end
        if name == 'fh_homestead' then return 'missing' end
        return 'started'
    end,
    GetConvar = function(_, def) return def end,
    GetPlayerPed = function(src) return players[src] and 100 or 0 end,
    GetEntityCoords = function() return { x = -190.0, y = 800.0, z = 118.0 } end,
    GetPlayers = function()
        local out = {}
        for s in pairs(players) do out[#out + 1] = tostring(s) end
        return out
    end,
    GetGameTimer = function() return 10000 end,
    vector3 = function(x, y, z) return { x = x, y = y, z = z } end,
    vector4 = function(x, y, z, w) return { x = x, y = y, z = z, w = w } end,
    TriggerEvent = function() end, RegisterCommand = function() end,
    AddEventHandler = function(name, fn)
        handlers[name] = handlers[name] or {}
        handlers[name][#handlers[name] + 1] = fn
    end,
    CreateThread = function() end, Wait = function() end,
    print = function(msg) logs[#logs + 1] = tostring(msg) end,
}, { __index = _G })
env._G = env
for _, p in ipairs({
    R .. 'fh_core/shared/regions.lua', R .. 'fh_heat/config.lua',
    R .. 'fh_heat/shared/heat_rules.lua', R .. 'fh_heat/shared/roadblock_rules.lua',
    R .. 'fh_heat/server/main.lua', R .. 'fh_heat/server/roadblocks.lua',
}) do
    local fh = assert(io.open(p, 'rb')); local src = fh:read('a'); fh:close()
    assert(load(src, '@' .. p, 't', env))()
end
local payoff, get = exported.payoff, exported.get

local function fireEvent(name, payload, src)
    env.source = src
    for _, fn in ipairs(handlers[name] or {}) do fn(payload) end
    env.source = nil
end

local function reset(heat, result)
    -- set() goes through the fire-and-forget path, so it lands regardless of db.result
    charges, credits, pays, logs, spawns = {}, {}, {}, {}, {}
    players = { [1] = 'CID1' }
    db.result, db.throws, db.beforeWrite = { affectedRows = 1 }, false, nil
    economy.state, economy.creditOk, economy.creditErr, economy.creditMode, economy.creditThrows =
        'started', true, nil, nil, false
    assert(exported.set(1, 'outlaws', heat))
    db.result = result
    logs = {}
end

local function hasLog(pat)
    for _, l in ipairs(logs) do if l:find(pat) then return true end end
    return false
end

T.describe('fh_heat.payoff awaited write + credit refund (stubbed server)', function()
    T.it('truthy query result -> persisted: heat cleared, one charge, no refund', function()
        reset(40, { affectedRows = 1 })
        local ok, a, b = payoff(1, 'outlaws')
        assert(ok == true and a == 40 and b == 160, tostring(a))
        T.eq(0, get(1, 'outlaws')); T.eq(0, rows['CID1|outlaws'])
        T.same({ 160 }, charges); T.same({}, credits); T.same({}, pays)
    end)
    T.it('query.await returns false -> not persisted: credited to citizenid, heat unchanged', function()
        reset(40, false)
        local ok, err, cost = payoff(1, 'outlaws')
        T.eq(false, ok); T.eq('fh_payoff_refunded', err); T.eq(160, cost)
        T.eq(40, get(1, 'outlaws'), 'in-memory change rolled back'); T.eq(40, rows['CID1|outlaws'])
        T.same({ 160 }, charges); T.same({}, pays, 'never uses pay(src)')
        T.eq(1, #credits); T.eq('CID1', credits[1].cid); T.eq(160, credits[1].amount)
        T.eq('heat_bounty_refund', credits[1].reason); T.eq('paid', credits[1].mode)
    end)
    T.it('query.await returns nil -> not persisted: refunded via credit', function()
        reset(40, nil)
        local ok, err = payoff(1, 'outlaws')
        T.eq(false, ok); T.eq('fh_payoff_refunded', err)
        T.eq(40, get(1, 'outlaws')); T.eq(1, #credits); T.eq(160, credits[1].amount)
    end)
    T.it('query.await throws -> not persisted: refunded via credit', function()
        reset(40, { affectedRows = 1 }); db.throws = true
        local ok, err = payoff(1, 'outlaws')
        T.eq(false, ok); T.eq('fh_payoff_refunded', err)
        T.eq(40, get(1, 'outlaws')); T.eq(1, #credits); T.eq(160, credits[1].amount)
    end)
    T.it('player drops during payoff -> credit queued (pending) to original citizenid', function()
        reset(40, false)
        db.beforeWrite = function()
            players[1] = nil
            fireEvent('playerDropped', nil, 1)
        end
        local ok, err, cost = payoff(1, 'outlaws')
        T.eq(false, ok); T.eq('fh_payoff_refunded', err); T.eq(160, cost)
        T.same({}, pays, 'pay(src) must not be called')
        T.eq(1, #credits)
        T.eq('CID1', credits[1].cid); T.eq(160, credits[1].amount); T.eq('pending', credits[1].mode)
        assert(hasLog('refund queued %(pending%) cid=CID1'), 'pending refund logged')
    end)
    T.it('character switch during payoff -> original citizenid credited, not the new character', function()
        reset(40, false)
        db.beforeWrite = function()
            players[1] = 'CID2'
        end
        local ok, err, cost = payoff(1, 'outlaws')
        T.eq(false, ok); T.eq('fh_payoff_refunded', err); T.eq(160, cost)
        T.same({}, pays, 'pay(src) must not be called')
        T.eq(1, #credits)
        T.eq('CID1', credits[1].cid, 'original citizenid credited, not CID2')
        T.eq(160, credits[1].amount); T.eq('pending', credits[1].mode)
    end)
    T.it('credit failure (refused / throw / stopped) -> fh_payoff_refund_failed and logged loudly', function()
        reset(40, false); economy.creditOk = false; economy.creditErr = 'ledger_failed'
        local ok, err, cost = payoff(1, 'outlaws')
        T.eq(false, ok); T.eq('fh_payoff_refund_failed', err); T.eq(160, cost)
        assert(hasLog('ERROR payoff cid=CID1 faction=outlaws amount=160 charged=true: REFUND FAILED: ledger_failed'),
            'refused credit logged loudly')

        reset(40, false); economy.creditThrows = true
        ok, err = payoff(1, 'outlaws')
        T.eq(false, ok); T.eq('fh_payoff_refund_failed', err)
        assert(hasLog('ERROR payoff cid=CID1 faction=outlaws amount=160 charged=true: REFUND FAILED:.*credit boom'),
            'thrown credit logged loudly')

        reset(40, false)
        db.beforeWrite = function() economy.state = 'stopped' end
        ok, err = payoff(1, 'outlaws')
        T.eq(false, ok); T.eq('fh_payoff_refund_failed', err)
        assert(hasLog('ERROR payoff cid=CID1 faction=outlaws amount=160 charged=true: REFUND FAILED: fh_economy_unavailable'),
            'unavailable economy logged loudly')
    end)
end)

T.describe('fh_heat roadblocks faction resolution (stubbed server)', function()
    T.it('neutral faction (traders) -> no spawn, logged once, no throw', function()
        reset(0, { affectedRows = 1 })
        fireEvent('fh:heat:threshold', { src = 1, citizenid = 'CID1', faction = 'traders', old_level = 'watched', level = 'wanted', value = 55 })
        fireEvent('fh:heat:threshold', { src = 1, citizenid = 'CID1', faction = 'traders', old_level = 'watched', level = 'wanted', value = 55 })
        T.eq(0, #spawns)
        local hits = 0
        for _, l in ipairs(logs) do if l:find('roadblock: no ped config for faction traders') then hits = hits + 1 end end
        T.eq(1, hits, 'missing config logged exactly once')
    end)
    T.it('kind fallback (desert_gang outlaw) -> spawns roadblock peds using byKind.outlaw', function()
        reset(0, { affectedRows = 1 })
        fireEvent('fh:heat:threshold', { src = 1, citizenid = 'CID1', faction = 'desert_gang', old_level = 'watched', level = 'wanted', value = 55 })
        T.eq(4, #spawns)
        T.eq('g_m_m_unibanditos_01', spawns[1].model)
        T.eq('fh_heat:roadblock:desert_gang:1', spawns[1].tag)
    end)
    T.it('alias_of (rhodes_law -> lawmen) -> spawns roadblock peds using lawmen row', function()
        reset(0, { affectedRows = 1 })
        fireEvent('fh:heat:threshold', { src = 1, citizenid = 'CID1', faction = 'rhodes_law', old_level = 'watched', level = 'wanted', value = 55 })
        T.eq(4, #spawns)
        T.eq('s_m_m_valdeputy_01', spawns[1].model)
    end)
end)

T.finish()
