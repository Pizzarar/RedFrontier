-- fh_alife contracts rules spec (a-life-02 B3). Run from repo root via tools/run-specs.py (or `lua spec/contracts_rules_spec.lua`).
-- Loads shared/contracts_rules.lua against the real FhRegions + FhZonesConfig camps, and drives the offers + the
-- onEvent verdict end to end through fh_quests' intake.feed (credit rules included), like quests_jobtypes_spec.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local case, eq, same = T.it, T.eq, T.same

-- fh_quests pure modules for snapshot/def/feed (the verdict itself is self-contained; no FhQuestsMatch dependency).
local qshared = here .. '../server/resources/[fh]/fh_quests/shared/'
package.path = qshared .. '?.lua;' .. package.path
local Jobs = require('jobs')
local E = require('engine')
local I = require('intake')

local R = dofile(here .. '../server/resources/[fh]/fh_alife/shared/alife_rules.lua')
local C = dofile(here .. '../server/resources/[fh]/fh_alife/shared/contracts_rules.lua')

-- Load FhRegions/FhPlaceResolver + vector3 stand-in, then the configs (fh_zones resolves camps).
local Regions = dofile(here .. 'support/world_config.lua')
dofile(here .. '../server/resources/[fh]/fh_zones/config.lua')
dofile(here .. '../server/resources/[fh]/fh_alife/config.lua')
local cfg = FhAlifeConfig
local camps = FhZonesConfig.camps

local T0 = 1795651200
local ME, OTHER = 'ABC123', 'XYZ999'
local REGION = 'heartlands'

local function events()
    local set = { [C.SQUAD_EVENT] = true }
    for _, name in ipairs(E.INTAKE) do set[name] = true end
    return set
end

---Real FhRegions with per-region `ambush` overlaid (@world H format); isEnabled/factions/territories are the real ones.
local function fixtureRegions(ambush)
    local rr = {}
    for id, r in pairs(Regions.regions) do
        local copy = {}
        for k, v in pairs(r) do copy[k] = v end
        copy.ambush = ambush and ambush[id]
        rr[id] = copy
    end
    return setmetatable({ regions = rr }, { __index = Regions })
end

local HEART_AMBUSH = {
    { id = 'heartlands_amb_bend', x = 100.0, y = 500.0, z = 110.0, label = 'Dakota bend', verified = true },
    { x = 120.0, y = 520.0, z = 111.0 }, -- no id -> heartlands:ambush:2, no label
}
local heartCtx = R.context(cfg, fixtureRegions({ heartlands = HEART_AMBUSH }), camps)

---A state with an optional ambush squad (or none), so offers see camps only / a held node.
local function stateWithSquad(nodeId, phase)
    local st = R.newState()
    if nodeId then
        st.squads.sq1 = { id = 'sq1', goal = 'ambush', faction = 'outlaws', strength = 3, from = 'heartlands_t1_01',
            to = nodeId, node = nodeId, region_id = REGION, phase = phase, travel = 2, etaTick = 10 }
    end
    return st
end

local function findOffer(offers, key)
    for _, o in ipairs(offers) do if o.key == key then return o end end
    return nil
end

-- Accept an offer the way api.lua does: snapshot -> def -> engine.start, progress.job = snapshot.
local function accepted(offer, cid)
    local snap = assert(Jobs.snapshot(C.JOB_TYPE, offer, REGION, true))
    local def = assert(Jobs.def(snap, { regions = Regions.regions, events = events() }))
    local st = assert(E.start(def, {}, cid or ME, T0))
    st.progress.job = snap
    return def, st
end

