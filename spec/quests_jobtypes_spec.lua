-- Run from repo root: `lua spec/quests_jobtypes_spec.lua` (or via tools/run-specs.py).
-- fh_quests built-in job types (jobtypes.lua): offers are valid job offers, onEvent verdicts of hunt_request /
-- camp_clear / bounty end to end through intake.feed (credit rules included), and region rotation (3-5, deterministic).
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

local function events()
    local set = { [JT.BOUNTY_EVENT] = true, ['fh:quests:point_reached'] = true }
    for _, name in ipairs(E.INTAKE) do set[name] = true end
    return set
end

local function find(job_type, key)
    for _, o in ipairs(JT.offers(job_type, REGION)) do
        if o.key == key then return o end
    end
    error('no offer ' .. job_type .. ':' .. tostring(key))
end

-- Accept an offer the way api.lua does: snapshot -> def -> engine.start, progress.job = snapshot. Returns def, state.
local function accepted(job_type, offer, cid)
    local snap = assert(Jobs.snapshot(job_type, offer, REGION, true))
    local def = assert(Jobs.def(snap, { regions = regions.regions, events = events() }))
    local st = assert(E.start(def, {}, cid or ME, T0))
    st.progress.job = snap
    return def, st
end

-- Feed an event through the same router the server uses (engine.eligible, then the job type's verdict hook).
local function feed(job_type, def, st, name, payload)
    local hook = function(n, p, s) return JT.verdict(job_type, n, p, s) end
    local changes = I.feed({ [def.id] = def }, { [def.id] = st }, name, payload, T0, function() return hook end)
    return changes[1] and changes[1].after or st
end

describe('quests jobtypes: offers', function()
    it('every offer of every type passes snapshot + def validation (as a hook-driven job)', function()
        local n = 0
        for _, jt in ipairs(JT.TYPES) do
            for _, o in ipairs(JT.offers(jt, REGION)) do
                local snap = assert(Jobs.snapshot(jt, o, REGION, true), jt .. ':' .. o.key)
                local def, err = Jobs.def(snap, { regions = regions.regions, events = events() })
                assert(def, jt .. ':' .. o.key .. ' ' .. tostring(err))
                n = n + 1
            end
        end
        assert(n >= 5, 'enough templates for a 3-5 board')
    end)
    it('keys are unique per type and unknown regions / types give no offers', function()
        for _, jt in ipairs(JT.TYPES) do
            local seen = {}
            for _, o in ipairs(JT.offers(jt, REGION)) do
                eq(nil, seen[o.key], o.key)
                seen[o.key] = true
            end
        end
        same({}, JT.offers('hunt_request', 'nowhere'))
        same({}, JT.offers('freight', REGION))
    end)
    it('hunt_request: N-star pelt of animal X, animal required (Q0b landed)', function()
        local o = find('hunt_request', 'wolf_3star')
        eq('fh:hunting:pelt_sold', o.on)
        same({ min = 3 }, o.where.quality)
        same({ eq = 'wolf' }, o.where.animal)
    end)
    it('camp_clear names the camp; bounty carries its spawn setup for accept', function()
        eq('heartlands_t1_01', find('camp_clear', 'camp_heartlands_t1_01').where.camp_id)
        local b = find('bounty', 'bounty_silas_crow')
        eq(JT.BOUNTY_EVENT, b.on)
        eq('string', type(b.model)); eq('number', type(b.coords.x)); eq(REGION, b.region_id)
        eq('fh_quests:bounty:heartlands:bounty_silas_crow', JT.bountyTag(REGION, b.key))
    end)
end)

describe('quests jobtypes: hunt_request verdicts', function()
    local offer = find('hunt_request', 'wolf_3star')
    -- The real fh_hunting shared/sell.lua payload (deps.emit('fh:hunting:pelt_sold', ...)).
    local function sold(over)
        local p = { citizenid = ME, item_id = 'pelt_wolf', animal = 'wolf', size_class = 'bulky', quality = 3,
            price = 30, region_id = REGION }
        for k, v in pairs(over or {}) do p[k] = v end
        return p
    end
    local function run(payload, which)
        local def, st = accepted('hunt_request', which or offer)
        return feed('hunt_request', def, st, 'fh:hunting:pelt_sold', payload).status
    end
    it('right animal at or above N stars completes', function()
        eq('done', run(sold()))
        eq('done', run(sold({ item_id = 'pelt_deer', animal = 'deer', quality = 2, price = 14 }),
            find('hunt_request', 'deer_1star')))
    end)
    it('quality below N is ignored', function()
        eq('active', run(sold({ quality = 2 })))
    end)
    it('wrong animal never credits, even at full quality: the job stays active', function()
        local deer = find('hunt_request', 'deer_2star')
        eq('active', run(sold({ item_id = 'pelt_wolf', animal = 'wolf', quality = 3 }), deer))
        eq('active', run(sold({ item_id = 'pelt_deer', animal = 'deer' })))
        local def, st = accepted('hunt_request', deer)
        st = feed('hunt_request', def, st, 'fh:hunting:pelt_sold', sold({ quality = 3 }))
        eq('active', st.status)
        eq('done', feed('hunt_request', def, st, 'fh:hunting:pelt_sold',
            sold({ item_id = 'pelt_deer', animal = 'deer', quality = 2 })).status)
    end)
    it('a payload without animal no longer credits (animal is not optional)', function()
        local p = sold(); p.animal = nil
        eq('active', run(p))
    end)
    it('a missing quality never counts', function()
        local p = sold(); p.quality = nil
        eq('active', run(p))
    end)
    it('another citizen selling a pelt does not advance my job', function()
        eq('active', run(sold({ citizenid = OTHER })))
    end)
    it('another event or a bare onEvent call with the wrong job type does nothing', function()
        local def, st = accepted('hunt_request', offer)
        eq('active', feed('hunt_request', def, st, 'fh:hunting:pelt_skinned', { citizenid = ME, quality = 3 }).status)
        eq(nil, JT.verdict('camp_clear', 'fh:hunting:pelt_sold', { citizenid = ME, quality = 3 }, st))
        eq(nil, JT.verdict('hunt_request', 'fh:hunting:pelt_sold', { citizenid = ME, quality = 3 }, { citizenid = ME }))
    end)
end)

describe('quests jobtypes: camp_clear verdicts', function()
    local offer = find('camp_clear', 'camp_heartlands_t1_01')
    local function run(payload, cid)
        local def, st = accepted('camp_clear', offer, cid)
        return feed('camp_clear', def, st, 'fh:zones:camp_cleared', payload).status
    end
    local LOOT = { { name = 'bread', amount = 1 } }
    it('credits each participant in the real camp_cleared payload', function()
        eq('done', run({ camp_id = 'heartlands_t1_01', region_id = REGION, loot = LOOT,
            participants = { OTHER, ME } }))
    end)
    it('an empty participants table credits nobody and does not error', function()
        eq('active', run({ camp_id = 'heartlands_t1_01', region_id = REGION, loot = LOOT, participants = {} }))
    end)
    it('no participants field (an older emitter) credits nobody', function()
        eq('active', run({ camp_id = 'heartlands_t1_01', region_id = REGION, loot = LOOT }))
    end)
    it('a wrong citizen (not in participants) is ignored', function()
        eq('active', run({ camp_id = 'heartlands_t1_01', participants = { OTHER } }))
    end)
    it('another camp is ignored', function()
        eq('active', run({ camp_id = 'other_camp', participants = { ME } }))
    end)
    it('an explicit citizenid credits too', function()
        eq('done', run({ camp_id = 'heartlands_t1_01', citizenid = ME }))
    end)
end)

describe('quests jobtypes: bounty verdicts', function()
    local offer = find('bounty', 'bounty_silas_crow')
    local function run(payload, name)
        local def, st = accepted('bounty', offer)
        return feed('bounty', def, st, name or JT.BOUNTY_EVENT, payload).status
    end
    it('the acceptor is credited when their bounty goes down', function()
        eq('done', run({ citizenid = ME, offer_key = offer.key, region_id = REGION }))
    end)
    it('another offer key is ignored', function()
        eq('active', run({ citizenid = ME, offer_key = 'bounty_mabel_teague' }))
    end)
    it('only the acceptor: another citizenid, or the acceptor merely listed as a participant, is ignored', function()
        eq('active', run({ citizenid = OTHER, offer_key = offer.key }))
        eq('active', run({ citizenid = OTHER, offer_key = offer.key, participants = { ME } }))
    end)
    it('a different event never completes it', function()
        eq('active', run({ citizenid = ME, offer_key = offer.key }, 'fh:zones:camp_cleared'))
    end)
    it('a second player holding the same bounty is not credited by the first one\'s kill', function()
        local def, mine = accepted('bounty', offer, ME)
        local _, theirs = accepted('bounty', offer, OTHER)
        local p = { citizenid = ME, offer_key = offer.key }
        eq('done', feed('bounty', def, mine, JT.BOUNTY_EVENT, p).status)
        eq('active', feed('bounty', def, theirs, JT.BOUNTY_EVENT, p).status)
    end)
end)

describe('quests jobtypes: region rotation', function()
    local function lists(region)
        local l = {}
        for _, jt in ipairs(JT.TYPES) do l[jt] = JT.offers(jt, region) end
        return l
    end
    local function ids(board)
        local out = {}
        for i, o in ipairs(board) do out[i] = o.id end
        return out
    end
    it('3-5 offers per region on every epoch', function()
        for epoch = 490000, 490200 do
            local n = #B.rotate(REGION, epoch, lists(REGION), { rotate_min = 60 })
            assert(n >= 3 and n <= 5, ('epoch %d gave %d'):format(epoch, n))
        end
    end)
    it('the same region + epoch always gives the same board, whatever the offer order', function()
        local a = ids(B.rotate(REGION, 490123, lists(REGION)))
        local rev = lists(REGION)
        for _, list in pairs(rev) do
            for i = 1, #list // 2 do list[i], list[#list - i + 1] = list[#list - i + 1], list[i] end
        end
        same(a, ids(B.rotate(REGION, 490123, lists(REGION))))
        same(a, ids(B.rotate(REGION, 490123, rev)))
    end)
    it('the board changes as epochs roll over, and carries more than one job type', function()
        local seen, kinds = {}, {}
        for epoch = 490000, 490030 do
            local board = B.rotate(REGION, epoch, lists(REGION))
            seen[table.concat(ids(board), '|')] = true
            for _, o in ipairs(board) do kinds[o.job_type] = true end
        end
        local distinct = 0
        for _ in pairs(seen) do distinct = distinct + 1 end
        assert(distinct > 3, 'boards should vary across epochs')
        assert(kinds.hunt_request and kinds.camp_clear and kinds.bounty, 'every type shows up over time')
    end)
    it('offer ids are stable within an epoch and name the region and epoch', function()
        for _, o in ipairs(B.rotate(REGION, 490001, lists(REGION))) do
            assert(o.id:find('^heartlands:490001:' .. o.job_type .. ':'))
        end
    end)
end)

describe('quests jobtypes: bounty watch helpers', function()
    local function watchOf()
        return {
            ['t:b'] = { tag = 't:b', src = 2, cid = OTHER, key = 'k2' },
            ['t:a'] = { tag = 't:a', src = 1, cid = ME, key = 'k1' },
            ['t:c'] = { tag = 't:c', src = 1, cid = ME, key = 'k3' },
        }
    end
    it('collectDead returns a sorted snapshot, so the caller may mutate the watch afterwards', function()
        local watch = watchOf()
        local dead = JT.collectDead(watch, function(w) return w.tag ~= 't:c' end)
        same({ 't:a', 't:b' }, { dead[1].tag, dead[2].tag })
        watch['t:new'] = { tag = 't:new' } -- an accept inserting mid-fire cannot affect the snapshot
        watch['t:a'] = nil
        eq(2, #dead)
    end)
    it('collectDead skips an entry whose check throws and keeps the others', function()
        local dead = JT.collectDead(watchOf(), function(w) if w.tag == 't:a' then error('boom') end return true end)
        same({ 't:b', 't:c' }, { dead[1].tag, dead[2].tag })
    end)
    it('ownedBy finds only that player\'s bounties (owner left: despawn these, credit nobody)', function()
        local mine = JT.ownedBy(watchOf(), 1)
        same({ 't:a', 't:c' }, { mine[1].tag, mine[2].tag })
        eq(0, #JT.ownedBy(watchOf(), 99))
    end)
    it('bountyOffer rebuilds the spawn setup from region + key (re-arm after relog / restart)', function()
        local o = JT.bountyOffer(REGION, 'bounty_silas_crow')
        eq('bounty_silas_crow', o.key); eq('string', type(o.model)); eq('table', type(o.coords))
        eq(nil, JT.bountyOffer(REGION, 'bounty_nobody'))
        eq(nil, JT.bountyOffer('nowhere', 'bounty_silas_crow'))
    end)
end)

T.finish()
