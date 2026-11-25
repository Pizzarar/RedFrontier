-- Run from repo root: `lua spec/quests_rescue_spec.lua` (or via tools/run-specs.py).
-- quests-02 C4: the rescue job type (shared/jobtypes/rescue.lua): offers, the clear-then-reach rule (a camp_cleared
-- for the linked camp listing the holder, after accept, unlocks the captive; reaching it frees it), the lost rule
-- (escort's, captive dead / despawned -> fail), who is polled, no watch-entry leak, and the region gate.
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
local ROOT = here .. '../server/resources/[fh]/'

local function read(path)
    local h = assert(io.open(path, 'r'))
    local s = h:read('a')
    h:close()
    return s
end

local function events()
    local set = { [JT.CAPTIVE_FREED] = true, [JT.CAPTIVE_LOST] = true }
    for _, name in ipairs(E.INTAKE) do set[name] = true end
    return set
end

local function rescueOffer()
    local o = JT.offers('rescue', REGION)[1]
    assert(o, 'heartlands has a rescue template')
    return o
end

local function accepted(offer, cid)
    local snap = assert(Jobs.snapshot('rescue', offer, REGION, true))
    local def = assert(Jobs.def(snap, { regions = regions.regions, events = events() }))
    local st = assert(E.start(def, {}, cid or ME, T0))
    st.progress.job = snap
    return def, st
end

local function feed(def, st, name, payload)
    local hook = function(n, p, s) return JT.verdict('rescue', n, p, s) end
    local changes = I.feed({ [def.id] = def }, { [def.id] = st }, name, payload, T0, function() return hook end)
    return changes[1] and changes[1].after or st
end

local function ev(offer, cid)
    return { citizenid = cid or ME, offer_key = offer.key, region_id = REGION }
end

-- An armed rescue entry (server onArm runs JT.rescueArm) whose row has been seen active, unless `pending`.
local function entryFor(offer, cid, src, pending)
    local e = assert(WR.entry('rescue', { cid = cid or ME, src = src or 1, qid = Jobs.questId('rescue', offer.key),
        offer_key = offer.key, region_id = REGION }, offer, 0))
    assert(JT.rescueArm(e, offer))
    if not pending then e.pending = nil end
    return e
end

local function cleared(offer, participants, camp)
    return { camp_id = camp or offer.camp, region_id = REGION, loot = {}, participants = participants }
end

-- One reach-watcher tick for `watch` with the holder at `holder` (live captive at its spawn point unless given;
-- pass false for "no live captive", as server posOf does when the entity is missing or dead).
local function tickAt(watch, holder, captive)
    return WR.tick(watch, function(e)
        local c = captive
        if c == nil then c = e.points[1] elseif c == false then c = nil end
        return JT.rescuePos(e, holder, c)
    end)
end

local function st(status, count) return { status = status, progress = { count = count } } end
local ADOPTED = { state = 'adopted', netId = 7 }

describe('quests rescue: offers', function()
    it('heartlands rescue offer: 1-point watched job at the captive, linked to a real fh_zones camp', function()
        local o = rescueOffer()
        eq('rescue_ada_brennan', o.key)
        eq(JT.CAPTIVE_FREED, o.on)
        eq(1, o.count)
        eq('heartlands_t1_01', o.camp)
        eq('string', type(o.model)); eq('table', type(o.coords))
        same({ money = 34, rep = { region_id = REGION, delta = 3 } }, o.rewards)
        eq(true, WR.isWatched('rescue'))
        eq(JT.CAPTIVE_FREED, WR.eventOf('rescue'))
        local e = entryFor(o)
        eq(1, #e.points); same(o.coords, e.points[1])
        eq(JT.RESCUE_RADIUS, e.radius)
        eq(1, accepted(o).steps[1].count)
    end)
    it('every rescue camp id in the region data is an fh_zones camp id of the same region', function()
        local cfg = read(ROOT .. 'fh_zones/config.lua')
        local n = 0
        for region_id, d in pairs(JT.DATA) do
            for _, r in ipairs(d.rescues or {}) do
                n = n + 1
                assert(cfg:find("id = '" .. r.camp .. "'", 1, true), r.camp .. ' is not an fh_zones camp id')
                eq(region_id, r.camp:match('^(.-)_t%d+_%d+$'), r.camp)
            end
        end
        assert(n >= 1, 'at least one rescue template')
    end)
    it('a template without camp, coords or model yields no offer', function()
        local before = JT.DATA[DISABLED]
        local d = JT.DATA[REGION].rescues[1]
        local function without(k)
            local c = {}
            for kk, v in pairs(d) do c[kk] = v end
            c[k] = nil
            return c
        end
        JT.registerRegion(DISABLED, { rescues = { without('camp'), without('coords'), without('model') } })
        local n = #JT.offers('rescue', DISABLED)
        JT.registerRegion(DISABLED, before)
        eq(0, n)
    end)
    it('the builder reads the FhQuestsJobTypes global, never the chunk arg', function()
        local src = read(ROOT .. 'fh_quests/shared/jobtypes/rescue.lua')
        assert(src:find('local JT = FhQuestsJobTypes', 1, true))
        assert(not src:find('(...)', 1, true) and not src:find('or FhQuestsJobTypes', 1, true), 'rescue.lua reads the chunk arg')
    end)
    it('neither rescue event is a net event and both stay out of the shared intake whitelist', function()
        for _, name in ipairs(E.INTAKE) do
            assert(name ~= JT.CAPTIVE_FREED and name ~= JT.CAPTIVE_LOST, name)
        end
        for _, f in ipairs({ 'server/watch.lua', 'server/jobtypes.lua', 'shared/jobtypes/rescue.lua' }) do
            local src = read(ROOT .. 'fh_quests/' .. f)
            for _, name in ipairs({ 'captive_freed', 'captive_lost' }) do
                assert(not src:find("RegisterNetEvent%(%s*'fh:quests:" .. name), f .. ' registers ' .. name)
                assert(not src:find("TriggerServerEvent%(%s*'fh:quests:" .. name), f .. ' sends ' .. name)
                assert(not src:find("TriggerClientEvent%(%s*'fh:quests:" .. name), f .. ' sends ' .. name)
            end
            assert(not src:find("RegisterNetEvent%(%s*'fh:zones:camp_cleared"), f .. ' makes camp_cleared a net event')
        end
    end)
end)

describe('quests rescue: verdicts', function()
    it('freed completes with one reward; lost fails with none', function()
        local o = rescueOffer()
        local def, s = accepted(o)
        local done = feed(def, s, JT.CAPTIVE_FREED, ev(o))
        eq('done', done.status); eq(true, done.progress.reward_pending)
        def, s = accepted(o)
        local failed = feed(def, s, JT.CAPTIVE_LOST, ev(o))
        eq('failed', failed.status); eq(nil, failed.progress.reward_pending)
    end)
    it('other players, offers, regions and events change nothing (a camp clear alone never completes)', function()
        local o = rescueOffer()
        local def, s = accepted(o)
        for _, name in ipairs({ JT.CAPTIVE_FREED, JT.CAPTIVE_LOST }) do
            eq('active', feed(def, s, name, ev(o, OTHER)).status)
            local p = ev(o); p.offer_key = 'rescue_other'
            eq('active', feed(def, s, name, p).status)
            p = ev(o); p.region_id = 'great_plains'
            eq('active', feed(def, s, name, p).status)
        end
        eq('active', feed(def, s, JT.CAMP_CLEARED, cleared(o, { ME })).status)
        eq('active', feed(def, s, JT.ESCORT_ARRIVED, ev(o)).status)
        eq('active', feed(def, s, WR.POINT_EVENT, { citizenid = ME, offer_key = o.key, region_id = REGION,
            point = 1 }).status)
    end)
    it('the freed payload of the watch kind is exactly what the verdict accepts', function()
        local o = rescueOffer()
        local e = entryFor(o)
        same(ev(o), WR.payload(e, 1))
        local def, s = accepted(o)
        eq('done', feed(def, s, WR.eventOf('rescue'), WR.payload(e, 1)).status)
        eq('failed', feed(def, s, JT.CAPTIVE_LOST, JT.rescuePayload(e)).status)
    end)
end)

describe('quests rescue: clear, then reach', function()
    it('reaching the captive before the clear does nothing (and is not remembered)', function()
        local o = rescueOffer()
        local watch = { a = entryFor(o) }
        for _ = 1, 3 do eq(0, #tickAt(watch, o.coords)) end
        eq(false, WR.finished(watch.a))
        same({ 'a' }, JT.rescueOnCampCleared(watch, cleared(o, { ME })))
        eq(0, #tickAt(watch, { x = o.coords.x + 200, y = o.coords.y })) -- cleared but away: still nothing
        local hits = tickAt(watch, o.coords)
        eq(1, #hits); eq(true, hits[1].last); eq(1, hits[1].point)
    end)
    it('a clear lists the holder: unlocked; reach within RESCUE_RADIUS of the captive frees it', function()
        local o = rescueOffer()
        local c = o.coords
        local e = entryFor(o)
        JT.rescueOnCampCleared({ a = e }, cleared(o, { OTHER, ME }))
        eq(true, e.cleared)
        eq(nil, JT.rescuePos(e, { x = c.x + JT.RESCUE_RADIUS + 1, y = c.y }, c))
        same(c, JT.rescuePos(e, { x = c.x + 3, y = c.y - 2 }, c))
        -- the captive was knocked 30 m away: the holder must reach it, not its spawn point
        local moved = { x = c.x + 30, y = c.y }
        eq(nil, JT.rescuePos(e, c, moved))
        same(c, JT.rescuePos(e, { x = c.x + 31, y = c.y }, moved))
    end)
    it('a clear by non-participants only does not count', function()
        local o = rescueOffer()
        local watch = { a = entryFor(o) }
        same({}, JT.rescueOnCampCleared(watch, cleared(o, { OTHER })))
        same({}, JT.rescueOnCampCleared(watch, cleared(o, {})))
        same({}, JT.rescueOnCampCleared(watch, cleared(o, nil)))
        same({}, JT.rescueOnCampCleared(watch, cleared(o, 'ABC123')))
        eq(false, watch.a.cleared)
        eq(0, #tickAt(watch, o.coords))
    end)
    it('a clear of another camp, or a malformed payload, does not count', function()
        local o = rescueOffer()
        local watch = { a = entryFor(o) }
        same({}, JT.rescueOnCampCleared(watch, cleared(o, { ME }, 'heartlands_t1_02')))
        same({}, JT.rescueOnCampCleared(watch, nil))
        same({}, JT.rescueOnCampCleared(watch, { participants = { ME } }))
        eq(0, #tickAt(watch, o.coords))
    end)
    it('a clear before accept does not count: only entries armed when the clear arrives unlock', function()
        local o = rescueOffer()
        local watch = {}
        same({}, JT.rescueOnCampCleared(watch, cleared(o, { ME }))) -- cleared, then accepted
        watch.a = entryFor(o)
        eq(0, #tickAt(watch, o.coords))
    end)
    it('a re-arm (relog / restart) starts locked again: it needs a fresh clear', function()
        local o = rescueOffer()
        local e = entryFor(o)
        JT.rescueOnCampCleared({ a = e }, cleared(o, { ME }))
        local again = entryFor(o)
        eq(false, again.cleared)
        eq(0, #tickAt({ a = again }, o.coords))
    end)
    it('one clear unlocks every listed holder of that camp, and only the rescue entries', function()
        local o = rescueOffer()
        local survey = assert(WR.entry('survey', { cid = ME, src = 3, qid = 'job:survey:s', offer_key = 's',
            region_id = REGION }, JT.offers('survey', REGION)[1], 0))
        local watch = { a = entryFor(o, ME, 1), b = entryFor(o, OTHER, 2), c = entryFor(o, 'NOPE', 4), s = survey }
        same({ 'a', 'b' }, JT.rescueOnCampCleared(watch, cleared(o, { ME, OTHER })))
        eq(nil, survey.cleared)
        eq(false, watch.c.cleared)
    end)
    it('tick: locked entries are polled but yield nothing; a lost entry is never freed', function()
        local o = rescueOffer()
        local e = entryFor(o)
        JT.rescueOnCampCleared({ a = e }, cleared(o, { ME }))
        e.lost = true
        eq(nil, JT.rescuePos(e, o.coords, o.coords))
        eq(0, #tickAt({ a = e }, o.coords))
        e.cleared = false
        same({}, JT.rescueOnCampCleared({ a = e }, cleared(o, { ME }))) -- lost: not re-unlocked
    end)
end)

describe('quests rescue: captive lost (escort rule)', function()
    it('a captive whose spawn failed can never be freed, even unlocked and reached; the lost check fails it', function()
        local o = rescueOffer()
        local e = entryFor(o)
        JT.rescueOnCampCleared({ a = e }, cleared(o, { ME }))
        e.spawnFailed = true
        eq(nil, JT.rescuePos(e, o.coords, o.coords))
        eq(0, #tickAt({ a = e }, o.coords))
        eq(0, #tickAt({ a = e }, o.coords, false))
        local lost = JT.rescueCollectLost({ a = e }, function() return { spawn = { state = 'pending' }, failed = true } end)
        eq(1, #lost); eq(true, e.lost)
    end)
    it('a despawned captive within the lost grace cannot be freed, then fails', function()
        local o = rescueOffer()
        local e = entryFor(o)
        JT.rescueOnCampCleared({ a = e }, cleared(o, { ME }))
        local watch = { a = e }
        local missing = function() return { spawn = ADOPTED, exists = false } end
        -- reach ticks run before the lost check: with no live captive (posOf passes nil) nothing is freed
        for _ = 1, JT.ESCORT_LOST_TICKS - 1 do
            eq(0, #tickAt(watch, o.coords, false))
            eq(0, #JT.rescueCollectLost(watch, missing)) -- grace: wait
        end
        eq(0, #tickAt(watch, o.coords, false))
        eq(nil, JT.rescuePos(e, o.coords, nil))
        local lost = JT.rescueCollectLost(watch, missing)
        eq(1, #lost); eq(true, e.lost)
        eq(false, WR.finished(e))
        local def, s = accepted(o)
        eq('failed', feed(def, s, JT.CAPTIVE_LOST, JT.rescuePayload(e)).status)
    end)
    it('server posOf reads no captive spot fallback: missing / dead entity or spawnFailed -> nil', function()
        local src = read(ROOT .. 'fh_quests/server/watch.lua')
        local section = src:sub((src:find('-- ================================================================ rescue', 1, true)))
        assert(section:find('if not e.cleared or e.spawnFailed then return nil end', 1, true))
        assert(section:find('if not ent or GetEntityHealth(ent) <= 0 then return nil end', 1, true))
    end)
    it('dead or despawned before freed: lost -> the fail event, reported again until the row leaves active', function()
        local o = rescueOffer()
        local watch = { a = entryFor(o, ME, 1), b = entryFor(o, OTHER, 2) }
        local lost = JT.rescueCollectLost(watch, function(e)
            if e.src == 1 then return { spawn = ADOPTED, exists = true, dead = true } end
            return { spawn = ADOPTED, exists = true }
        end)
        eq(1, #lost); eq('a', lost[1].key); eq(true, watch.a.lost)
        eq(1, #JT.rescueCollectLost(watch, function() return { spawn = ADOPTED, exists = true } end))
        eq('failed', feed(select(1, accepted(o)), select(2, accepted(o)), JT.CAPTIVE_LOST,
            JT.rescuePayload(watch.a)).status)
        eq('drop', WR.heal(watch.a, st('failed', 0)))
        local gone = entryFor(o)
        eq('lost', JT.escortObserve(gone, { spawn = { state = 'despawned' } }))
    end)
    it('checks only rescue entries that are not pending or freed, once each; escort entries are not touched', function()
        local o = rescueOffer()
        local eo = JT.offers('escort', REGION)[1]
        local esc = assert(WR.entry('escort', { cid = ME, src = 9, qid = 'job:escort:x', offer_key = eo.key,
            region_id = REGION }, eo, 0))
        esc.pending = nil
        local freed = entryFor(o, 'FREED', 4); WR.mark(freed, 1)
        local watch = { a = entryFor(o, ME, 1), p = entryFor(o, 'PEND', 5, true), f = freed, e = esc }
        local asked = {}
        JT.rescueCollectLost(watch, function(e)
            asked[e.src] = (asked[e.src] or 0) + 1
            return { spawn = nil }
        end)
        same({ [1] = 1 }, asked)
        eq(nil, esc.lost)
        -- and escort's own check still ignores rescue entries
        asked = {}
        JT.escortCollectLost({ a = entryFor(o) }, function(e) asked[e.src] = true; return { spawn = nil } end)
        same({}, asked)
    end)
    it('a freed captive killed afterwards does not fail the job', function()
        local o = rescueOffer()
        local e = entryFor(o)
        WR.mark(e, 1)
        eq(0, #JT.rescueCollectLost({ a = e }, function() return { spawn = ADOPTED, exists = true, dead = true } end))
    end)
end)

describe('quests rescue: the 1-point job cannot leak a watch entry', function()
    it('pending is never polled; unlocked + freed + done row drops it', function()
        local o = rescueOffer()
        local e = entryFor(o, ME, 1, true)
        JT.rescueOnCampCleared({ k = e }, cleared(o, { ME })) -- clear while the accept commits: post-accept, counts
        local asked = 0
        eq(0, #WR.tick({ k = e }, function() asked = asked + 1; return o.coords end))
        eq(0, asked)
        eq('keep', WR.heal(e, st('done', 0))) -- the previous run's done row while accept commits
        eq('keep', WR.heal(e, st('active', 0)))
        local hits = tickAt({ k = e }, o.coords)
        eq(1, #hits); eq(true, hits[1].last)
        eq(0, #WR.tick({ k = e }, function() error('finished: never polled') end))
        eq('drop', WR.heal(e, st('done', 1)))
    end)
    it('a locked entry whose row is abandoned / failed elsewhere drops; a never-active pending one drops too', function()
        local o = rescueOffer()
        eq('drop', WR.heal(entryFor(o), st('failed', 0)))
        eq('drop', WR.heal(entryFor(o), st('abandoned', 0)))
        local p = entryFor(o, ME, 1, true)
        for _ = 1, WR.PENDING_TICKS do eq('keep', WR.heal(p, nil)) end
        eq('drop', WR.heal(p, nil))
    end)
    it('freed never credited rolls back so the captive can be reached again (still unlocked)', function()
        local o = rescueOffer()
        local e = entryFor(o)
        JT.rescueOnCampCleared({ a = e }, cleared(o, { ME }))
        eq(1, #tickAt({ a = e }, o.coords))
        for _ = 1, WR.HEAL_TICKS do WR.heal(e, st('active', 0)) end
        eq(false, WR.finished(e))
        eq(1, #tickAt({ a = e }, o.coords))
    end)
    it('server/watch.lua: the rescue section despawns on every disarm and stays separate from escort', function()
        local src = read(ROOT .. 'fh_quests/server/watch.lua')
        local esc = src:find('-- ================================================================ escort', 1, true)
        local res = src:find('-- ================================================================ rescue', 1, true)
        assert(esc and res and res > esc, 'rescue has its own section after escort')
        local section = src:sub(res)
        assert(section:find('kind.onDisarm', 1, true) and section:find('despawnReq(e.reqId)', 1, true))
        assert(section:find('AddEventHandler(JT.CAMP_CLEARED', 1, true))
        assert(not src:sub(esc, res - 1):find('rescue', 1, true), 'escort section mentions rescue')
        assert(read(ROOT .. 'fh_quests/server/jobtypes.lua'):find('rescueHooks', 1, true))
    end)
end)

describe('quests rescue: region gate', function()
    it('a disabled region with rescue data yields no rescue offer on the board; enabling shows it', function()
        local before, flag = JT.DATA[DISABLED], regions.regions[DISABLED].enabled
        JT.registerRegion(DISABLED, { rescues = JT.DATA[REGION].rescues })
        local ok, err = pcall(function()
            eq(1, #JT.offers('rescue', DISABLED))
            local types = { rescue = { hooks = { offers = function(r) return JT.offers('rescue', r) end } } }
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
