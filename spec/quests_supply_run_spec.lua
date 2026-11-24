-- Run from repo root: `lua spec/quests_supply_run_spec.lua` (or via tools/run-specs.py).
-- quests-02 C1: supply_run job type. Advances on the existing fh:trade:sold event (fh_trade server/main.lua:144),
-- whose real payload is { src, region, post, item, amount, total }: the key is `region` (NOT region_id) and the
-- intake resolves src -> citizenid. Verdicts: the right post + right item + enough amount in one sale completes the
-- job; a wrong post / wrong item / short amount is ignored; a disabled region yields no supply_run offer.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local describe, it, eq, same = T.describe, T.it, T.eq, T.same
local shared = here .. '../server/resources/[fh]/fh_quests/shared/'
package.path = shared .. '?.lua;' .. package.path
local JT = dofile(shared .. 'jobtypes.lua')
local Jobs = require('jobs')
local E = require('engine')
local I = require('intake')
local B = require('board')
local regions = require('regions')

local T0 = 1795651200
local ME, OTHER = 'ABC123', 'XYZ999'
local REGION = 'heartlands'
local KEY = 'supply_valentine_post_trade_cloth'

local function events()
    local set = {}
    for _, name in ipairs(E.INTAKE) do set[name] = true end
    return set
end

local function find(key)
    for _, o in ipairs(JT.offers('supply_run', REGION)) do
        if o.key == key then return o end
    end
    error('no supply_run offer ' .. tostring(key))
end

-- Accept an offer the way api.lua does: snapshot -> def -> engine.start, progress.job = snapshot.
local function accepted(offer, cid)
    local snap = assert(Jobs.snapshot('supply_run', offer, REGION, true))
    local def = assert(Jobs.def(snap, { regions = regions.regions, events = events() }))
    local st = assert(E.start(def, {}, cid or ME, T0))
    st.progress.job = snap
    return def, st
end

-- The real fh_trade server/main.lua:144 payload: TriggerEvent('fh:trade:sold', { src, region, post, item, amount, total }).
local function sold(over)
    local p = { src = 7, region = REGION, post = 'valentine_post', item = 'trade_cloth', amount = 2, total = 28 }
    for k, v in pairs(over or {}) do p[k] = v end
    return p
end

describe('quests supply_run: offers', function()
    it('the builder is registered and the example template validates as a job', function()
        eq('function', type(JT.BUILDERS.supply_run))
        local o = find(KEY)
        eq('fh:trade:sold', o.on)
        same({ eq = 'valentine_post' }, o.where.post)
        same({ eq = 'trade_cloth' }, o.where.item)
        same({ min = 2 }, o.where.amount)
        eq(nil, o.where.region, 'the payload key is `region`; the offer must not match region')
        eq(nil, o.where.region_id, 'the payload has no `region_id`; the offer must not match it')
        eq(REGION, o.region_id)
        eq('number', type(o.rewards.money)); eq(REGION, o.rewards.rep.region_id)
    end)
    it('unknown regions and unregistered types give no supply_run offers', function()
        same({}, JT.offers('supply_run', 'nowhere'))
        eq(nil, JT.BUILDERS.freight)
    end)
end)

describe('quests supply_run: verdicts (real fh:trade:sold payload)', function()
    local offer = find(KEY)
    -- Feed through the same router the server uses (engine.eligible, then the job type's verdict hook), with the
    -- intake having resolved src -> citizenid (I.payloadFor).
    local function feed(def, st, payload, cid)
        local hook = function(n, pl, s) return JT.verdict('supply_run', n, pl, s) end
        local p = I.payloadFor(payload, cid)
        local changes = I.feed({ [def.id] = def }, { [def.id] = st }, 'fh:trade:sold', p, T0, function() return hook end)
        return changes[1] and changes[1].after or st
    end
    local function run(payload)
        local def, st = accepted(offer)
        return feed(def, st, payload, ME).status
    end
    it('src resolves to citizenid and the `region` key carries the sale: the job completes', function()
        eq('done', run(sold()))
    end)
    it('a src-only payload credits nobody until the intake resolves it', function()
        local def, st = accepted(offer)
        local hook = function(n, pl, s) return JT.verdict('supply_run', n, pl, s) end
        local changes = I.feed({ [def.id] = def }, { [def.id] = st }, 'fh:trade:sold', sold(), T0, function() return hook end)
        same({}, changes)
    end)
    it('selling more than required still completes (amount is a minimum)', function()
        eq('done', run(sold({ amount = 5 })))
    end)
    it('short amount is ignored: the job stays active', function()
        eq('active', run(sold({ amount = 1 })))
    end)
    it('wrong post is ignored', function()
        eq('active', run(sold({ post = 'rhodes_post' })))
    end)
    it('wrong item is ignored', function()
        eq('active', run(sold({ item = 'trade_whiskey' })))
    end)
    it('another citizen selling does not advance my job', function()
        eq('active', run(sold({ citizenid = OTHER })))
    end)
    it('a different event never completes it', function()
        local def, st = accepted(offer)
        local hook = function(n, pl, s) return JT.verdict('supply_run', n, pl, s) end
        local changes = I.feed({ [def.id] = def }, { [def.id] = st }, 'fh:hunting:pelt_sold',
            { citizenid = ME, post = 'valentine_post', item = 'trade_cloth', amount = 2 }, T0, function() return hook end)
        same({}, changes)
    end)
end)

describe('quests supply_run: region gate', function()
    local DISABLED = 'bluewater_marsh'
    it('a disabled region yields no supply_run offer (board.collect gates it)', function()
        local before, flag = JT.DATA[DISABLED], regions.regions[DISABLED].enabled
        JT.registerRegion(DISABLED, JT.DATA.heartlands) -- give it the supply templates, as C5 will
        local ok, err = pcall(function()
            assert(#JT.offers('supply_run', DISABLED) > 0, 'the job type itself has a template')
            local jts = {}
            for _, name in ipairs(JT.TYPES) do
                jts[name] = { hooks = { offers = function(region_id) return JT.offers(name, region_id) end } }
            end
            local lists = B.collect(DISABLED, jts, regions.isEnabled)
            eq(nil, lists.supply_run)
            eq(0, #B.rotate(DISABLED, 490001, lists))
        end)
        JT.registerRegion(DISABLED, before)
        regions.regions[DISABLED].enabled = flag
        if not ok then error(err, 0) end
    end)
end)

T.finish()
