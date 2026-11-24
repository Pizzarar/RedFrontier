-- Run from repo root: `lua spec/quests_escort_spec.lua` (or via tools/run-specs.py).
-- quests-02 C3: the escort job type (shared/jobtypes/escort.lua): offers, the watch kind (arrival of the escortee at
-- the destination through the shared reach-watcher), the pure lost rule (escortee dead / despawned), who is polled,
-- no watch-entry leak for the 1-point (destination) job, and the region gate.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local describe, it, eq, same = T.describe, T.it, T.eq, T.same
local shared = here .. '../server/resources/[fh]/fh_quests/shared/'
package.path = shared .. '?.lua;' .. package.path
local JT = dofile(shared .. 'jobtypes.lua')
local WR = require('watch_rules')
local Jobs = require('jobs')
local E = require('engine')
local I = require('intake')
local B = require('board')
local regions = require('regions')

local T0 = 1795651200
local ME, OTHER = 'ABC123', 'XYZ999'
local REGION = 'heartlands'
local DISABLED = 'bluewater_marsh'

local function events()
    local set = { [JT.ESCORT_ARRIVED] = true, [JT.ESCORT_LOST] = true }
    for _, name in ipairs(E.INTAKE) do set[name] = true end
    return set
end

local function escortOffer()
    local o = JT.offers('escort', REGION)[1]
    assert(o, 'heartlands has an escort template')
    return o
end

local function accepted(offer, cid)
    local snap = assert(Jobs.snapshot('escort', offer, REGION, true))
    local def = assert(Jobs.def(snap, { regions = regions.regions, events = events() }))
    local st = assert(E.start(def, {}, cid or ME, T0))
    st.progress.job = snap
    return def, st
end

local function feed(def, st, name, payload)
    local hook = function(n, p, s) return JT.verdict('escort', n, p, s) end
    local changes = I.feed({ [def.id] = def }, { [def.id] = st }, name, payload, T0, function() return hook end)
    return changes[1] and changes[1].after or st
end

local function ev(offer, cid)
    return { citizenid = cid or ME, offer_key = offer.key, region_id = REGION }
end

-- A watched escort entry whose row has been seen active (pending cleared), unless `pending`.
local function entryFor(offer, cid, src, pending)
    local e = assert(WR.entry('escort', { cid = cid or ME, src = src or 1, qid = Jobs.questId('escort', offer.key),
        offer_key = offer.key, region_id = REGION }, offer, 0))
    if not pending then e.pending = nil end
    return e
end

local function st(status, count) return { status = status, progress = { count = count } } end
local ADOPTED = { state = 'adopted', netId = 7 }

