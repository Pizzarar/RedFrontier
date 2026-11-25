-- Run from repo root: `lua spec/hunting_coats_spec.lua` (or via tools/run-specs.py).
-- Legendary coat grants (shared/coats.lua) with a fake fh_tailor.grant.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local describe, it, eq, same = T.describe, T.it, T.eq, T.same
local base = here .. '../server/resources/[fh]/fh_hunting/'
local Coats = dofile(base .. 'shared/coats.lua')

local Tl = dofile(here .. '../server/resources/[fh]/fh_tailor/shared/tailor_logic.lua')
local L = dofile(base .. 'shared/legendaries.lua')

local function world(w)
    w = w or {}
    local W = { calls = {}, logs = {}, available = true, results = {} }
    for k, v in pairs(w) do W[k] = v end
    W.coats = Coats.new({
        available = function() return W.available end,
        grant = function(cid, id, src)
            W.calls[#W.calls + 1] = { cid = cid, id = id, src = src }
            local r = W.results[id]
            if r == 'throw' then error('boom') end
            if r then return false, r end
            return true, 'granted'
        end,
        log = function(m) W.logs[#W.logs + 1] = m end,
    })
    return W
end

describe('coat ids', function()
    it('follow the convention and the source matches the tailor pattern', function()
        local m, f = Coats.ids('legendary_bear')
        eq(m, 'coat_legendary_bear_male'); eq(f, 'coat_legendary_bear_female')
        eq(Coats.source('legendary_bear'), 'hunting:bear')
        eq(Coats.source('legendary_bear'):match('^[%w_:%-%.]+$') ~= nil, true)
    end)
    it('reject invalid legendary ids', function()
        eq(Coats.ids(nil), nil); eq(Coats.ids('a b'), nil); eq(Coats.source(5), nil)
    end)
end)

describe('grantFor', function()
    it('completing grants both ids with the right source', function()
        local W = world()
        eq(W.coats.grantFor('CID1', 'legendary_bear'), 2)
        same(W.calls, {
            { cid = 'CID1', id = 'coat_legendary_bear_male', src = 'hunting:bear' },
            { cid = 'CID1', id = 'coat_legendary_bear_female', src = 'hunting:bear' } })
    end)
    it('wrong_sex is ignored silently', function()
        local W = world({ results = { coat_x_female = 'wrong_sex' } })
        eq(W.coats.grantFor('CID1', 'x'), 2); eq(#W.logs, 0)
    end)
    it('unknown_entry does not break and logs once per id', function()
        local W = world({ results = { coat_x_male = 'unknown_entry', coat_x_female = 'unknown_entry' } })
        eq(W.coats.grantFor('CID1', 'x'), 2); eq(#W.logs, 2)
        eq(W.coats.grantFor('CID2', 'x'), 2); eq(#W.logs, 2)
    end)
    it('a throwing grant is caught', function()
        local W = world({ results = { coat_x_male = 'throw' } })
        eq(W.coats.grantFor('CID1', 'x'), 2); eq(#W.calls, 2)
    end)
    it('fh_tailor missing is a silent no-op', function()
        local W = world({ available = false })
        eq(W.coats.grantFor('CID1', 'x'), 0); eq(#W.calls, 0); eq(#W.logs, 0)
    end)
end)

describe('real legendaries', function()
    it('every legendary source passes fh_tailor validSource and every coat id passes validId', function()
        eq(#L.list, 15)
        for _, e in ipairs(L.list) do
            local m, f = Coats.ids(e.id)
            eq(Tl.validSource(Coats.source(e.id)), true, e.id .. ' source ' .. tostring(Coats.source(e.id)))
            eq(Tl.validId(m), true, m); eq(Tl.validId(f), true, f)
        end
    end)
end)

describe('refusals are logged once per (id, code)', function()
    it('invalid_source / db_failed warn once each; wrong_sex stays silent', function()
        local W = world({ results = { coat_x_male = 'invalid_source', coat_x_female = 'wrong_sex' } })
        W.coats.grantFor('C1', 'x'); W.coats.grantFor('C2', 'x')
        eq(#W.logs, 1)
        W.results.coat_x_male = 'db_failed'
        W.coats.grantFor('C1', 'x'); W.coats.grantFor('C1', 'x')
        eq(#W.logs, 2)
    end)
end)

describe('server/main.lua wiring guard', function()
    it('has one PlayerLoaded handler, one coats setup and one of each top-level setup (no duplicated block)', function()
        local f = assert(io.open(base .. 'server/main.lua', 'rb')); local src = f:read('a'); f:close()
        local function count(pat) local n = 0; for _ in src:gmatch(pat) do n = n + 1 end return n end
        eq(count("RSGCore:Server:PlayerLoaded"), 1)
        eq(count("FhHuntingCoats%.new"), 1)
        eq(count("\nchain = FhHuntingChain%.new"), 1)
        eq(count("fh:hunting:pelt_skinned"), 1)
    end)
end)

describe('backfill', function()
    it('grants for the given completed ids only', function()
        local W = world()
        same(W.coats.backfill('CID1', { 'a', 'c' }), { 'a', 'c' }); eq(#W.calls, 4)
        eq(W.calls[1].id, 'coat_a_male'); eq(W.calls[3].id, 'coat_c_male')
    end)
    it('empty list, or fh_tailor missing: no calls; available() reflects it', function()
        local W = world()
        same(W.coats.backfill('CID1', {}), {}); eq(#W.calls, 0); eq(W.coats.available(), true)
        local W2 = world({ available = false })
        same(W2.coats.backfill('CID1', { 'a' }), {}); eq(#W2.calls, 0); eq(W2.coats.available(), false)
    end)
end)

describe('backfillFromQuery', function()
    it('a query failure (throw or non-table) logs citizenid + error and grants nothing', function()
        local W = world()
        same(W.coats.backfillFromQuery('CID9', function() error('db down') end, { a = true }), {})
        same(W.coats.backfillFromQuery('CID9', function() return nil end, { a = true }), {})
        eq(#W.calls, 0); eq(#W.logs, 2)
        assert(W.logs[1]:match('CID9') and W.logs[1]:match('db down'), W.logs[1])
    end)
    it('grants only known legendary ids from the rows', function()
        local W = world()
        same(W.coats.backfillFromQuery('C1', function() return { { chain_id = 'a' }, { chain_id = 'zz' } } end, { a = true }), { 'a' })
        eq(#W.logs, 0); eq(#W.calls, 2)
    end)
end)

T.finish()
