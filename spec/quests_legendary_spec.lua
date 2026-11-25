-- Run from repo root: `~/.venvs/rf/bin/python tools/run-specs.py spec/quests_legendary_spec.lua`.
-- quests-04 L2: `legendary` job type builder validation, all 15 regions with real fh_hunting legendary ids,
-- chain_complete matching (matching {chain_id, region_id} completes; mismatched region/chain/citizen does not),
-- tier 3 gating + scaling, and lockedFor (chainState absent -> nil, step number -> nil, 'complete' -> locked).
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local describe, it, eq, same = T.describe, T.it, T.eq, T.same
local fh = here .. '../server/resources/[fh]/'
local QROOT = fh .. 'fh_quests/'
local shared = QROOT .. 'shared/'
package.path = shared .. '?.lua;' .. package.path

local JT = dofile(shared .. 'jobtypes.lua')
local Jobs = require('jobs')
local E = require('engine')
local I = require('intake')
local B = require('board')
local R = require('rewards')
local regions = require('regions')
local legendaries = dofile(fh .. 'fh_hunting/shared/legendaries.lua')

local T0 = 1795651200
local ME, OTHER = 'ABC123', 'XYZ999'

local function accepted(offer, region_id, cid)
    local snap = assert(Jobs.snapshot('legendary', offer, region_id, true))
    local def = assert(Jobs.def(snap, { regions = regions.regions }))
    local st = assert(E.start(def, {}, cid or ME, T0))
    st.progress.job = snap
    return def, st
end

local function feed(def, st, name, payload)
    local hook = function(n, p, s) return JT.verdict('legendary', n, p, s) end
    local changes = I.feed({ [def.id] = def }, { [def.id] = st }, name, payload, T0, function() return hook end)
    return changes[1] and changes[1].after or st
end

