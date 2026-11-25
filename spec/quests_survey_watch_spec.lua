-- Run from repo root: `lua spec/quests_survey_watch_spec.lua` (or via tools/run-specs.py).
-- quests-02 C2: the shared reach-watcher rules (shared/watch_rules.lua: distance, visit order, who is polled) and the
-- survey job type (shared/jobtypes/survey.lua) end to end through intake.feed.
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
    local set = { [WR.POINT_EVENT] = true }
    for _, name in ipairs(E.INTAKE) do set[name] = true end
    return set
end

local function surveyOffer()
    local o = JT.offers('survey', REGION)[1]
    assert(o, 'heartlands has a survey template')
    return o
end

local function accepted(offer, cid)
    local snap = assert(Jobs.snapshot('survey', offer, REGION, true))
    local def = assert(Jobs.def(snap, { regions = regions.regions, events = events() }))
    local st = assert(E.start(def, {}, cid or ME, T0))
    st.progress.job = snap
    return def, st
end

local function feed(def, st, payload, name)
    local hook = function(n, p, s) return JT.verdict('survey', n, p, s) end
    local changes = I.feed({ [def.id] = def }, { [def.id] = st }, name or WR.POINT_EVENT, payload, T0,
        function() return hook end)
    return changes[1] and changes[1].after or st
end

local function pt(offer, point, cid)
    return { citizenid = cid or ME, offer_key = offer.key, region_id = REGION, point = point }
end

-- A watched entry whose row has been seen active (pending cleared), unless `pending` asks for a fresh accept.
local function entryFor(offer, cid, src, done, ordered, pending)
    local o = offer
    if ordered ~= nil then
        o = {}
        for k, v in pairs(offer) do o[k] = v end
        o.ordered = ordered
    end
    local e = assert(WR.entry('survey', { cid = cid or ME, src = src or 1, qid = Jobs.questId('survey', offer.key),
        offer_key = offer.key, region_id = REGION }, o, done))
    if not pending then e.pending = nil end
    return e
end

-- A non-table coordinate value, like FXServer's vector3 userdata (type 'vector3'): Lua 5.4 has no newproxy, so use a
-- coroutine with a temporary per-type metatable (type() is 'thread', never 'table'). Indexing unknown fields
-- errors, as a vector3 can. Calls f(make) and restores the thread metatable afterwards.
local function withVectors(f)
    local probe = coroutine.create(function() end)
    local old = debug.getmetatable(probe)
    local fields = setmetatable({}, { __mode = 'k' })
    debug.setmetatable(probe, { __index = function(v, k)
        local c = fields[v]
        if c and c[k] ~= nil then return c[k] end
        error('vector3 has no field ' .. tostring(k))
    end })
    local function make(x, y, z)
        local v = coroutine.create(function() end)
        fields[v] = { x = x, y = y, z = z }
        return v
    end
    local ok, err = pcall(f, make)
    debug.setmetatable(probe, old)
    if not ok then error(err, 0) end
end

describe('quests watch rules: distance', function()
    it('within radius is horizontal and inclusive; z is ignored', function()
        local p = { x = 100.0, y = 200.0, z = 10.0 }
        eq(true, WR.within({ x = 100.0, y = 200.0, z = 500.0 }, p, 5.0))
        eq(true, WR.within({ x = 103.0, y = 204.0, z = 0.0 }, p, 5.0)) -- exactly 5
        eq(false, WR.within({ x = 103.1, y = 204.0, z = 10.0 }, p, 5.0))
        eq(true, WR.within({ x = 100.0 + WR.DEFAULT_RADIUS, y = 200.0 }, p)) -- default radius
    end)
    it('missing or malformed coords never count', function()
        local p = { x = 0.0, y = 0.0, z = 0.0 }
        eq(false, WR.within(nil, p, 5))
        eq(false, WR.within({ x = 0.0 }, p, 5))
        eq(false, WR.within({ x = 0 / 0, y = 0.0 }, p, 5))
        eq(false, WR.within({ x = 0.0, y = 0.0 }, { x = 'a', y = 0 }, 5))
    end)
end)

