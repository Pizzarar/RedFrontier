-- Run from repo root: `lua spec/fence_leads_spec.lua` (Lua 5.4: pcall must be yieldable).
-- Treasure lead dig (progression-02 G2): pure rules in fh_fence/shared/leads_logic.lua, and the real
-- fh_fence/server/leads.lua dig driven with fake fh_core / fh_economy deps that yield (like awaited exports), so
-- `interleave` can run two digs step by step.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local fence = here .. '../server/resources/[fh]/fh_fence/'
package.path = fence .. 'shared/?.lua;' .. fence .. 'server/?.lua;' .. package.path
local case = T.it
local logic = require('leads_logic')
local leads = require('leads')

assert(loadfile(fence .. 'config.lua'))()
local cfg = FhFenceConfig
local LEAD = cfg.leads.item
local ROAD = cfg.stock.heartlands_road.leads[1].lead          -- heartlands_road lead (coords + hint)
local CAMP = cfg.stock.heartlands_camp.leads[1].lead
local SPOT = { x = ROAD.coords.x, y = ROAD.coords.y, z = ROAD.coords.z }
local function info(l) return { target = { x = l.coords.x, y = l.coords.y, z = l.coords.z }, hint = l.hint } end

-- Seeded LCG with math.random's (m, n) contract: same seed = same sequence.
local function lcg(seed)
    local s = seed
    return function(m, n)
        s = (s * 1103515245 + 12345) % 2147483648
        return m + (s // 65536) % (n - m + 1)
    end
end

-- ---------------------------------------------------------------- pure rules

case('roll: config loot table is valid and under fh_economy maxPay', function()
    assert(loadfile(here .. '../server/resources/[fh]/fh_economy/config.lua'))()
    local maxPay = assert(FhEconomyConfig.maxPay)
    T.same({ true, n = 1 }, table.pack(logic.validLoot(cfg.leads.loot, maxPay)))
end)

case('roll: distribution follows the weights, money stays in range (seeded, 20000 rolls)', function()
    local loot = cfg.leads.loot
    local total, hits = 0, {}
    for i, e in ipairs(loot) do total = total + e.weight; hits[i] = 0 end
    local rng, N = lcg(12345), 20000
    for _ = 1, N do
        local r = assert(logic.roll(loot, rng))
        local e = loot[r.index]
        hits[r.index] = hits[r.index] + 1
        assert(r.money >= e.money[1] and r.money <= e.money[2] and r.money == math.floor(r.money), 'money range')
        T.eq(e.item, r.item); T.eq(e.item and e.qty or 0, r.qty)
    end
    for i, e in ipairs(loot) do
        local want = N * e.weight / total
        assert(math.abs(hits[i] - want) < want * 0.1, ('entry %d: %d hits, want ~%d'):format(i, hits[i], want))
    end
end)

case('roll: deterministic with a seeded rng', function()
    local a, b, c = lcg(42), lcg(42), lcg(43)
    local sa, sb, sc = {}, {}, {}
    for i = 1, 50 do
        sa[i] = logic.roll(cfg.leads.loot, a); sb[i] = logic.roll(cfg.leads.loot, b); sc[i] = logic.roll(cfg.leads.loot, c)
    end
    T.same(sa, sb)
    local differs = false
    for i = 1, 50 do if sa[i].money ~= sc[i].money or sa[i].index ~= sc[i].index then differs = true end end
    assert(differs, 'another seed gives another sequence')
end)

case('roll: picks by cumulative weight; fixed money skips the second rng call', function()
    local loot = { { weight = 1, money = { 5, 5 } }, { weight = 3, item = 'x', qty = 2 } }
    local calls = 0
    local function fixed(v) return function() calls = calls + 1; return v end end
    T.same({ index = 1, money = 5, qty = 0 }, logic.roll(loot, fixed(1)))
    T.eq(1, calls)
    T.same({ index = 2, money = 0, item = 'x', qty = 2 }, logic.roll(loot, fixed(2)))
    T.same({ index = 2, money = 0, item = 'x', qty = 2 }, logic.roll(loot, fixed(4)))
end)

case('roll: bad tables and bad rng are refused', function()
    T.eq(nil, (logic.roll({}, lcg(1))))
    T.eq(nil, (logic.roll({ { weight = 0, money = { 1, 2 } } }, lcg(1))))
    T.eq(nil, (logic.roll({ { weight = 1, money = { 3, 2 } } }, lcg(1))))
    T.eq(nil, (logic.roll({ { weight = 1 } }, lcg(1))))
    T.eq(nil, (logic.roll({ { weight = 1, item = 'x', qty = 0 } }, lcg(1))))
    T.same({ false, 'money_cap@1', n = 2 }, table.pack(logic.validLoot({ { weight = 1, money = { 1, 200 } } }, 100)))
    T.same({ nil, 'bad_rng', n = 2 }, table.pack(logic.roll(cfg.leads.loot, function() return 0 end)))
    T.same({ nil, 'bad_rng', n = 2 }, table.pack(logic.roll(cfg.leads.loot, function() return 1.5 end)))
end)

case('area: the spot is inside the circle, never its centre, and the centre is stable', function()
    for _, l in ipairs({ ROAD, CAMP }) do
        local t = info(l).target
        local a = logic.area(t, cfg.leads.areaRadius)
        local d = math.sqrt((a.x - t.x) ^ 2 + (a.y - t.y) ^ 2)
        assert(d >= cfg.leads.areaRadius * 0.25 - 1e-6 and d <= cfg.leads.areaRadius * 0.65 + 1e-6, 'offset ' .. d)
        assert(d + cfg.leads.digRadius <= cfg.leads.areaRadius, 'whole dig circle inside the area')
        T.same(a, logic.area(t, cfg.leads.areaRadius))
    end
end)

case('regionFor: stop region for a stock lead, config fallback otherwise', function()
    T.eq('heartlands', logic.regionFor(cfg, SPOT))
    T.eq(cfg.leads.regionId, logic.regionFor(cfg, { x = 1, y = 2, z = 3 }))
end)

-- ---------------------------------------------------------------- fake world

local function copy(t)
    if type(t) ~= 'table' then return t end
    local o = {}
    for k, v in pairs(t) do o[k] = copy(v) end
    return o
end

local function count(box, name)
    local n = 0
    for _, it in pairs(box) do if it.name == name then n = n + it.amount end end
    return n
end

---Players by citizenid: pos, money, sections equipped / backpack (slot -> item), room = backpack units left.
local function world(o)
    o = o or {}
    local W = {
        players = { C1 = { pos = copy(SPOT), money = 0, equipped = {}, backpack = {}, room = 10 } },
        srcs = { [1] = 'C1', [2] = 'C1' }, -- src 2 = C1 on a second connection (same character)
        fail = {}, hooks = {}, calls = {}, logs = {}, paid = {}, added = {}, clock = 1000,
        rngq = {},
    }
    for k, v in pairs(o) do W.players.C1[k] = v end
    local function P(src) return W.players[W.srcs[src]] end
    local function box(ref) return P(ref.id)[ref.type] end
    local function step(name, ...)
        if coroutine.isyieldable() then coroutine.yield(name) end
        W.calls[name] = (W.calls[name] or 0) + 1
        local h = W.hooks[name]
        if h then h(W, W.calls[name], ...) end
    end
    W.deps = {
        citizenOf = function(src) return W.srcs[src] end,
        pedCoords = function(src) step('pedCoords'); local p = P(src); return p and copy(p.pos) end,
        snapshot = function(ref)
            step('snapshot')
            if W.fail.snapshot then return nil, W.fail.snapshot end
            return copy(box(ref))
        end,
        canFit = function(ref, _, qty)
            step('canFit')
            if qty <= P(ref.id).room then return true end
            return false, 'fh_too_heavy'
        end,
        removeItem = function(ref, name, qty) -- fh_core: exactly qty or nothing
            step('removeItem')
            if W.fail.removeItem then return false, W.fail.removeItem end
            local b = box(ref)
            if count(b, name) < qty then return false, 'fh_not_enough' end
            for s, it in pairs(b) do
                if qty > 0 and it.name == name then
                    local n = math.min(qty, it.amount)
                    it.amount, qty = it.amount - n, qty - n
                    if it.amount == 0 then b[s] = nil end
                end
            end
            return true
        end,
        addItem = function(ref, name, qty, inf)
            step('addItem')
            if W.fail.addItem then return false, W.fail.addItem end
            local b = box(ref)
            b[#b + 100] = { name = name, amount = qty, info = inf }
            P(ref.id).room = P(ref.id).room - qty
            W.added[#W.added + 1] = { name = name, qty = qty }
            return true
        end,
        pay = function(src, amount, reason, region)
            step('pay')
            if W.fail.pay then return false, W.fail.pay end
            P(src).money = P(src).money + amount
            W.paid[#W.paid + 1] = { amount = amount, reason = reason, region = region }
            return true
        end,
        knownRegion = function(id) return id == 'heartlands' end,
        rng = function(m, n) -- scripted values first, then the low end
            local v = table.remove(W.rngq, 1)
            if v then assert(v >= m and v <= n, 'scripted rng out of range'); return v end
            return m
        end,
        now = function() return W.clock end,
        log = function(m) W.logs[#W.logs + 1] = m end,
        label = function(item) return cfg.items[item] and cfg.items[item].label end,
    }
    W.D = leads.new(cfg, logic, W.deps)
    W.C1 = W.players.C1
    W.leads = function() return count(W.C1.equipped, LEAD) + count(W.C1.backpack, LEAD) end
    return W
end

local function withLead(where_, l, extra)
    local o = { [where_] = { [5] = { name = LEAD, amount = 1, info = info(l or ROAD) } } }
    for k, v in pairs(extra or {}) do o[k] = v end
    return o
end

local function logged(W, needle)
    for _, l in ipairs(W.logs) do if l:find(needle, 1, true) then return l end end
    return nil
end

local function interleave(fns)
    local cos, res = {}, {}
    for i, f in ipairs(fns) do cos[i] = coroutine.create(f) end
    repeat
        local live = false
        for i, co in ipairs(cos) do
            if coroutine.status(co) == 'suspended' then
                live = true
                local r = table.pack(coroutine.resume(co))
                if not r[1] then error(r[2]) end
                if coroutine.status(co) == 'dead' then res[i] = table.pack(table.unpack(r, 2, r.n)) end
            end
        end
    until not live
    return res
end

-- loot entry 1 (money only, 150-300) at its low end unless scripted; entry 2 = 2 gunsmith parts + money
local GUN_ROLL = { 51, 100 } -- pick r=51 -> entry 2, then money 100

-- ---------------------------------------------------------------- dig

case('dig: too far from the spot is refused; lead kept, nothing paid', function()
    local W = world(withLead('backpack', ROAD, { pos = { x = SPOT.x + cfg.leads.digRadius + 0.5, y = SPOT.y, z = SPOT.z } }))
    T.same({ false, 'lead_too_far', n = 2 }, table.pack(W.D.dig(1)))
    T.eq(1, W.leads()); T.eq(0, #W.paid); T.eq(nil, W.calls.removeItem)
end)

case('dig: just inside the radius counts (server-side ped coords)', function()
    local W = world(withLead('backpack', ROAD, { pos = { x = SPOT.x + cfg.leads.digRadius - 0.5, y = SPOT.y, z = SPOT.z } }))
    T.eq(true, (W.D.dig(1)))
end)

case('dig: no lead is refused', function()
    local W = world()
    T.same({ false, 'no_lead', n = 2 }, table.pack(W.D.dig(1)))
    T.eq(nil, W.calls.removeItem); T.eq(0, #W.paid)
end)

case('dig: a lead for another spot is refused (too far), not spent', function()
    local W = world(withLead('backpack', CAMP))
    T.same({ false, 'lead_too_far', n = 2 }, table.pack(W.D.dig(1)))
    T.eq(1, W.leads())
end)

case('dig: no room for the parts is refused with the lead kept', function()
    local W = world(withLead('backpack', ROAD, { room = 1 }))
    W.rngq = copy(GUN_ROLL)
    T.same({ false, 'no_room', n = 2 }, table.pack(W.D.dig(1)))
    T.eq(1, W.leads()); T.eq(0, #W.paid); T.eq(nil, W.calls.removeItem); T.eq(0, #W.added)
end)

case('dig: success removes the lead and pays money + parts', function()
    local W = world(withLead('backpack', ROAD))
    W.rngq = copy(GUN_ROLL)
    local ok, res = W.D.dig(1)
    T.eq(true, ok)
    T.same({ money = 100, item = 'fh_part_gunsmith', qty = 2, label = 'Gunsmith Parts' }, res)
    T.eq(0, W.leads())
    T.same({ { amount = 100, reason = 'fence_lead_dig', region = 'heartlands' } }, W.paid)
    T.same({ { name = 'fh_part_gunsmith', qty = 2 } }, W.added)
    T.eq(100, W.C1.money)
    assert(logged(W, 'lead dug: citizenid=C1'), 'audit line')
    T.eq(nil, logged(W, 'WARNING'))
    T.eq('You dug up $100 and 2 x Gunsmith Parts.', logic.notice(ok, res))
end)

case('dig: the order is canFit -> removeItem -> pay -> addItem', function()
    local W = world(withLead('backpack', ROAD))
    W.rngq = copy(GUN_ROLL)
    local order = {}
    for _, n in ipairs({ 'canFit', 'removeItem', 'pay', 'addItem' }) do
        W.hooks[n] = function() order[#order + 1] = n end
    end
    assert(W.D.dig(1))
    T.same({ 'canFit', 'removeItem', 'pay', 'addItem' }, order)
end)

case('dig: a second dig of the same lead fails and pays nothing', function()
    local W = world(withLead('backpack', ROAD))
    assert(W.D.dig(1))
    W.clock = W.clock + 60
    T.same({ false, 'no_lead', n = 2 }, table.pack(W.D.dig(1)))
    T.eq(1, #W.paid)
end)

case('dig: pay failure after removal is logged as WARNING; the lead is NOT re-granted', function()
    for _, code in ipairs({ 'ledger_failed', 'addmoney_refused', 'no_player', 'player_changed', 'pay_unavailable' }) do
        local W = world(withLead('backpack', ROAD))
        W.fail.pay = code
        local ok, res = W.D.dig(1)
        T.eq(true, ok) -- the dig happened: the lead is spent
        T.eq(0, res.money)
        T.same({ money = 150, payErr = code }, res.owed)
        local line = assert(logged(W, 'WARNING lead dig: lead taken but payout incomplete'), code)
        assert(line:find('citizenid=C1', 1, true) and line:find('owed_money=150 (' .. code .. ')', 1, true)
            and line:find('region=heartlands', 1, true) and line:find('target=-520.0,910.0,120.0', 1, true), line)
        T.eq(0, W.leads())
        T.eq(0, #W.added) -- no lead (or anything) added back
        W.clock = W.clock + 60
        W.fail.pay = nil
        T.same({ false, 'no_lead', n = 2 }, table.pack(W.D.dig(1)))
        T.eq(0, #W.paid)
        T.eq('You found the cache, but it could not be handed over: an admin has been told.', logic.notice(ok, res))
    end
end)

case('dig: part add failure after removal is logged; money still paid; lead gone', function()
    local W = world(withLead('backpack', ROAD))
    W.rngq = copy(GUN_ROLL)
    W.fail.addItem = 'fh_inventory_down'
    local ok, res = W.D.dig(1)
    T.eq(true, ok)
    T.eq(100, res.money)
    T.same({ item = 'fh_part_gunsmith', qty = 2, addErr = 'fh_inventory_down' }, res.owed)
    assert(logged(W, 'owed_item=fh_part_gunsmith x2 (fh_inventory_down)'))
    T.eq(0, W.leads())
end)

case('dig: removeItem refusal pays nothing; an unclear one is logged', function()
    local W = world(withLead('backpack', ROAD))
    W.fail.removeItem = 'fh_not_enough'
    T.same({ false, 'no_lead', n = 2 }, table.pack(W.D.dig(1)))
    T.eq(0, #W.paid); T.eq(nil, logged(W, 'WARNING'))
    W = world(withLead('backpack', ROAD))
    W.fail.removeItem = 'fh_unavailable'
    T.same({ false, 'fh_unavailable', n = 2 }, table.pack(W.D.dig(1)))
    T.eq(0, #W.paid)
    assert(logged(W, 'WARNING lead dig: removeItem failed (fh_unavailable)'))
end)

case('dig: concurrent digs are serialized (one lead, two connections)', function()
    local W = world(withLead('backpack', ROAD))
    local r = interleave({ function() return W.D.dig(1) end, function() return W.D.dig(2) end })
    T.eq(true, r[1][1])
    T.same({ false, 'dig_busy', n = 2 }, r[2])
    T.eq(1, #W.paid); T.eq(0, W.leads())
    T.eq(false, W.D.busy('C1')) -- released
end)

case('dig: even a reclaimed stale lock cannot pay twice for one lead (removeItem is the gate)', function()
    local W = world(withLead('backpack', ROAD))
    W.hooks.snapshot = function(w, n) if n == 2 then w.clock = w.clock + cfg.leads.lockStaleSeconds + 1 end end
    local r = interleave({ function() return W.D.dig(1) end, function()
        coroutine.yield('wait'); coroutine.yield('wait'); coroutine.yield('wait')
        return W.D.dig(2)
    end })
    local oks = (r[1][1] and 1 or 0) + (r[2][1] and 1 or 0)
    T.eq(1, oks)
    T.eq(1, #W.paid); T.eq(0, W.leads())
    assert(logged(W, 'WARNING reclaimed a stale dig lock'))
end)

case('dig: cooldown between attempts', function()
    local W = world(withLead('backpack', CAMP))
    T.same({ false, 'lead_too_far', n = 2 }, table.pack(W.D.dig(1)))
    T.same({ false, 'dig_cooldown', n = 2 }, table.pack(W.D.dig(1)))
    W.clock = W.clock + cfg.leads.cooldownSeconds
    T.same({ false, 'lead_too_far', n = 2 }, table.pack(W.D.dig(1)))
end)

case('dig: two leads for different spots in one section are refused (lead_mixed), none spent', function()
    local W = world({ backpack = { [1] = { name = LEAD, amount = 1, info = info(CAMP) },
                                   [2] = { name = LEAD, amount = 1, info = info(ROAD) } } })
    T.same({ false, 'lead_mixed', n = 2 }, table.pack(W.D.dig(1)))
    T.eq(2, W.leads()); T.eq(nil, W.calls.removeItem)
end)

case('dig: picks the section that holds only this spot\'s lead', function()
    local W = world({ backpack = { [1] = { name = LEAD, amount = 1, info = info(CAMP) } },
                      equipped = { [2] = { name = LEAD, amount = 1, info = info(ROAD) } } })
    assert(W.D.dig(1))
    T.eq(0, count(W.C1.equipped, LEAD)); T.eq(1, count(W.C1.backpack, LEAD))
end)

case('dig: an error after removal is logged with the owed roll', function()
    local W = world(withLead('backpack', ROAD))
    W.hooks.pay = function() error('boom') end
    T.same({ false, 'dig_error_taken', n = 2 }, table.pack(W.D.dig(1)))
    assert(logged(W, 'WARNING lead dig: error after the lead was taken'))
    T.eq(0, W.leads()); T.eq(false, W.D.busy('C1'))
end)

case('dig: fail closed on inventory read failure, unknown player, bad source', function()
    local W = world(withLead('backpack', ROAD))
    W.fail.snapshot = 'fh_inventory_down'
    T.same({ false, 'fh_inventory_down', n = 2 }, table.pack(W.D.dig(1)))
    T.same({ false, 'no_player', n = 2 }, table.pack(W.D.dig(99)))
    T.same({ false, 'no_player', n = 2 }, table.pack(W.D.dig(0)))
    T.same({ false, 'no_player', n = 2 }, table.pack(W.D.dig('1')))
    T.eq(1, W.leads()); T.eq(0, #W.paid)
end)

case('leadsFor: one area per target with the hint, no exact target', function()
    local W = world({ backpack = { [1] = { name = LEAD, amount = 1, info = info(ROAD) },
                                   [2] = { name = LEAD, amount = 1, info = info(ROAD) },
                                   [3] = { name = 'bread', amount = 1 } },
                      equipped = { [4] = { name = LEAD, amount = 1, info = info(CAMP) } } })
    local list = W.D.leadsFor(1)
    T.eq(2, #list)
    for _, l in ipairs(list) do
        T.eq(cfg.leads.areaRadius, l.radius)
        assert(l.hint == ROAD.hint or l.hint == CAMP.hint)
        T.eq(nil, l.target)
    end
end)

T.finish()