describe('quests legendary: builder validation and FXServer chunk-arg safety', function()
    it('builds valid offers and skips malformed data entries', function()
        local probe = 'legendary_probe_region'
        JT.registerRegion(probe, {
            legendaries = {
                'not_a_table',
                { chain_id = '', legendary = 'x', money = 60, rep = 5, min_tier = 3 },
                { chain_id = 'x', legendary = '', money = 60, rep = 5, min_tier = 3 },
                { chain_id = 'x', legendary = 'x', money = -1, rep = 5, min_tier = 3 },
                { chain_id = 'x', legendary = 'x', money = 10.5, rep = 5, min_tier = 3 },
                { chain_id = 'x', legendary = 'x', money = 60, rep = 0, min_tier = 3 },
                { chain_id = 'x', legendary = 'x', money = 60, rep = -2, min_tier = 3 },
                { chain_id = 'x', legendary = 'x', money = 60, rep = 1.5, min_tier = 3 },
                { chain_id = 'legendary_bear', legendary = 'legendary_bear', money = 60, rep = 5, min_tier = 3 },
            },
        })
        local ok, err = pcall(function()
            local offers = JT.offers('legendary', probe)
            eq(1, #offers)
            local o = offers[1]
            eq('legendary_bear', o.key)
            eq('fh:hunting:chain_complete', o.on)
            same({ chain_id = { eq = 'legendary_bear' }, region_id = { eq = probe } }, o.where)
            eq(3, o.min_tier)
            eq('legendary_bear', o.chain_id)
            eq('legendary_bear', o.legendary)
            eq(probe, o.region_id)
            same({ money = 60, rep = { region_id = probe, delta = 5 } }, o.rewards)
        end)
        JT.DATA[probe] = nil
        assert(ok, err)
    end)

    it('shared/jobtypes/legendary.lua registers cleanly when FXServer passes a number chunk arg', function()
        local beforeG, beforeB = FhQuestsJobTypes, JT.BUILDERS.legendary
        FhQuestsJobTypes = JT
        JT.BUILDERS.legendary = nil
        local ok, err = pcall(function() assert(loadfile(shared .. 'jobtypes/legendary.lua'))(7) end)
        local got = JT.BUILDERS.legendary
        FhQuestsJobTypes = beforeG
        JT.BUILDERS.legendary = beforeB
        assert(ok, err)
        eq('function', type(got))
    end)
end)

describe('quests legendary: all 15 regions build with real fh_hunting ids', function()
    it('every FhRegions region builds 1 valid tier-3 offer matching fh_hunting/data/legendaries/<region>.lua', function()
        local count = 0
        for rid in pairs(regions.regions) do
            count = count + 1
            local offers = JT.offers('legendary', rid)
            eq(1, #offers, rid .. ' should have 1 legendary commission')
            local o = offers[1]
            local leg = assert(legendaries.byRegion[rid], rid .. ' missing from fh_hunting legendaries')
            eq(leg.chain_id, o.chain_id, rid .. ' chain_id')
            eq(leg.id, o.legendary, rid .. ' legendary')
            eq(leg.chain_id, o.key, rid .. ' offer key')
            eq('fh:hunting:chain_complete', o.on, rid .. ' event')
            same({ chain_id = { eq = leg.chain_id }, region_id = { eq = rid } }, o.where, rid .. ' where')
            eq(3, o.min_tier, rid .. ' min_tier')
            local snap = assert(Jobs.snapshot('legendary', o, rid, true), rid .. ' snapshot')
            local def, err = Jobs.def(snap, { regions = regions.regions })
            assert(def, rid .. ' def validation: ' .. tostring(err))
        end
        eq(15, count)
    end)

    it('fh:hunting:chain_complete is in engine.INTAKE', function()
        eq(true, E.isIntake('fh:hunting:chain_complete'))
    end)
end)

describe('quests legendary: chain_complete verdicts', function()
    local offer = JT.offers('legendary', 'heartlands')[1]

    it('matching { chain_id, region_id } completes the commission', function()
        local def, st = accepted(offer, 'heartlands')
        local after = feed(def, st, 'fh:hunting:chain_complete', {
            citizenid = ME, chain_id = 'legendary_bear', region_id = 'heartlands', legendary = 'legendary_bear',
        })
        eq('done', after.status)
    end)

    it('mismatched or missing region_id does not complete the commission', function()
        local def, st = accepted(offer, 'heartlands')
        eq('active', feed(def, st, 'fh:hunting:chain_complete', {
            citizenid = ME, chain_id = 'legendary_bear', region_id = 'bayou_nwa', legendary = 'legendary_bear',
        }).status)
        eq('active', feed(def, st, 'fh:hunting:chain_complete', {
            citizenid = ME, chain_id = 'legendary_bear', legendary = 'legendary_bear',
        }).status)
    end)

    it('mismatched chain_id, wrong citizenid, or other event does not complete', function()
        local def, st = accepted(offer, 'heartlands')
        eq('active', feed(def, st, 'fh:hunting:chain_complete', {
            citizenid = ME, chain_id = 'legendary_mossback_gator', region_id = 'heartlands',
        }).status)
        eq('active', feed(def, st, 'fh:hunting:chain_complete', {
            citizenid = OTHER, chain_id = 'legendary_bear', region_id = 'heartlands',
        }).status)
        eq('active', feed(def, st, 'fh:hunting:pelt_sold', {
            citizenid = ME, chain_id = 'legendary_bear', region_id = 'heartlands',
        }).status)
    end)
end)

describe('quests legendary: tier 3 gating and reward scaling', function()
    it('board.visible hides legendary offers below tier 3 and shows them at tier 3', function()
        local offers = JT.offers('legendary', 'heartlands')
        eq(0, #B.visible(offers, 1))
        eq(0, #B.visible(offers, 2))
        eq(1, #B.visible(offers, 3))
    end)

    it('tier-3 scaling keeps payouts in line with t3 offers (base 60/5 -> scaled 135/11)', function()
        local o = JT.offers('legendary', 'heartlands')[1]
        local scaled = R.scaleByTier(o.rewards, o.min_tier)
        eq(135, scaled.money)
        eq(11, scaled.rep.delta)
    end)
end)

describe('quests legendary: lockedFor (pure + server/jobtypes.lua wiring)', function()
    local offer = JT.offers('legendary', 'heartlands')[1]

    it('pure JT.legendaryLockedFor: chainState absent/stopped/throwing/step -> nil; complete -> locked', function()
        local base = { citizenidOf = function() return ME end, huntingStarted = function() return true end }
        -- chainState absent (L0 not landed)
        eq(nil, JT.legendaryLockedFor(offer, 1, base))
        -- fh_hunting stopped
        eq(nil, JT.legendaryLockedFor(offer, 1, {
            citizenidOf = base.citizenidOf, huntingStarted = function() return false end,
            chainState = function() return 'complete' end,
        }))
        -- chainState returns step number or nil
        eq(nil, JT.legendaryLockedFor(offer, 1, {
            citizenidOf = base.citizenidOf, huntingStarted = base.huntingStarted,
            chainState = function() return nil end,
        }))
        for step = 1, 4 do
            eq(nil, JT.legendaryLockedFor(offer, 1, {
                citizenidOf = base.citizenidOf, huntingStarted = base.huntingStarted,
                chainState = function() return step end,
            }))
        end
        -- chainState throws (e.g. FXServer missing-export error before L0 lands)
        eq(nil, JT.legendaryLockedFor(offer, 1, {
            citizenidOf = base.citizenidOf, huntingStarted = base.huntingStarted,
            chainState = function() error('No such export chainState') end,
        }))
        -- chainState returns 'complete'
        local seenCid, seenChain
        local lock = JT.legendaryLockedFor(offer, 1, {
            citizenidOf = base.citizenidOf, huntingStarted = base.huntingStarted,
            chainState = function(cid, chain_id) seenCid, seenChain = cid, chain_id; return 'complete' end,
        })
        same({ reason = 'legendary_done' }, lock)
        eq(ME, seenCid)
        eq('legendary_bear', seenChain)
    end)

    it('server/jobtypes.lua registers legendary with lockedFor that handles absent, step, throw, and complete', function()
        local saved = {}
        local keys = {
            'FhQuestsJobTypes', 'FhQuestsJobs', 'FhQuestsServer', 'FhQuestsWatch', 'exports',
            'GetResourceState', 'GetCurrentResourceName', 'CreateThread', 'Wait', 'AddEventHandler', 'GetPlayers',
        }
        for _, k in ipairs(keys) do saved[k] = _G[k] end

        local registered = {}
        local huntingState = 'started'
        local huntingExports = {}
        local threads = {}

        local ok, err = pcall(function()
            _G.FhQuestsJobTypes = JT
            _G.FhQuestsJobs = Jobs
            _G.FhQuestsServer = {
                citizenidOf = function(src) return src == 1 and ME or nil end,
                srcOf = {},
                log = function() end,
            }
            _G.FhQuestsWatch = {
                jobHooks = function() return {} end,
                escortHooks = function() return {} end,
                rescueHooks = function() return {} end,
                rearmAll = function() end,
            }
            _G.GetCurrentResourceName = function() return 'fh_quests' end
            _G.GetResourceState = function(name)
                if name == 'fh_hunting' then return huntingState end
                return 'started'
            end
            _G.CreateThread = function(fn) threads[#threads + 1] = fn end
            _G.Wait = function() end
            _G.AddEventHandler = function() end
            _G.GetPlayers = function() return {} end
            _G.exports = {
                fh_quests = {
                    registerJobType = function(_, name, h) registered[name] = h; return true end,
                },
                fh_hunting = huntingExports,
            }

            dofile(QROOT .. 'server/jobtypes.lua')
            -- Second thread in server/jobtypes.lua is registration (first is the bounty poll loop).
            threads[2]()

            local legHooks = assert(registered.legendary, 'legendary job type not registered')
            assert(type(legHooks.lockedFor) == 'function', 'legendary lockedFor hook missing')

            -- 1. chainState absent (L0 not landed yet) -> nil
            eq(nil, legHooks.lockedFor(offer, 1))

            -- 2. fh_hunting stopped -> nil even if chainState would say complete
            huntingExports.chainState = function(_, cid, chain_id)
                if cid == ME and chain_id == 'legendary_bear' then return 'complete' end
                return nil
            end
            huntingState = 'stopped'
            eq(nil, legHooks.lockedFor(offer, 1))

            -- 3. fh_hunting started + chainState == 'complete' -> { reason = 'legendary_done' }
            huntingState = 'started'
            same({ reason = 'legendary_done' }, legHooks.lockedFor(offer, 1))

            -- 4. fh_hunting started + chainState == step number -> nil
            huntingExports.chainState = function() return 2 end
            eq(nil, legHooks.lockedFor(offer, 1))

            -- 5. fh_hunting started + chainState throws -> nil
            huntingExports.chainState = function() error('No such export chainState in resource fh_hunting') end
            eq(nil, legHooks.lockedFor(offer, 1))

            -- accept guard (hooks.accept)
            assert(type(legHooks.accept) == 'function', 'legendary accept hook missing')
            local function acc() return legHooks.accept(1, offer) end
            huntingExports.chainState = function() return 'complete' end
            local a1, a2 = acc()
            eq(false, a1); eq('fh_legendary_done', a2)
            for step = 1, 4 do
                huntingExports.chainState = function() return step end
                eq(true, (acc()))
            end
            huntingExports.chainState = function() return nil end
            eq(true, (acc()))
            huntingExports.chainState = function() error('boom') end
            eq(true, (acc()))
            huntingExports.chainState = nil
            eq(true, (acc()))
            huntingExports.chainState = function() return 'complete' end
            huntingState = 'stopped'
            eq(true, (acc()))
            huntingState = 'started'
        end)

        for _, k in ipairs(keys) do _G[k] = saved[k] end
        assert(ok, err)
    end)

    it('Jobs.callable and legendaryLockedFor/accept handle FXServer __call table export proxy stubs', function()
        local saved = {}
        local keys = {
            'FhQuestsJobTypes', 'FhQuestsJobs', 'FhQuestsServer', 'FhQuestsWatch', 'exports',
            'GetResourceState', 'GetCurrentResourceName', 'CreateThread', 'Wait', 'AddEventHandler', 'GetPlayers',
        }
        for _, k in ipairs(keys) do saved[k] = _G[k] end

        local registered = {}
        local proxyVal = 'complete'
        local proxyStub = setmetatable({}, {
            __call = function(_, _self, cid, chain_id)
                if cid == ME and chain_id == 'legendary_bear' then return proxyVal end
                return nil
            end,
        })
        local threads = {}

        local ok, err = pcall(function()
            eq(true, Jobs.callable(proxyStub), 'Jobs.callable accepts __call table stub')
            eq(false, Jobs.callable({}), 'Jobs.callable rejects plain table')
            eq(false, Jobs.callable(nil), 'Jobs.callable rejects nil')

            _G.FhQuestsJobTypes = JT
            _G.FhQuestsJobs = Jobs
            _G.FhQuestsServer = {
                citizenidOf = function(src) return src == 1 and ME or nil end,
                srcOf = {},
                log = function() end,
            }
            _G.FhQuestsWatch = {
                jobHooks = function() return {} end,
                escortHooks = function() return {} end,
                rescueHooks = function() return {} end,
                rearmAll = function() end,
            }
            _G.GetCurrentResourceName = function() return 'fh_quests' end
            _G.GetResourceState = function() return 'started' end
            _G.CreateThread = function(fn) threads[#threads + 1] = fn end
            _G.Wait = function() end
            _G.AddEventHandler = function() end
            _G.GetPlayers = function() return {} end
            _G.exports = {
                fh_quests = {
                    registerJobType = function(_, name, h) registered[name] = h; return true end,
                },
                fh_hunting = { chainState = proxyStub },
            }

            dofile(QROOT .. 'server/jobtypes.lua')
            threads[2]()

            local legHooks = assert(registered.legendary, 'legendary job type not registered')
            same({ reason = 'legendary_done' }, legHooks.lockedFor(offer, 1))
            local p1, p2 = legHooks.accept(1, offer)
            eq(false, p1); eq('fh_legendary_done', p2)

            proxyVal = 3
            eq(nil, legHooks.lockedFor(offer, 1))
            eq(true, (legHooks.accept(1, offer)))
        end)

        for _, k in ipairs(keys) do _G[k] = saved[k] end
        assert(ok, err)
    end)
end)

T.finish()
