-- Run from repo root: `lua spec/progression_cache_spec.lua`.
-- Drives FhProgressionCache with a fake DB whose reads snapshot the value, then yield (like MySQL.scalar.await),
-- so events can interleave while a load / re-read is suspended.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local res = here .. '../server/resources/[fh]/fh_progression/'
package.path = res .. 'shared/?.lua;' .. res .. 'server/?.lua;' .. package.path
local case = T.it
local logic = require('progression_logic')
local Cache = require('progression_cache')

local cfg = {
    tiers = { heartlands = { t2 = 100, t3 = 400 }, west = { t2 = 100, t3 = 400 } },
    unlocks = { t1_perk = { region_id = 'heartlands', min_tier = 1 }, t2_perk = { region_id = 'heartlands', min_tier = 2 } },
}

-- db[citizenid][region] = value | 'fail'; online[src] = citizenid
local function harness()
    local h = { db = {}, online = {}, emits = {}, reads = 0 }
    h.store = Cache.new({
        cfg = cfg,
        logic = logic,
        citizenOf = function(src) return h.online[src] end,
        emit = function(p) h.emits[#h.emits + 1] = p end,
        read = function(cid, region)
            h.reads = h.reads + 1
            local v = (h.db[cid] or {})[region]
            if coroutine.isyieldable() then coroutine.yield() end -- the await: value already read
            if v == 'fail' then return nil, 'db_error' end
            return v or 0
        end,
    })
    return h
end

-- Starts fn in a coroutine and runs it to its first yield.
local function start(fn)
    local co = coroutine.create(fn)
    assert(coroutine.resume(co))
    return co
end
local function finish(co)
    while coroutine.status(co) ~= 'dead' do assert(coroutine.resume(co)) end
end

case('loadAll reads every region, emits nothing, entry() serves the cache', function()
    local h = harness()
    h.online[1] = 'A'; h.db.A = { heartlands = 150, west = 5 }
    h.store.loadAll(1, 'A')
    T.same({ heartlands = 150, west = 5 }, h.store.peek(1).rep)
    T.eq(0, #h.emits)
    local n = h.reads
    T.eq(2, h.store.getTier(1, 'heartlands'))
    T.eq(n, h.reads, 'warm entry must not re-read')
end)

case('rep_changed with value crosses once; cold rep_changed loads without emitting', function()
    local h = harness()
    h.online[1] = 'A'; h.db.A = { heartlands = 90 }
    h.store.onRepChanged(1, 'A', 'heartlands', 90) -- cold
    T.eq(0, #h.emits); T.eq(90, h.store.peek(1).rep.heartlands)
    h.store.onRepChanged(1, 'A', 'heartlands', 110)
    T.eq(1, #h.emits); T.eq(1, h.emits[1].old); T.eq(2, h.emits[1].new)
    h.store.onRepChanged(1, 'A', 'heartlands', 120)
    T.eq(1, #h.emits)
end)

case('(a) rep_changed during a cold load: the stale load does not overwrite the newer value', function()
    local h = harness()
    h.online[1] = 'A'; h.db.A = { heartlands = 90 }
    local co = start(function() h.store.loadAll(1, 'A') end) -- read 90 for some region, suspended
    h.db.A.heartlands = 110
    h.store.onRepChanged(1, 'A', 'heartlands', 110) -- cold -> its own load (sync here) commits 110
    T.eq(110, h.store.peek(1).rep.heartlands)
    finish(co)
    T.eq(110, h.store.peek(1).rep.heartlands, 'stale load overwrote fresher rep')
end)

case('(a2) rep_changed on a warm entry while a reload is in flight: reload must not commit', function()
    local h = harness()
    h.online[1] = 'A'; h.db.A = { heartlands = 90 }
    h.store.loadAll(1, 'A')
    local co = start(function() h.store.loadAll(1, 'A') end) -- e.g. a PlayerLoaded reload reading 90
    h.store.onRepChanged(1, 'A', 'heartlands', 110)
    T.eq(1, #h.emits)
    finish(co)
    T.eq(110, h.store.peek(1).rep.heartlands)
end)

case('(b) drop / unload while loading: no resurrected entry', function()
    local h = harness()
    h.online[1] = 'A'; h.db.A = { heartlands = 90 }
    local co = start(function() h.store.loadAll(1, 'A') end)
    h.store.invalidate(1)
    finish(co)
    T.eq(nil, h.store.peek(1))
end)

case('(b2) character switched on src while loading: not committed, not returned', function()
    local h = harness()
    h.online[1] = 'A'; h.db.A = { heartlands = 500 }
    local got = 'unset'
    local co = start(function() got = h.store.loadAll(1, 'A') end)
    h.online[1] = 'B'
    finish(co)
    T.eq(nil, got); T.eq(nil, h.store.peek(1))
end)

case('older of two loads finishing last does not win', function()
    local h = harness()
    h.online[1] = 'A'; h.db.A = { heartlands = 90 }
    local old = start(function() h.store.loadAll(1, 'A') end)
    h.db.A.heartlands = 300
    local new = start(function() h.store.loadAll(1, 'A') end)
    finish(new)
    finish(old)
    T.eq(300, h.store.peek(1).rep.heartlands)
end)

case('(c) re-read (value nil) overtaken by a newer change: no stale overwrite, no double emit', function()
    local h = harness()
    h.online[1] = 'A'; h.db.A = { heartlands = 90 }
    h.store.loadAll(1, 'A')
    h.db.A.heartlands = 95
    local co = start(function() h.store.onRepChanged(1, 'A', 'heartlands', nil) end) -- read 95, suspended
    h.store.onRepChanged(1, 'A', 'heartlands', 110)
    T.eq(1, #h.emits)
    finish(co)
    T.eq(110, h.store.peek(1).rep.heartlands)
    T.eq(1, #h.emits, 'stale re-read emitted again')
end)

case('(c2) re-read is not dropped by a change to a different region', function()
    local h = harness()
    h.online[1] = 'A'; h.db.A = { heartlands = 90, west = 0 }
    h.store.loadAll(1, 'A')
    h.db.A.heartlands = 150
    local co = start(function() h.store.onRepChanged(1, 'A', 'heartlands', nil) end)
    h.store.onRepChanged(1, 'A', 'west', 5)
    finish(co)
    T.eq(150, h.store.peek(1).rep.heartlands)
    T.eq(5, h.store.peek(1).rep.west)
    T.eq(1, #h.emits); T.eq('heartlands', h.emits[1].region_id); T.eq(2, h.emits[1].new)
end)

case('(c3) re-read after drop: nothing applied, nothing emitted', function()
    local h = harness()
    h.online[1] = 'A'; h.db.A = { heartlands = 90 }
    h.store.loadAll(1, 'A')
    h.db.A.heartlands = 150
    local e = h.store.peek(1)
    local co = start(function() h.store.onRepChanged(1, 'A', 'heartlands', nil) end)
    h.store.invalidate(1)
    finish(co)
    T.eq(nil, h.store.peek(1)); T.eq(90, e.rep.heartlands); T.eq(0, #h.emits)
end)

case('re-read failure keeps the old value, emits nothing, reloads on next access', function()
    local h = harness()
    h.online[1] = 'A'; h.db.A = { heartlands = 90 }
    h.store.loadAll(1, 'A')
    h.db.A.heartlands = 'fail'
    h.store.onRepChanged(1, 'A', 'heartlands', nil)
    T.eq(90, h.store.peek(1).rep.heartlands); T.eq(0, #h.emits)
    T.eq(false, h.store.peek(1).complete)
    h.db.A.heartlands = 150
    T.eq(150, h.store.getRep(1, 'heartlands'))
    T.eq(true, h.store.peek(1).complete)
end)

case('failed region read on load: incomplete, retried on next access', function()
    local h = harness()
    h.online[1] = 'A'; h.db.A = { heartlands = 'fail', west = 3 }
    h.store.loadAll(1, 'A')
    T.eq(false, h.store.peek(1).complete); T.eq(nil, h.store.peek(1).rep.heartlands)
    h.db.A.heartlands = 400
    T.eq(3, h.store.getTier(1, 'heartlands'))
end)

case('entry reloads when src now has a different character', function()
    local h = harness()
    h.online[1] = 'A'; h.db.A = { heartlands = 500 }; h.db.B = { heartlands = 0 }
    h.store.loadAll(1, 'A')
    h.online[1] = 'B'
    T.eq(1, h.store.getTier(1, 'heartlands'))
    T.eq('B', h.store.peek(1).citizenid)
end)

case('canUnlock: no character -> no_player, even for a min_tier 1 unlock', function()
    local h = harness()
    for _, src in ipairs({ 7, 'x' }) do
        local ok, why = h.store.canUnlock(src, 't1_perk')
        T.eq(false, ok); T.eq('no_player', why)
    end
    local nok, nwhy = h.store.canUnlock(nil, 't1_perk')
    T.eq(false, nok); T.eq('no_player', nwhy)
    h.online[1] = 'A'; h.db.A = { heartlands = 0 }
    T.eq(true, (h.store.canUnlock(1, 't1_perk')))
    local ok, why = h.store.canUnlock(1, 't2_perk')
    T.eq(false, ok); T.eq('tier_too_low', why)
    T.eq(0, h.store.getRep(7, 'heartlands')); T.eq(1, h.store.getTier(7, 'heartlands'))
end)

T.finish()
