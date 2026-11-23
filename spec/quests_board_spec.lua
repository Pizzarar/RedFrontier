-- Run from repo root: `lua spec/quests_board_spec.lua` (or via tools/run-specs.py).
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local describe, it, eq, same = T.describe, T.it, T.eq, T.same
local B = dofile(here .. '../server/resources/[fh]/fh_quests/shared/board.lua')

local function offers(prefix, n)
    local t = {}
    for i = 1, n do t[i] = { key = prefix .. i, title = prefix .. ' #' .. i } end
    return t
end

local function lists()
    return { hunt_request = offers('hunt', 6), camp_clear = offers('camp', 2), bounty = offers('bounty', 4) }
end

local function ids(board)
    local t = {}
    for i, o in ipairs(board) do t[i] = o.id end
    return t
end

describe('quests board: determinism', function()
    it('same region + epoch + offers gives the identical board', function()
        same(ids(B.rotate('heartlands', 100, lists())), ids(B.rotate('heartlands', 100, lists())))
    end)
    it('input order of offers does not matter', function()
        local a = lists()
        local b = lists()
        local rev = {}
        for i = #b.hunt_request, 1, -1 do rev[#rev + 1] = b.hunt_request[i] end
        b.hunt_request = rev
        same(ids(B.rotate('heartlands', 7, a)), ids(B.rotate('heartlands', 7, b)))
    end)
    it('boards rotate: across 20 epochs more than one distinct board appears', function()
        local seen, n = {}, 0
        for e = 1, 20 do
            local k = table.concat(ids(B.rotate('heartlands', e, lists())), '|')
            if not seen[k] then seen[k] = true; n = n + 1 end
        end
        assert(n > 1, 'board never changed')
    end)
    it('different regions get their own boards', function()
        local a = table.concat(ids(B.rotate('heartlands', 5, lists())), '|')
        local diff = false
        for _, r in ipairs({ 'r2', 'r3', 'r4', 'r5' }) do
            local b = table.concat(ids(B.rotate(r, 5, lists())), '|'):gsub('^' .. r, 'heartlands')
            if b ~= a then diff = true end
        end
        assert(diff)
    end)
    it('hash and rng are stable known values', function()
        eq(2166136261, B.hash(''))
        eq(B.hash('heartlands:1'), B.hash('heartlands:1'))
        local r1, r2 = B.rng(42), B.rng(42)
        for _ = 1, 10 do eq(r1(7), r2(7)) end
    end)
    it('epoch buckets time by rotate_min', function()
        eq(0, B.epoch(3599, 60)); eq(1, B.epoch(3600, 60)); eq(2, B.epoch(7200)); eq(4, B.epoch(3600, 15))
    end)
end)

describe('quests board: count bounds and ids', function()
    it('always 3-5 offers when enough exist, across many epochs and regions', function()
        local sizes = {}
        for e = 0, 199 do
            for _, r in ipairs({ 'heartlands', 'other' }) do
                local n = #B.rotate(r, e, lists())
                assert(n >= 3 and n <= 5, 'size ' .. n)
                sizes[n] = true
            end
        end
        assert(sizes[3] and sizes[4] and sizes[5], 'every size 3..5 occurs')
    end)
    it('fewer offers than the minimum: all of them, never invented', function()
        eq(2, #B.rotate('heartlands', 1, { bounty = offers('b', 2) }))
        eq(0, #B.rotate('heartlands', 1, {}))
        eq(0, #B.rotate('heartlands', 1, nil))
    end)
    it('custom bounds are respected', function()
        for e = 1, 30 do
            local n = #B.rotate('heartlands', e, lists(), { min = 1, max = 2 })
            assert(n >= 1 and n <= 2)
        end
    end)
    it('ids are region:epoch:type:key, unique, and stable for the epoch', function()
        local b = B.rotate('heartlands', 9, lists(), { rotate_min = 60 })
        local seen = {}
        for _, o in ipairs(b) do
            eq('heartlands:9:' .. o.job_type .. ':' .. o.key, o.id)
            assert(not seen[o.id], 'duplicate id'); seen[o.id] = true
            eq('heartlands', o.region_id); eq(9, o.epoch); eq(10 * 3600, o.expires_at)
            assert(o.offer and o.offer.key == o.key)
        end
        eq(b[1].id, B.find(B.rotate('heartlands', 9, lists()), b[1].id).id)
        eq(nil, B.find(b, 'heartlands:8:bounty:bounty1'))
    end)
    it('duplicate keys and keyless offers are dropped', function()
        local b = B.rotate('heartlands', 1, { bounty = { { key = 'a' }, { key = 'a' }, { title = 'no key' }, 'junk' } })
        eq(1, #b); eq('a', b[1].key)
    end)
    it('job types interleave: with 3 types and 3+ offers no type appears twice', function()
        for e = 1, 50 do
            local b = B.rotate('heartlands', e, lists())
            local per = {}
            for i = 1, 3 do
                local jt = b[i].job_type
                assert(not per[jt], 'type repeated in first round'); per[jt] = true
            end
        end
    end)
end)

T.finish()