describe('quests escort: offers', function()
    it('heartlands escort offer: 1-point watched job to the destination, arrival event, spawn setup rides along', function()
        local o = escortOffer()
        eq('escort_doc_hollis', o.key)
        eq(JT.ESCORT_ARRIVED, o.on)
        eq(1, o.count)
        eq('table', type(o.start)); eq('table', type(o.destination))
        eq('string', type(o.model))
        same({ money = 28, rep = { region_id = REGION, delta = 2 } }, o.rewards)
        eq(true, WR.isWatched('escort'))
        eq(JT.ESCORT_ARRIVED, WR.eventOf('escort'))
        local e = entryFor(o)
        eq(1, #e.points)
        same(o.destination, e.points[1])
        eq(1, accepted(o).steps[1].count)
    end)
    it('a template without start, destination or model yields no offer', function()
        local before = JT.DATA[DISABLED]
        local d = JT.DATA[REGION].escorts[1]
        local function without(k)
            local c = {}
            for kk, v in pairs(d) do c[kk] = v end
            c[k] = nil
            return c
        end
        JT.registerRegion(DISABLED, { escorts = { without('start'), without('destination'), without('model') } })
        local n = #JT.offers('escort', DISABLED)
        JT.registerRegion(DISABLED, before)
        eq(0, n)
    end)
    it('neither escort event is a net event and both stay out of the shared intake whitelist', function()
        for _, name in ipairs(E.INTAKE) do
            assert(name ~= JT.ESCORT_ARRIVED and name ~= JT.ESCORT_LOST, name)
        end
        local root = here .. '../server/resources/[fh]/fh_quests/'
        for _, f in ipairs({ 'server/watch.lua', 'server/jobtypes.lua', 'client/escort.lua', 'shared/jobtypes/escort.lua' }) do
            local h = assert(io.open(root .. f, 'r'))
            local src = h:read('a')
            h:close()
            for _, name in ipairs({ 'escort_arrived', 'escort_lost' }) do
                assert(not src:find("RegisterNetEvent%(%s*'fh:quests:" .. name), f .. ' registers ' .. name)
                assert(not src:find("TriggerServerEvent%(%s*'fh:quests:" .. name), f .. ' sends ' .. name)
                assert(not src:find("TriggerClientEvent%(%s*'fh:quests:" .. name), f .. ' sends ' .. name)
            end
        end
    end)
end)

describe('quests escort: verdicts', function()
    it('arrival completes with one reward', function()
        local o = escortOffer()
        local def, s = accepted(o)
        s = feed(def, s, JT.ESCORT_ARRIVED, ev(o))
        eq('done', s.status)
        eq(true, s.progress.reward_pending)
    end)
    it('lost fails the job, no reward', function()
        local o = escortOffer()
        local def, s = accepted(o)
        s = feed(def, s, JT.ESCORT_LOST, ev(o))
        eq('failed', s.status)
        eq(nil, s.progress.reward_pending)
    end)
    it('other players, offers, regions and events change nothing', function()
        local o = escortOffer()
        local def, s = accepted(o)
        for _, name in ipairs({ JT.ESCORT_ARRIVED, JT.ESCORT_LOST }) do
            eq('active', feed(def, s, name, ev(o, OTHER)).status)
            local p = ev(o); p.offer_key = 'escort_other'
            eq('active', feed(def, s, name, p).status)
            p = ev(o); p.region_id = 'great_plains'
            eq('active', feed(def, s, name, p).status)
        end
        eq('active', feed(def, s, WR.POINT_EVENT, { citizenid = ME, offer_key = o.key, region_id = REGION,
            point = 1 }).status)
        eq('active', feed(def, s, JT.BOUNTY_EVENT, ev(o)).status)
    end)
    it('the arrival payload of the watch kind is exactly what the verdict accepts', function()
        local o = escortOffer()
        local e = entryFor(o)
        same(ev(o), WR.payload(e, 1))
        local def, s = accepted(o)
        eq('done', feed(def, s, WR.eventOf('escort'), WR.payload(e, 1)).status)
        eq('failed', feed(def, s, JT.ESCORT_LOST, JT.escortLostPayload(e)).status)
    end)
end)

describe('quests escort: arrival (reach-watcher, posOf = the escortee)', function()
    it('the escortee within radius of the destination arrives; anywhere else does not', function()
        local o = escortOffer()
        local d = o.destination
        local e = entryFor(o)
        eq(nil, WR.reached(e, o.start))
        eq(nil, WR.reached(e, { x = d.x + WR.DEFAULT_RADIUS + 1, y = d.y }))
        eq(1, WR.reached(e, { x = d.x + 3.0, y = d.y - 2.0, z = 0.0 }))
    end)
    it('tick: only escort holders are polled, once each; arrival is the last (only) point', function()
        local o = escortOffer()
        local watch = { a = entryFor(o, ME, 1), b = entryFor(o, OTHER, 2) }
        local asked = {}
        local hits = WR.tick(watch, function(e)
            asked[e.src] = (asked[e.src] or 0) + 1
            return e.src == 1 and o.destination or o.start
        end)
        same({ [1] = 1, [2] = 1 }, asked)
        eq(1, #hits); eq(ME, hits[1].entry.cid); eq(true, hits[1].last)
    end)
end)

describe('quests escort: lost rule (pure)', function()
    it('adopted + alive: ok; dead: lost at once', function()
        local e = entryFor(escortOffer())
        eq('ok', JT.escortObserve(e, { spawn = ADOPTED, exists = true, dead = false }))
        eq('lost', JT.escortObserve(e, { spawn = ADOPTED, exists = true, dead = true }))
    end)
    it('request gone, failed or despawned (or onFailed): lost', function()
        local e = entryFor(escortOffer())
        eq('lost', JT.escortObserve(e, { spawn = nil }))
        eq('lost', JT.escortObserve(e, { spawn = { state = 'failed' } }))
        eq('lost', JT.escortObserve(e, { spawn = { state = 'despawned' } }))
        eq('lost', JT.escortObserve(e, { spawn = ADOPTED, exists = true, failed = true }))
    end)
    it('still spawning or re-requested (pending / verifying): wait, never lost', function()
        local e = entryFor(escortOffer())
        for _ = 1, 10 do
            eq('wait', JT.escortObserve(e, { spawn = { state = 'pending' } }))
            eq('wait', JT.escortObserve(e, { spawn = { state = 'verifying' } }))
        end
    end)
    it('adopted but the entity is missing: lost only after LOST_TICKS checks in a row', function()
        local e = entryFor(escortOffer())
        for _ = 1, JT.ESCORT_LOST_TICKS - 1 do eq('wait', JT.escortObserve(e, { spawn = ADOPTED, exists = false })) end
        eq('ok', JT.escortObserve(e, { spawn = ADOPTED, exists = true })) -- back: the counter resets
        for _ = 1, JT.ESCORT_LOST_TICKS - 1 do eq('wait', JT.escortObserve(e, { spawn = ADOPTED, exists = false })) end
        eq('lost', JT.escortObserve(e, { spawn = ADOPTED, exists = false }))
    end)
    it('a pending (uncommitted accept) or finished (arrived) entry is never lost', function()
        local o = escortOffer()
        local p = entryFor(o, ME, 1, true)
        eq('wait', JT.escortObserve(p, { spawn = nil }))
        local f = entryFor(o)
        WR.mark(f, 1)
        eq('wait', JT.escortObserve(f, { spawn = ADOPTED, exists = true, dead = true }))
    end)
    it('a malformed observation is no evidence: wait', function()
        local e = entryFor(escortOffer())
        eq('wait', JT.escortObserve(e, nil))
        eq('wait', JT.escortObserve(e, 'x'))
    end)
end)

describe('quests escort: collectLost (who is checked)', function()
    it('observes only escort entries (not survey, not pending, not finished), once each, and skips throws', function()
        local o = escortOffer()
        local survey = assert(WR.entry('survey', { cid = OTHER, src = 3, qid = 'job:survey:s', offer_key = 's',
            region_id = REGION }, JT.offers('survey', REGION)[1], 0))
        survey.pending = nil
        local fin = entryFor(o, 'FIN', 4); WR.mark(fin, 1)
        local watch = { a = entryFor(o, ME, 1), b = entryFor(o, OTHER, 2), c = survey,
            d = entryFor(o, 'PEND', 5, true), f = fin, g = entryFor(o, 'BOOM', 6) }
        local asked = {}
        local lost = JT.escortCollectLost(watch, function(e)
            asked[e.src] = (asked[e.src] or 0) + 1
            if e.src == 6 then error('no entity') end
            return { spawn = e.src == 1 and { state = 'despawned' } or ADOPTED, exists = true }
        end)
        same({ [1] = 1, [2] = 1, [6] = 1 }, asked)
        eq(1, #lost); eq('a', lost[1].key); eq(ME, lost[1].entry.cid)
        eq(true, watch.a.lost)
    end)
    it('a lost entry is no longer polled for arrival and is reported again each check until the row leaves active', function()
        local o = escortOffer()
        local watch = { a = entryFor(o, ME, 1) }
        local observe = function() return { spawn = nil } end
        eq(1, #JT.escortCollectLost(watch, observe))
        local n = 0
        eq(0, #WR.tick(watch, function(e) n = n + 1; return JT.escortPos(e, o.destination) end))
        eq(1, #JT.escortCollectLost(watch, observe)) -- the fail never landed: say it again
        eq('drop', WR.heal(watch.a, st('failed', 0)))
    end)
    it('escortPos: the escortee position unless the entry is lost', function()
        local e = entryFor(escortOffer())
        same({ x = 1, y = 2 }, JT.escortPos(e, { x = 1, y = 2 }))
        e.lost = true
        eq(nil, JT.escortPos(e, { x = 1, y = 2 }))
    end)
end)

describe('quests escort: the 1-point job cannot leak a watch entry', function()
    it('pending is never polled (no arrival before the row is active); arrived + done row drops it', function()
        local o = escortOffer()
        local e = entryFor(o, ME, 1, true)
        local asked = 0
        eq(0, #WR.tick({ k = e }, function() asked = asked + 1; return o.destination end))
        eq(0, asked)
        eq('keep', WR.heal(e, st('done', 0))) -- the previous run's done row while accept commits
        eq('keep', WR.heal(e, st('active', 0)))
        local hits = WR.tick({ k = e }, function() return o.destination end)
        eq(1, #hits); eq(true, hits[1].last)
        eq(0, #WR.tick({ k = e }, function() error('finished: never polled') end))
        eq('drop', WR.heal(e, st('done', 1)))
    end)
    it('arrival never credited rolls back so the escortee can arrive again; a failed row drops', function()
        local o = escortOffer()
        local e = entryFor(o)
        WR.mark(e, 1)
        for _ = 1, WR.HEAL_TICKS do WR.heal(e, st('active', 0)) end
        eq(false, WR.finished(e))
        eq('drop', WR.heal(e, st('failed', 0)))
    end)
    it('a pending entry whose row never turns active is dropped after PENDING_TICKS', function()
        local e = entryFor(escortOffer(), ME, 1, true)
        for _ = 1, WR.PENDING_TICKS do eq('keep', WR.heal(e, nil)) end
        eq('drop', WR.heal(e, nil))
    end)
end)

describe('quests escort: region gate', function()
    it('a disabled region with escort data yields no escort offer on the board; enabling shows it', function()
        local before, flag = JT.DATA[DISABLED], regions.regions[DISABLED].enabled
        JT.registerRegion(DISABLED, { escorts = JT.DATA[REGION].escorts })
        local ok, err = pcall(function()
            eq(1, #JT.offers('escort', DISABLED))
            local types = { escort = { hooks = { offers = function(r) return JT.offers('escort', r) end } } }
            local n = 0
            for _, l in pairs(B.collect(DISABLED, types, regions.isEnabled)) do n = n + #l end
            eq(0, n)
            regions.regions[DISABLED].enabled = true
            n = 0
            for _, l in pairs(B.collect(DISABLED, types, regions.isEnabled)) do n = n + #l end
            eq(1, n)
        end)
        JT.registerRegion(DISABLED, before)
        regions.regions[DISABLED].enabled = flag
        if not ok then error(err, 0) end
    end)
end)

T.finish()