describe('quests watch rules: visit order', function()
    it('ordered: only done + 1 is a target; a later point reached first is rejected', function()
        local o = surveyOffer()
        local e = entryFor(o)
        same({ 1 }, WR.nextTargets(e))
        eq(nil, WR.reached(e, o.points[2]))
        eq(nil, WR.reached(e, o.points[3]))
        eq(1, WR.reached(e, o.points[1]))
        eq(false, WR.mark(e, 1))
        same({ 2 }, WR.nextTargets(e))
        eq(nil, WR.reached(e, o.points[1])) -- already done
        eq(2, WR.reached(e, o.points[2]))
    end)
    it('any-order: every unvisited point is a target, a visited one never counts twice', function()
        local o = surveyOffer()
        local e = entryFor(o, nil, nil, 0, false)
        eq(false, e.ordered)
        same({ 1, 2, 3 }, WR.nextTargets(e))
        eq(3, WR.reached(e, o.points[3]))
        WR.mark(e, 3)
        eq(nil, WR.reached(e, o.points[3]))
        same({ 1, 2 }, WR.nextTargets(e))
        eq(1, WR.reached(e, o.points[1]))
        WR.mark(e, 1)
        eq(true, WR.mark(e, 2))
        same({}, WR.nextTargets(e))
        eq(true, WR.finished(e))
    end)
    it('a restored ordered entry resumes at the persisted count (clamped to the point list)', function()
        local o = surveyOffer()
        same({ 3 }, WR.nextTargets(entryFor(o, nil, nil, 2)))
        same({}, WR.nextTargets(entryFor(o, nil, nil, 99)))
        same({ 1 }, WR.nextTargets(entryFor(o, nil, nil, -4)))
    end)
    it('acceptsPoint: ordered needs exactly count + 1; any-order any 1..total while unfinished', function()
        eq(true, WR.acceptsPoint(true, 3, 0, 1))
        eq(false, WR.acceptsPoint(true, 3, 0, 2))
        eq(false, WR.acceptsPoint(true, 3, 1, 1))
        eq(true, WR.acceptsPoint(false, 3, 1, 3))
        eq(false, WR.acceptsPoint(false, 3, 3, 1))
        eq(false, WR.acceptsPoint(true, 3, 0, 0))
        eq(false, WR.acceptsPoint(true, 3, 0, 4))
        eq(false, WR.acceptsPoint(true, 3, 0, 'x'))
        eq(false, WR.acceptsPoint(true, 3, 0, 1.5))
    end)
end)

