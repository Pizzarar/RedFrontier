-- Run from repo root: `lua spec/hunting_sell_spec.lua` (or via tools/run-specs.py).
-- The real trapper decision (shared/sell.lua) with fake exports: payout per star and legendary, validation rejects,
-- remove-before-pay, refund on pay failure, no double pay, the pelt_sold event.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local describe, it, eq, same = T.describe, T.it, T.eq, T.same
local base = here .. '../server/resources/[fh]/fh_hunting/'
local cfg = dofile(base .. 'config.lua')
local A = dofile(base .. 'shared/animals.lua')
local P = dofile(base .. 'shared/price.lua')
FhHuntingWagon = dofile(base .. 'shared/wagon.lua') -- the shared xyz reader sell.lua uses
local S = dofile(base .. 'shared/sell.lua')

local SRC, CID = 7, 'CID123'
local BAG = { type = 'saddlebag', id = 'fh:saddle:' .. CID }

-- A world: player at the trapper, a saddlebag holding `items` (slot -> item). Override with `w`.
local function world(w)
    w = w or {}
    local W = {
        player = { x = cfg.Trapper.coords.x, y = cfg.Trapper.coords.y, z = cfg.Trapper.coords.z },
        items = { [1] = { name = 'pelt_deer', amount = 1, info = { stars = 3 } } },
        bag = BAG, wagon = nil,
        calls = {},          -- ordered log of 'remove' / 'pay' / 'add'
        pays = {}, removes = {}, adds = {}, events = {},
        payOk = true, removeOk = true,
    }
    for k, v in pairs(w) do W[k] = v end
    W.deps = {
        citizenid = function(src) return src == SRC and CID or nil end,
        playerCoords = function() return W.player end,
        refFor = function(kind) if kind == 'saddlebag' then return W.bag end return W.wagon end,
        snapshot = function(ref)
            if ref == W.bag or ref == W.wagon then return W.items end
            return nil
        end,
        removeItem = function(ref, name, n, slot)
            W.calls[#W.calls + 1] = 'remove'
            W.removes[#W.removes + 1] = { ref = ref, name = name, n = n, slot = slot }
            if not W.removeOk then return false end
            local it = W.items[slot]
            if not it or it.name ~= name then return false end
            W.items[slot] = nil
            return true
        end,
        addItem = function(ref, name, n, info)
            W.calls[#W.calls + 1] = 'add'
            W.adds[#W.adds + 1] = { ref = ref, name = name, n = n, info = info }
            return true
        end,
        pay = function(src, amount, reason, region)
            W.calls[#W.calls + 1] = 'pay'
            W.pays[#W.pays + 1] = { src = src, amount = amount, reason = reason, region = region }
            return W.payOk
        end,
        emit = function(name, payload) W.events[#W.events + 1] = { name = name, payload = payload } end,
    }
    W.t = S.new({ cfg = cfg, animals = A, price = P, deps = W.deps })
    W.sell = function(p) return W.t.sell(SRC, p or { container = 'saddlebag', slot = 1, item = 'pelt_deer' }) end
    return W
end

local function pelt(name, stars) return { name = name, amount = 1, info = { stars = stars } } end

describe('hunting sell: payout math', function()
    it('pays base x star multiplier through pay(src, amount, hunting:pelt, region)', function()
        local expect = { [1] = 6, [2] = 14, [3] = 25 } -- deer base 14: 5.6, 14, 25.2
        for stars, amount in pairs(expect) do
            local W = world({ items = { [1] = pelt('pelt_deer', stars) } })
            local ok, res = W.sell()
            eq(true, ok)
            eq(amount, res.price)
            same({ { src = SRC, amount = amount, reason = 'hunting:pelt', region = cfg.Trapper.region_id } }, W.pays)
        end
    end)
    it('a 3 star pelt pays more than a 1 star pelt of the same animal', function()
        local W1 = world({ items = { [1] = pelt('pelt_bear', 1) } })
        local W3 = world({ items = { [1] = pelt('pelt_bear', 3) } })
        local _, r1 = W1.sell({ container = 'saddlebag', slot = 1, item = 'pelt_bear' })
        local _, r3 = W3.sell({ container = 'saddlebag', slot = 1, item = 'pelt_bear' })
        eq(18, r1.price)  -- 45 x 0.4
        eq(81, r3.price)  -- 45 x 1.8
    end)
    it('legendary bear pelt is 3 stars x 4 whatever the item info says', function()
        local W = world({ items = { [1] = pelt('pelt_legendary_bear', 1) } })
        local ok, res = W.sell({ container = 'saddlebag', slot = 1, item = 'pelt_legendary_bear' })
        eq(true, ok)
        eq(432, res.price) -- 60 x 1.8 x 4
        eq(3, res.stars)
    end)
    it('follows the configured multipliers', function()
        local c = {}
        for k, v in pairs(cfg) do c[k] = v end
        c.QualityMult = { [1] = 1, [2] = 2, [3] = 3 }
        local W = world()
        W.t = S.new({ cfg = c, animals = A, price = P, deps = W.deps })
        local ok, res = W.t.sell(SRC, { container = 'saddlebag', slot = 1, item = 'pelt_deer' })
        eq(true, ok)
        eq(42, res.price)
    end)
end)

describe('hunting sell: ordering, event, no double pay', function()
    it('removes the item before paying, then emits pelt_sold with the full payload', function()
        local W = world()
        eq(true, (W.sell()))
        same({ 'remove', 'pay' }, W.calls)
        eq(1, #W.events)
        eq('fh:hunting:pelt_sold', W.events[1].name)
        same({ citizenid = CID, item_id = 'pelt_deer', animal = 'deer', size_class = 'bulky', quality = 3, price = 25,
            region_id = cfg.Trapper.region_id }, W.events[1].payload)
    end)
    it('selling the same slot twice pays once', function()
        local W = world()
        eq(true, (W.sell()))
        local ok, err = W.sell()
        eq(false, ok); eq('fh_no_item', err)
        eq(1, #W.pays)
    end)
    it('a sale in flight blocks a second one (busy), then releases', function()
        local W = world()
        local inner
        local realPay = W.deps.pay
        W.deps.pay = function(...)
            inner = { W.sell() }
            return realPay(...)
        end
        W.t = S.new({ cfg = cfg, animals = A, price = P, deps = W.deps })
        eq(true, (W.t.sell(SRC, { container = 'saddlebag', slot = 1, item = 'pelt_deer' })))
        eq(false, inner[1]); eq('fh_busy', inner[2])
        eq(1, #W.pays)
        W.items[1] = pelt('pelt_deer', 2)
        eq(true, (W.t.sell(SRC, { container = 'saddlebag', slot = 1, item = 'pelt_deer' })))
    end)
    it('a failed payout puts the pelt back with its info and emits nothing', function()
        local W = world({ payOk = false })
        local ok, err = W.sell()
        eq(false, ok); eq('fh_pay_failed', err)
        same({ 'remove', 'pay', 'add' }, W.calls)
        eq('pelt_deer', W.adds[1].name)
        same({ stars = 3 }, W.adds[1].info)
        eq(0, #W.events)
    end)
    it('a failed remove never pays', function()
        local W = world({ removeOk = false })
        local ok, err = W.sell()
        eq(false, ok); eq('fh_remove_failed', err)
        eq(0, #W.pays); eq(0, #W.events)
    end)
    it('when the container took a different slot, the payout follows the pelt that really left', function()
        local W = world({ items = { [1] = pelt('pelt_deer', 3), [2] = pelt('pelt_deer', 1) } })
        local real = W.deps.removeItem
        W.deps.removeItem = function(ref, name, n, slot)
            real(ref, name, n, 2) -- fh_core removes by name: it took slot 2, not the requested slot 1
            return true, { slot = 2, info = { stars = 1 } }
        end
        W.t = S.new({ cfg = cfg, animals = A, price = P, deps = W.deps })
        local ok, res = W.sell()
        eq(true, ok)
        eq(1, res.stars)
        eq(res.price, W.pays[1].amount)
        eq(1, W.events[1].payload.quality)
    end)
    it('an unpriceable pelt that was taken instead is put back and nothing is paid', function()
        local W = world({ items = { [1] = pelt('pelt_deer', 3), [2] = pelt('pelt_deer', 1) } })
        W.deps.removeItem = function() return true, { slot = 2, info = { stars = 9 } } end
        W.t = S.new({ cfg = cfg, animals = A, price = P, deps = W.deps })
        local ok, err = W.sell()
        eq(false, ok); eq('fh_bad_price', err)
        eq(0, #W.pays); eq(1, #W.adds)
    end)
    it('a throwing dep is contained and releases the lock', function()
        local W = world()
        local real = W.deps.snapshot
        W.deps.snapshot = function() error('boom') end
        W.t = S.new({ cfg = cfg, animals = A, price = P, deps = W.deps })
        local ok, err = W.t.sell(SRC, { container = 'saddlebag', slot = 1, item = 'pelt_deer' })
        eq(false, ok); eq('fh_error', err)
        W.deps.snapshot = real
        eq(true, (W.t.sell(SRC, { container = 'saddlebag', slot = 1, item = 'pelt_deer' })))
    end)
end)

describe('hunting sell: validation rejects (nothing removed, nothing paid)', function()
    local function rejected(w, payload, code)
        local W = world(w)
        local ok, err = W.sell(payload)
        eq(false, ok); eq(code, err)
        eq(0, #W.removes); eq(0, #W.pays); eq(0, #W.events)
    end
    it('unknown player', function()
        local W = world()
        local ok, err = W.t.sell(99, { container = 'saddlebag', slot = 1, item = 'pelt_deer' })
        eq(false, ok); eq('fh_no_player', err)
    end)
    it('out of range of the trapper', function()
        rejected({ player = { x = cfg.Trapper.coords.x + cfg.Trapper.SellRange + 1, y = cfg.Trapper.coords.y, z = cfg.Trapper.coords.z } },
            nil, 'fh_too_far')
    end)
    it('no server-side position', function() rejected({ player = false }, nil, 'fh_too_far') end)
    it('malformed requests', function()
        rejected(nil, 'nope', 'fh_bad_request')
        rejected(nil, { container = 'backpack', slot = 1, item = 'pelt_deer' }, 'fh_bad_request')
        rejected(nil, { container = 'saddlebag', slot = 1.5, item = 'pelt_deer' }, 'fh_bad_request')
        rejected(nil, { container = 'saddlebag', slot = 0, item = 'pelt_deer' }, 'fh_bad_request')
        rejected(nil, { container = 'saddlebag', slot = 1, item = "pelt_deer'; drop" }, 'fh_bad_request')
        rejected(nil, { container = 'saddlebag', slot = 1 }, 'fh_bad_request')
    end)
    it('no such container (no saddlebag / no wagon in range)', function()
        rejected({ bag = false }, nil, 'fh_no_container')
        rejected(nil, { container = 'wagon', slot = 1, item = 'pelt_deer' }, 'fh_no_container')
    end)
    it('empty slot, or the slot holds a different item than the UI showed', function()
        rejected({ items = {} }, nil, 'fh_no_item')
        rejected({ items = { [1] = pelt('pelt_fox', 2) } }, nil, 'fh_no_item')
    end)
    it('not a pelt: trophies and other items are not bought', function()
        rejected({ items = { [1] = { name = 'trophy_legendary_bear', amount = 1, info = { stars = 3 } } } },
            { container = 'saddlebag', slot = 1, item = 'trophy_legendary_bear' }, 'fh_not_pelt')
        rejected({ items = { [1] = { name = 'bread', amount = 1 } } },
            { container = 'saddlebag', slot = 1, item = 'bread' }, 'fh_not_pelt')
    end)
    it('bad quality: missing, zero, fractional or out of range stars', function()
        for _, info in ipairs({ {}, { stars = 0 }, { stars = 4 }, { stars = 2.5 }, { stars = '3' } }) do
            rejected({ items = { [1] = { name = 'pelt_deer', amount = 1, info = info } } }, nil, 'fh_bad_quality')
        end
        rejected({ items = { [1] = { name = 'pelt_deer', amount = 1 } } }, nil, 'fh_bad_quality')
    end)
    it('a zero payout is refused before anything is removed', function()
        local W = world({ items = { [1] = pelt('pelt_deer', 3) } })
        local a = A.byPelt.pelt_deer
        local oldValue = a.value
        a.value = 0
        local ok, err = W.sell()
        a.value = oldValue
        eq(false, ok); eq('fh_bad_price', err)
        eq(0, #W.removes)
    end)
end)

describe('hunting sell: wagon container and the UI list', function()
    it('sells from a wagon the adapter found', function()
        local WAG = { type = 'wagon', id = 'fh:wagon:5' }
        local W = world({ bag = false, wagon = WAG, items = { [2] = pelt('pelt_bison', 2) } })
        local ok, res = W.sell({ container = 'wagon', slot = 2, item = 'pelt_bison' })
        eq(true, ok); eq(40, res.price)
        same(WAG, W.removes[1].ref)
    end)
    it('list shows only sellable pelts with the same prices sell() pays', function()
        local W = world({ items = {
            [1] = pelt('pelt_deer', 3), [2] = { name = 'bread', amount = 1 }, [3] = pelt('pelt_fox', 1),
            [4] = { name = 'pelt_deer', amount = 1, info = { stars = 9 } } } })
        local rows = W.t.list(SRC)
        eq(2, #rows)
        eq('deer', rows[1].animal); eq(25, rows[1].price); eq(3, rows[1].stars)
        eq('fox', rows[2].animal); eq(3, rows[2].price)  -- 8 x 0.4 = 3.2
    end)
    it('list is refused away from the trapper', function()
        local W = world({ player = { x = 0, y = 0, z = 0 } })
        local rows, err = W.t.list(SRC)
        eq(nil, rows); eq('fh_too_far', err)
    end)
end)

-- A stand-in for a vector3 userdata: not type 'table'-comparable by shape, fields are read through a metatable.
local function vec(x, y, z)
    local data = { x = x, y = y, z = z }
    return setmetatable({}, { __index = data })
end

describe('hunting sell: vector3 coordinates (natives return vectors, not plain tables)', function()
    it('a vector-like player position at the trapper sells', function()
        local c = cfg.Trapper.coords
        local W = world({ player = vec(c.x, c.y, c.z) })
        eq(true, (W.sell()))
    end)
    it('a vector-like position out of range is refused, an unreadable one too', function()
        local c = cfg.Trapper.coords
        local W = world({ player = vec(c.x + 50, c.y, c.z) })
        local ok, err = W.sell(); eq(false, ok); eq('fh_too_far', err)
        W = world({ player = vec(nil, 1, 2) })
        ok, err = W.sell(); eq(false, ok); eq('fh_too_far', err)
    end)
    it('S.distance reads both shapes', function()
        eq(5, S.distance({ x = 0, y = 0, z = 0 }, vec(3, 4, 0)))
        eq(nil, S.distance(5, { x = 0, y = 0, z = 0 }))
    end)
end)

describe('hunting sell: values whose type() is vector3 (CfxLua 5.4 / LuaGLM)', function()
    -- Fake `type` returning 'vector3' for the marker, restored even on error.
    local function withVectorType(marker, fn)
        local real = type
        _G.type = function(v) if v == marker then return 'vector3' end return real(v) end
        local ok, err = pcall(fn)
        _G.type = real
        if not ok then error(err, 0) end
    end
    it('xyz and distance read it, and a sale at the trapper goes through', function()
        local c = cfg.Trapper.coords
        local marker = vec(c.x, c.y, c.z)
        withVectorType(marker, function()
            eq(c.x, (S.xyz(marker)))
            eq(0, S.distance(marker, c))
            local W = world({ player = marker })
            eq(true, (W.sell()))
        end)
    end)
    it('plain arrays and bad values', function()
        eq(3, select(3, S.xyz({ 1, 2, 3 })))
        eq(nil, S.xyz({ 1, 2 })); eq(nil, S.xyz('abc')); eq(nil, S.xyz(7)); eq(nil, S.xyz(true))
        eq(nil, S.xyz({ x = 1, y = 2, z = 0 / 0 }))
    end)
end)

T.finish()