-- Feed an event through the same router the server uses (engine.eligible, then the job type's verdict hook).
local function feed(def, st, name, payload)
    local hook = function(n, p, s) return C.verdict(C.JOB_TYPE, n, p, s) end
    local changes = I.feed({ [def.id] = def }, { [def.id] = st }, name, payload, T0, function() return hook end)
    return changes[1] and changes[1].after or st
end

-- ---------------------------------------------------------------- offers

case('offers: every outlaw-held camp posts a "clear <camp>" job, law-held camps do not', function()
    local all = C.offers(heartCtx, R.newState(), REGION)
    eq(4, #all, '4 heartlands camps, all outlaw-held by default, no squads')
    local o = findOffer(all, 'camp_heartlands_t1_01')
    eq('Clear out: Heartland Bluffs Camp', o.title)
    eq(C.CAMP_EVENT, o.on)
    same({ camp_id = 'heartlands_t1_01' }, o.where)
    same({ money = 40, rep = { region_id = REGION, delta = 3 } }, o.rewards)

    local st = R.newState()
    st.owners.heartlands_t1_01 = 'lawmen'
    local after = C.offers(heartCtx, st, REGION)
    eq(3, #after)
    eq(nil, findOffer(after, 'camp_heartlands_t1_01'), 'law-held camp no longer offered')
end)

case('offers: a held node posts a "break the ambush" job; travel/return squads do not', function()
    local held = C.offers(heartCtx, stateWithSquad('heartlands_amb_bend', 'hold'), REGION)
    eq(5, #held, '4 camp offers + 1 ambush offer')
    local o = findOffer(held, 'ambush_heartlands_amb_bend')
    eq('Break the ambush: Dakota bend', o.title)
    eq(C.SQUAD_EVENT, o.on)
    same({ node_id = 'heartlands_amb_bend' }, o.where)
    same({ money = 30, rep = { region_id = REGION, delta = 2 } }, o.rewards)

    eq(4, #C.offers(heartCtx, stateWithSquad('heartlands_amb_bend', 'travel'), REGION), 'travel squad not offered')
    eq(4, #C.offers(heartCtx, stateWithSquad('heartlands_amb_bend', 'return'), REGION), 'returning squad not offered')
end)

case('offers: a node without a label uses its id in the title', function()
    local o = findOffer(C.offers(heartCtx, stateWithSquad('heartlands:ambush:2', 'hold'), REGION),
        'ambush_heartlands:ambush:2')
    eq('Break the ambush: heartlands:ambush:2', o.title)
end)

case('offers: disabled region offers nothing; a region with no ambush nodes offers camps only, no error', function()
    eq(false, Regions.isEnabled('bluewater_marsh'), 'fixture assumes bluewater_marsh is disabled')
    same({}, C.offers(heartCtx, R.newState(), 'bluewater_marsh'))
    local sm = C.offers(heartCtx, R.newState(), 'scarlett_meadows')
    eq(3, #sm, '3 scarlett_meadows camps, all outlaw-held, no ambush nodes')
    for _, o in ipairs(sm) do eq(C.CAMP_EVENT, o.on) end
    same({}, C.offers(heartCtx, R.newState(), 'nowhere'))
end)

case('offers: keys are unique and every offer passes snapshot + def validation (as a hook-driven job)', function()
    local offers = C.offers(heartCtx, stateWithSquad('heartlands_amb_bend', 'hold'), REGION)
    local seen = {}
    for _, o in ipairs(offers) do
        eq(nil, seen[o.key], o.key)
        seen[o.key] = true
        local snap = assert(Jobs.snapshot(C.JOB_TYPE, o, REGION, true), o.key)
        local def, err = Jobs.def(snap, { regions = Regions.regions, events = events() })
        assert(def, o.key .. ' ' .. tostring(err))
    end
    eq(5, #offers)
end)

-- ---------------------------------------------------------------- verdicts

case('verdict: a camp job completes for each participant of the real camp_cleared payload', function()
    local offer = findOffer(C.offers(heartCtx, R.newState(), REGION), 'camp_heartlands_t1_01')
    local def, st = accepted(offer, ME)
    local after = feed(def, st, C.CAMP_EVENT, { camp_id = 'heartlands_t1_01', region_id = REGION, loot = {},
        participants = { OTHER, ME } })
    eq('done', after.status)
end)

case('verdict: wrong camp / no participants leave the camp job active', function()
    local offer = findOffer(C.offers(heartCtx, R.newState(), REGION), 'camp_heartlands_t1_01')
    local def, st = accepted(offer, ME)
    eq('active', feed(def, st, C.CAMP_EVENT, { camp_id = 'heartlands_t1_02', participants = { ME } }).status)
    eq('active', feed(def, st, C.CAMP_EVENT, { camp_id = 'heartlands_t1_01' }).status)
    eq('active', feed(def, st, C.CAMP_EVENT, { camp_id = 'heartlands_t1_01', participants = { OTHER } }).status)
end)

case('verdict: an ambush job completes when its node\'s squad is wiped and the holder is credited', function()
    local offer = findOffer(C.offers(heartCtx, stateWithSquad('heartlands_amb_bend', 'hold'), REGION),
        'ambush_heartlands_amb_bend')
    local def, st = accepted(offer, ME)
    local after = feed(def, st, C.SQUAD_EVENT, { squad_id = 'sq1', node_id = 'heartlands_amb_bend', region_id = REGION,
        faction = 'outlaws', participants = { ME } })
    eq('done', after.status)
end)

case('verdict: ambush job needs a credited payload — no participants / someone else credits nobody', function()
    local offer = findOffer(C.offers(heartCtx, stateWithSquad('heartlands_amb_bend', 'hold'), REGION),
        'ambush_heartlands_amb_bend')
    local def, st = accepted(offer, ME)
    -- Without participants (or with only other players) engine.eligible gates the event out: nobody is paid.
    eq('active', feed(def, st, C.SQUAD_EVENT, { squad_id = 'sq1', node_id = 'heartlands_amb_bend', region_id = REGION,
        faction = 'outlaws' }).status)
    eq('active', feed(def, st, C.SQUAD_EVENT, { squad_id = 'sq1', node_id = 'heartlands_amb_bend', region_id = REGION,
        faction = 'outlaws', participants = { OTHER } }).status)
end)

case('verdict: wrong node / wrong event never advances an ambush job', function()
    local offer = findOffer(C.offers(heartCtx, stateWithSquad('heartlands_amb_bend', 'hold'), REGION),
        'ambush_heartlands_amb_bend')
    local def, st = accepted(offer, ME)
    eq('active', feed(def, st, C.SQUAD_EVENT, { squad_id = 'sq1', node_id = 'heartlands:ambush:2', region_id = REGION,
        faction = 'outlaws', participants = { ME } }).status)
    eq('active', feed(def, st, C.CAMP_EVENT, { camp_id = 'heartlands_t1_01', participants = { ME } }).status)
end)

case('verdict: pure function matches the offer event + where and nothing else', function()
    local offer = findOffer(C.offers(heartCtx, stateWithSquad('heartlands_amb_bend', 'hold'), REGION),
        'ambush_heartlands_amb_bend')
    local _, st = accepted(offer, ME)
    eq('progress', C.verdict(C.JOB_TYPE, C.SQUAD_EVENT, { squad_id = 'sq1', node_id = 'heartlands_amb_bend',
        region_id = REGION, faction = 'outlaws' }, st))
    eq(nil, C.verdict(C.JOB_TYPE, C.SQUAD_EVENT, { node_id = 'heartlands:ambush:2' }, st))
    eq(nil, C.verdict(C.JOB_TYPE, C.CAMP_EVENT, { node_id = 'heartlands_amb_bend' }, st))
    eq(nil, C.verdict(C.JOB_TYPE, C.SQUAD_EVENT, { node_id = 'heartlands_amb_bend' }, { citizenid = ME }))
    eq(nil, C.verdict('camp_clear', C.SQUAD_EVENT, { node_id = 'heartlands_amb_bend' }, st))
end)

T.finish()