describe('quests watch rules: who is polled', function()
    it('watchedJob: only registered kinds count as watched held jobs', function()
        eq('survey', (WR.watchedJob('job:survey:survey_ridge_markers')))
        eq(nil, WR.watchedJob('job:bounty:bounty_silas_crow'))
        eq(nil, WR.watchedJob('family:hale:1'))
        eq(nil, WR.watchedJob(nil))
    end)
    it('tick asks positions only for watch entries (holders), once each, and skips a throwing posOf', function()
        local o = surveyOffer()
        local watch = {
            [WR.key(ME, 'q')] = entryFor(o, ME, 1),
            [WR.key(OTHER, 'q')] = entryFor(o, OTHER, 2),
        }
        local asked = {}
        local pos = { [1] = o.points[1], [3] = o.points[1] } -- src 3 holds nothing: must never be asked
        local hits = WR.tick(watch, function(e)
            asked[e.src] = (asked[e.src] or 0) + 1
            if e.src == 2 then error('no ped') end
            return pos[e.src]
        end)
        same({ [1] = 1, [2] = 1 }, asked)
        eq(1, #hits)
        eq(ME, hits[1].entry.cid)
        eq(1, hits[1].point)
        eq(false, hits[1].last)
        same({ citizenid = ME, offer_key = o.key, region_id = REGION, point = 1 }, WR.payload(hits[1].entry, 1))
    end)
    it('a finished entry is not polled; the last point is flagged', function()
        local o = surveyOffer()
        local e = entryFor(o, ME, 1, 2)
        local watch = { k = e }
        local n = 0
        local hits = WR.tick(watch, function() n = n + 1; return o.points[3] end)
        eq(true, hits[1].last)
        WR.tick(watch, function() n = n + 1; return o.points[3] end)
        eq(1, n)
    end)
    it('ownedBy lists only the leaving player\'s entries', function()
        local o = surveyOffer()
        local watch = { a = entryFor(o, ME, 1), b = entryFor(o, OTHER, 2), c = entryFor(o, ME, 1) }
        same({ 'a', 'c' }, WR.ownedBy(watch, 1))
    end)
    it('registerKind: a new kind (escort/rescue style) plugs in without core edits', function()
        WR.registerKind('spec_kind', { points = function(offer) return { offer.dest } end, radius = 2.0,
            event = 'fh:quests:spec_arrived' })
        eq(true, WR.isWatched('spec_kind'))
        eq('fh:quests:spec_arrived', WR.eventOf('spec_kind'))
        eq(WR.POINT_EVENT, WR.eventOf('survey'))
        local e = assert(WR.entry('spec_kind', { cid = ME, src = 1 }, { dest = { x = 0.0, y = 0.0 } }, 0))
        eq(nil, WR.reached(e, { x = 3.0, y = 0.0 }))
        eq(1, WR.reached(e, { x = 1.0, y = 0.0 }))
        eq(nil, (WR.entry('spec_kind', { cid = ME }, { dest = nil }, 0)))
        eq(nil, (WR.entry('nope', { cid = ME }, {}, 0)))
        WR.KINDS.spec_kind = nil
    end)
end)

describe('quests watch rules: heal from the cached state', function()
    local function st(status, count) return { status = status, progress = { count = count } } end
    it('no cached rows: keep and change nothing; not active: drop', function()
        local e = entryFor(surveyOffer(), ME, 1, 1, nil, true)
        eq('keep', WR.heal(e, nil)); eq(1, e.done)
        eq('keep', WR.heal(e, st('done', 0)), 'fresh accept: the old done row is not committed over yet')
        eq('keep', WR.heal(e, st('active', 1)))
        eq('drop', WR.heal(e, st('done', 0)))
        eq('drop', WR.heal(e, st('failed', 1)))
    end)
    it('one tick of lag is tolerated; a point never credited rolls back after HEAL_TICKS', function()
        local o = surveyOffer()
        local e = entryFor(o, ME, 1, 0)
        WR.mark(e, 1) -- emitted, the intake has not landed yet
        eq('keep', WR.heal(e, st('active', 0))); eq(1, e.done)
        eq('keep', WR.heal(e, st('active', 0))); eq(0, e.done)
        same({ 1 }, WR.nextTargets(e))
    end)
    it('a landed credit clears the lag; a count ahead catches the entry up', function()
        local e = entryFor(surveyOffer(), ME, 1, 0)
        WR.mark(e, 1)
        WR.heal(e, st('active', 0))
        WR.heal(e, st('active', 1)); eq(nil, e.lag); eq(1, e.done)
        WR.heal(e, st('active', 2)); eq(2, e.done)
        same({ 3 }, WR.nextTargets(e))
    end)
end)

describe('quests watch rules: vector3 coords (C2 review HIGH)', function()
    it('within reads x/y from a non-table vector value, for pos and for the point', function()
        withVectors(function(vec)
            local v = vec(100.0, 200.0, 5.0)
            eq('thread', type(v))
            eq(true, WR.within(v, { x = 103.0, y = 204.0, z = 0.0 }, 5.0))
            eq(true, WR.within({ x = 103.0, y = 204.0 }, v, 5.0))
            eq(false, WR.within(vec(120.0, 200.0, 0.0), { x = 100.0, y = 200.0 }, 5.0))
            eq(false, WR.within(vec(0 / 0, 0.0, 0.0), { x = 0.0, y = 0.0 }, 5.0))
            eq(false, WR.within(vec(nil, 0.0, 0.0), { x = 0.0, y = 0.0 }, 5.0)) -- errors on .x: pcall'd
            eq(false, WR.within(coroutine.create(function() end), { x = 0.0, y = 0.0 }, 5.0))
        end)
    end)
    it('tick reaches a point when posOf (default ped or a kind.posOf) returns a vector value', function()
        withVectors(function(vec)
            local o = surveyOffer()
            local p1 = o.points[1]
            local watch = { a = entryFor(o, ME, 1) }
            local hits = WR.tick(watch, function() return vec(p1.x, p1.y, p1.z) end)
            eq(1, #hits); eq(1, hits[1].point)
            WR.registerKind('spec_vec', { points = function(offer) return { offer.dest } end, radius = 2.0,
                posOf = function() return vec(1.0, 1.0, 0.0) end })
            local e = assert(WR.entry('spec_vec', { cid = ME, src = 1 }, { dest = { x = 0.0, y = 0.0 } }, 0))
            e.pending = nil
            hits = WR.tick({ k = e }, function(x) return WR.KINDS[x.job_type].posOf(x) end)
            eq(1, #hits); eq(true, hits[1].last)
            WR.KINDS.spec_vec = nil
        end)
    end)
end)

describe('quests watch rules: pending entries (C2 review LOW)', function()
    local function st(status, count) return { status = status, progress = { count = count } } end
    local function onePoint()
        WR.registerKind('spec_one', { points = function(offer) return { offer.dest } end })
        return assert(WR.entry('spec_one', { cid = ME, src = 1, qid = 'job:spec_one:k' },
            { dest = { x = 0.0, y = 0.0 } }, 0))
    end
    it('a pending entry is never polled, so a 1-point job cannot finish before its row reads active', function()
        local e = onePoint()
        local asked = 0
        eq(0, #WR.tick({ k = e }, function() asked = asked + 1; return { x = 0.0, y = 0.0 } end))
        eq(0, asked)
        eq('keep', WR.heal(e, st('done', 0))) -- old done row while accept's commit is in flight
        eq('keep', WR.heal(e, st('active', 0)))
        eq(1, #WR.tick({ k = e }, function() return { x = 0.0, y = 0.0 } end))
        eq('drop', WR.heal(e, st('done', 0))) -- completed: dropped, no leak
        WR.KINDS.spec_one = nil
    end)
    it('a pending entry whose row never turns active is dropped after PENDING_TICKS', function()
        local e = onePoint()
        for _ = 1, WR.PENDING_TICKS do eq('keep', WR.heal(e, st('done', 0))) end
        eq('drop', WR.heal(e, st('done', 0)))
        local f = onePoint()
        for _ = 1, WR.PENDING_TICKS do eq('keep', WR.heal(f, nil)) end
        eq('drop', WR.heal(f, nil))
        WR.KINDS.spec_one = nil
    end)
end)

describe('quests survey: offers and verdicts', function()
    it('heartlands survey offer is a valid hook-driven job with count = #points', function()
        local o = surveyOffer()
        eq('survey_ridge_markers', o.key)
        eq(3, o.count)
        eq(3, #o.points)
        eq(WR.POINT_EVENT, o.on)
        local def = accepted(o)
        eq(3, def.steps[1].count)
    end)
    it('completes after all points in order, with one reward', function()
        local o = surveyOffer()
        local def, st = accepted(o)
        st = feed(def, st, pt(o, 1)); eq('active', st.status); eq(1, st.progress.count)
        st = feed(def, st, pt(o, 2)); eq('active', st.status); eq(2, st.progress.count)
        st = feed(def, st, pt(o, 3)); eq('done', st.status)
        eq(true, st.progress.reward_pending)
    end)
    it('wrong order, repeats, other players, other offers, other regions and other events are rejected', function()
        local o = surveyOffer()
        local def, st = accepted(o)
        eq(0, feed(def, st, pt(o, 2)).progress.count)
        eq(0, feed(def, st, pt(o, 3)).progress.count)
        eq(0, feed(def, st, pt(o, 1, OTHER)).progress.count)
        local p = pt(o, 1); p.offer_key = 'survey_other'
        eq(0, feed(def, st, p).progress.count)
        p = pt(o, 1); p.region_id = 'great_plains'
        eq(0, feed(def, st, p).progress.count)
        eq(0, feed(def, st, pt(o, 1), JT.BOUNTY_EVENT).progress.count)
        st = feed(def, st, pt(o, 1))
        eq(1, feed(def, st, pt(o, 1)).progress.count) -- re-fired point 1
    end)
    it('a disabled region with survey data yields no survey offer on the board', function()
        local before, flag = JT.DATA[DISABLED], regions.regions[DISABLED].enabled
        JT.registerRegion(DISABLED, { surveys = JT.DATA[REGION].surveys })
        local ok, err = pcall(function()
            eq(1, #JT.offers('survey', DISABLED))
            local types = { survey = { hooks = { offers = function(r) return JT.offers('survey', r) end } } }
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
