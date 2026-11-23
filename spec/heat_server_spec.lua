-- Stubbed-server spec (idea-669 LOW1): loads fh_heat's real server/main.lua with a fake MySQL, rsg-core and
-- fh_economy, and drives exports.fh_heat:payoff end to end. Focus: the awaited heat write (saveAwait) counts as
-- persisted only on a truthy MySQL.query.await result, so a `false` / nil result refunds instead of keeping the money.
-- Not a substitute for a live boot: exports are captured in-process, MySQL is a fake, roadblocks.lua is not loaded.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local R = here .. '../server/resources/[fh]/'

local rows, exported, charges, pays = {}, {}, {}, {}
local db = { result = { affectedRows = 1 }, throws = false }
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
        if db.throws then error('db down') end
        if db.result then rows[v[1] .. '|' .. v[2]] = v[3] end -- a falsy result means the write did not land
        return db.result
    end,
}, { __call = function(_, _, v) rows[v[1] .. '|' .. v[2]] = v[3] end }) } -- fire-and-forget save()

local exportsT = setmetatable({
    ['rsg-core'] = { GetPlayer = function(_, src) return src == 1 and { PlayerData = { citizenid = 'CID1' } } or nil end },
    fh_economy = {
        charge = function(_, src, amount) charges[#charges + 1] = amount return true, nil, #charges end,
        pay = function(_, src, amount) pays[#pays + 1] = amount return true end,
    },
}, { __call = function(_, name, fn) exported[name] = fn end })

local env = setmetatable({
    exports = exportsT, MySQL = MySQL, GetCurrentResourceName = function() return 'fh_heat' end,
    GetResourceState = function() return 'started' end,
    GetPlayerPed = function() return 0 end, GetPlayers = function() return {} end, GetGameTimer = function() return 0 end,
    TriggerEvent = function() end, RegisterCommand = function() end, AddEventHandler = function() end,
    CreateThread = function() end, Wait = function() end,
    print = function() end,
}, { __index = _G })
env._G = env
for _, p in ipairs({ R .. 'fh_core/shared/regions.lua', R .. 'fh_heat/config.lua', R .. 'fh_heat/shared/heat_rules.lua',
    R .. 'fh_heat/server/main.lua' }) do
    local fh = assert(io.open(p, 'rb')); local src = fh:read('a'); fh:close()
    assert(load(src, '@' .. p, 't', env))()
end
local payoff, get = exported.payoff, exported.get

local function reset(heat, result)
    -- set() goes through the fire-and-forget path, so it lands regardless of db.result
    charges, pays = {}, {}
    db.result, db.throws = { affectedRows = 1 }, false
    assert(exported.set(1, 'outlaws', heat))
    db.result = result
end

T.describe('fh_heat.payoff awaited write (stubbed server)', function()
    T.it('truthy query result -> persisted: heat cleared, one charge, no refund', function()
        reset(40, { affectedRows = 1 })
        local ok, a, b = payoff(1, 'outlaws')
        assert(ok == true and a == 40 and b == 160, tostring(a))
        T.eq(0, get(1, 'outlaws')); T.eq(0, rows['CID1|outlaws'])
        T.same({ 160 }, charges); T.same({}, pays)
    end)
    T.it('query.await returns false -> not persisted: refunded, heat unchanged in memory and DB', function()
        reset(40, false)
        local ok, err, cost = payoff(1, 'outlaws')
        T.eq(false, ok); T.eq('fh_payoff_refunded', err); T.eq(160, cost)
        T.eq(40, get(1, 'outlaws'), 'in-memory change rolled back'); T.eq(40, rows['CID1|outlaws'])
        T.same({ 160 }, charges); T.same({ 160 }, pays, 'exact amount refunded')
    end)
    T.it('query.await returns nil -> not persisted: refunded', function()
        reset(40, nil)
        local ok, err = payoff(1, 'outlaws')
        T.eq(false, ok); T.eq('fh_payoff_refunded', err)
        T.eq(40, get(1, 'outlaws')); T.same({ 160 }, pays)
    end)
    T.it('query.await throws -> not persisted: refunded', function()
        reset(40, { affectedRows = 1 }); db.throws = true
        local ok, err = payoff(1, 'outlaws')
        T.eq(false, ok); T.eq('fh_payoff_refunded', err)
        T.eq(40, get(1, 'outlaws')); T.same({ 160 }, pays)
    end)
end)

T.finish()
