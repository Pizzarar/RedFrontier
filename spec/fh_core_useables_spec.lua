-- core-08 P2: fh_core/server/useables.lua with stubbed natives, exports and inventory.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local case = T.it
local SERVER = here .. '../server/resources/[fh]/fh_core/server/useables.lua'

local function boot(o)
    o = o or {}
    local w = { cid = (o.cid == nil) and 'CID1' or o.cid, events = {}, notes = {}, removed = {}, added = {}, credited = {}, paid = {}, charged = {}, useables = {}, handlers = {}, logs = {} }
    local bag = o.bag or {}
    local env = setmetatable({}, { __index = _G })
    env.GetGameTimer = function() w.t = (w.t or 0) + 5000 return w.t end
    env.GetCurrentResourceName = function() return 'fh_core' end
    env.AddEventHandler = function(n, fn) w.handlers[n] = fn end
    env.CreateThread = function(fn) fn() end
    w.timers = {}
    env.SetTimeout = function(ms, fn) w.timers[#w.timers + 1] = { ms = ms, fn = fn } end
    env.GetPlayerPed = function() return 7 end
    env.GetEntityHealth = function() if o.health == 'nope' then error('no ped') end return o.health or 200 end
    env.print = function(...) w.logs[#w.logs + 1] = table.concat({ ... }, ' ') end
    env.TriggerClientEvent = function(name, src, p)
        if name == 'RSGCore:Client:Notify' then w.notes[#w.notes + 1] = p.description else w.events[#w.events + 1] = { name = name, p = p } end
    end
    env.exports = setmetatable({}, { __index = function(_, res)
        return setmetatable({}, { __index = function(_, fn)
            return function(_, a, b, c, d)
                if res == 'rsg-core' and fn == 'CreateUseableItem' then w.useables[a] = b return end
                if res == 'rsg-core' and fn == 'GetCoreObject' then
                    return { Functions = { GetPlayer = function()
                        if not w.cid then return nil end
                        local P = { PlayerData = { citizenid = w.cid, money = { bloodmoney = 0 } } }
                        P.Functions = { AddMoney = function(t, amt, why)
                            w.added[#w.added + 1] = { type = t, amount = amt, reason = why }
                            if o.addMoneyFalse then return false end
                            P.PlayerData.money[t] = P.PlayerData.money[t] + amt
                            w.order = (w.order or '') .. 'M'
                            if o.addMoneyThrows then error('side effect blew up') end
                            return true
                        end }
                        return P
                    end } }
                end
                if res == 'rsg-inventory' then
                    if fn == 'GetItemBySlot' then return bag[b] end
                    if fn == 'GetItemByName' then for _, it in pairs(bag) do if it.name == b then return it end end return nil end
                    if fn == 'RemoveItem' then
                        if o.removeFails then return false end
                        w.removed[#w.removed + 1] = b w.order = (w.order or '') .. 'R' bag[d or 1] = nil return true
                    end
                    if fn == 'AddItem' then
                        if o.addFails then return false end
                        w.gaveBack = (w.gaveBack or 0) + 1 return true
                    end
                end
                if res == 'fh_economy' and fn == 'credit' then w.credited[#w.credited + 1] = { cid = a, amount = b } return true, nil, 'paid' end
                if res == 'fh_economy' and fn == 'pay' then
                    if o.duringPay then o.duringPay(w, bag) end -- the yield: other things happen here
                    if o.payFails then return false, 'refused' end
                    w.paid[#w.paid + 1] = { amount = b, reason = c } w.order = (w.order or '') .. 'P' return true, nil, 1
                end
                if res == 'fh_economy' and fn == 'charge' then w.charged[#w.charged + 1] = { amount = b, reason = c } return true end
            end
        end })
    end })
    assert(loadfile(SERVER, 't', env))()
    w.handlers.onResourceStart('fh_core')
    function w.use(src, name) w.useables[name](src, { name = name, slot = 1 }) end
    function w.drop(src) env.source = src w.handlers.playerDropped() env.source = nil end
    function w.tick() local t = w.timers w.timers = {} for _, x in ipairs(t) do x.fn() end end
    -- internal maps, reached through the settle closure's upvalues (leak checks)
    local function upv(fn, name, seen)
        seen = seen or {}
        if seen[fn] then return nil end
        seen[fn] = true
        for i = 1, 64 do
            local n, v = debug.getupvalue(fn, i)
            if not n then break end
            if n == name then return v end
            if type(v) == 'function' then local r = upv(v, name, seen) if r ~= nil then return r end end
        end
    end
    function w.map(name) return upv(w.handlers.playerDropped, name) end
    return w
end

local function bagOf(name, info) return { [1] = { name = name, slot = 1, info = info or {} } } end

case('registers all eight items; re-registers on rsg-core restart', function()
    local w = boot()
    for _, n in ipairs({ 'bandage', 'fieldbandage', 'firstaid', 'tonic_healing', 'tonic_stamina', 'tonic_energy', 'money_clip', 'blood_money_clip' }) do
        assert(w.useables[n], n) w.useables[n] = nil
    end
    w.handlers.onResourceStart('rsg-core')
    assert(w.useables.bandage and w.useables.money_clip)
end)

case('heal: consumes one item then sends the restore event with the configured fractions', function()
    local w = boot({ bag = bagOf('bandage') })
    w.use(1, 'bandage')
    assert(#w.removed == 1 and w.removed[1] == 'bandage')
    assert(#w.events == 1 and w.events[1].name == 'fh:core:useable:restore' and w.events[1].p.hp == 0.15 and w.events[1].p.stamina == 0)
    local w2 = boot({ bag = bagOf('firstaid') }) w2.use(1, 'firstaid')
    assert(w2.events[1].p.hp == 0.60)
    local w3 = boot({ bag = bagOf('tonic_stamina') }) w3.use(1, 'tonic_stamina')
    assert(w3.events[1].p.stamina == 0.60 and w3.events[1].p.hp == 0)
    local w4 = boot({ bag = bagOf('tonic_energy') }) w4.use(1, 'tonic_energy')
    assert(w4.events[1].p.hp == 0.10 and w4.events[1].p.stamina == 0.40)
end)

case('heal: failed removal grants nothing', function()
    local w = boot({ bag = bagOf('bandage'), removeFails = true })
    w.use(1, 'bandage')
    assert(#w.events == 0 and #w.notes == 1)
end)

case('heal: item not in the inventory grants nothing; dead ped refused without consuming', function()
    local w = boot({ bag = {} }) w.use(1, 'bandage')
    assert(#w.events == 0 and #w.removed == 0)
    local d = boot({ bag = bagOf('bandage'), health = 0 }) d.use(1, 'bandage')
    assert(#d.events == 0 and #d.removed == 0)
end)

case('money clip: removes the clip first, then pays; whole cents, within range', function()
    local w = boot({ bag = bagOf('money_clip') })
    w.use(1, 'money_clip')
    assert(w.order == 'RP', w.order)
    local a = w.paid[1].amount
    assert(a >= 5 and a <= 25 and math.abs(a * 100 - math.floor(a * 100 + 0.5)) < 1e-6)
    local w2 = boot({ bag = bagOf('money_clip', { amount = 12.34 }) })
    w2.use(1, 'money_clip')
    assert(w2.paid[1].amount == 12.34 and w2.paid[1].reason == 'money_clip')
end)

case('money clip: failed removal pays nothing', function()
    local w = boot({ bag = bagOf('money_clip'), removeFails = true })
    w.use(1, 'money_clip')
    assert(#w.paid == 0 and #w.notes == 1)
end)

case('money clip: moved away during the pay yield -> already removed, so one payout only', function()
    local w = boot({ bag = bagOf('money_clip'), duringPay = function(_, bag) assert(bag[1] == nil) end })
    w.use(1, 'money_clip')
    assert(#w.paid == 1 and #w.removed == 1)
end)

case('money clip: pay failure gives the clip back; give-back failure credits the cash', function()
    local w = boot({ bag = bagOf('money_clip'), payFails = true })
    w.use(1, 'money_clip')
    assert(w.gaveBack == 1 and #w.credited == 0 and #w.paid == 0)
    local w2 = boot({ bag = bagOf('money_clip', { amount = 9 }), payFails = true, addFails = true })
    w2.use(1, 'money_clip')
    assert(#w2.credited == 1 and w2.credited[1].cid == 'CID1' and w2.credited[1].amount == 9)
end)

case('money clip: two concurrent uses pay once (in-flight lock), lock released afterwards', function()
    local w
    w = boot({ bag = bagOf('money_clip'), duringPay = function(ww) ww.use(1, 'money_clip') end })
    w.use(1, 'money_clip')
    assert(#w.paid == 1 and #w.removed == 1)
    w.useables.money_clip(1, { name = 'money_clip', slot = 1 }) -- bag empty now, but the lock must be free (no error)
    local bag, boom = bagOf('money_clip'), true
    local e = boot({ bag = bag, duringPay = function() if boom then error('boom') end end })
    e.use(1, 'money_clip') -- pay throws: clip given back, lock must still be released
    assert(e.gaveBack == 1 and #e.paid == 0)
    boom = false; bag[1] = { name = 'money_clip', slot = 1, info = {} }
    e.use(1, 'money_clip')
    assert(#e.paid == 1)
end)

case('blood money clip: pays bloodmoney via AddMoney after removal; false path gives the clip back, no credit', function()
    local w = boot({ bag = bagOf('blood_money_clip', { amount = 20 }) })
    w.use(1, 'blood_money_clip')
    assert(w.order == 'RM' and w.added[1].type == 'bloodmoney' and w.added[1].amount == 20 and #w.paid == 0)
    local f = boot({ bag = bagOf('blood_money_clip', { amount = 20 }), addMoneyFalse = true, addFails = true })
    f.use(1, 'blood_money_clip')
    assert(#f.credited == 0 and #f.paid == 0 and f.notes[#f.notes] == "You can't use that right now.")
    local g = boot({ bag = bagOf('blood_money_clip', { amount = 20 }), addMoneyFalse = true })
    g.use(1, 'blood_money_clip')
    assert(g.gaveBack == 1 and #g.credited == 0)
end)

case('money clip: disconnect during pay -> no give-back to anyone, cash credited to the original cid', function()
    local w = boot({ bag = bagOf('money_clip', { amount = 9 }), payFails = true, duringPay = function(ww) ww.cid = nil end })
    w.use(1, 'money_clip')
    assert((w.gaveBack or 0) == 0 and #w.credited == 1 and w.credited[1].cid == 'CID1' and w.credited[1].amount == 9)
end)

case('money clip: character switch on the same src during pay -> credited to A, nothing to B', function()
    local w = boot({ bag = bagOf('money_clip', { amount = 9 }), payFails = true, duringPay = function(ww) ww.cid = 'CID2' end })
    w.use(1, 'money_clip')
    assert((w.gaveBack or 0) == 0 and #w.credited == 1 and w.credited[1].cid == 'CID1')
    assert(#w.notes == 0) -- B is not told anything about A's clip
end)

case('money clip: onUse inside the unload window fails closed before consume (no dupe)', function()
    local w = boot({ bag = bagOf('money_clip', { amount = 9 }) })
    w.handlers['RSGCore:Server:OnPlayerUnload'](1)
    w.use(1, 'money_clip')
    assert(#w.removed == 0 and #w.paid == 0 and #w.credited == 0 and (w.gaveBack or 0) == 0)
    w.handlers['RSGCore:Server:PlayerLoaded']({ PlayerData = { source = 1, citizenid = 'CID1' } }) -- relogged
    w.use(1, 'money_clip')
    assert(#w.paid == 1)
end)

case('money clip: unload starting mid-pay -> no give-back into saved memory, cash credited to cid once', function()
    local w = boot({ bag = bagOf('money_clip', { amount = 9 }), payFails = true })
    w.use(1, 'money_clip') -- baseline: still same character -> gives back, no credit
    assert(w.gaveBack == 1 and #w.credited == 0)
    local w2 = boot({ bag = bagOf('money_clip', { amount = 9 }), payFails = true,
        duringPay = function(ww) ww.handlers['RSGCore:Server:OnPlayerUnload'](1) end })
    w2.use(1, 'money_clip')
    assert((w2.gaveBack or 0) == 0 and #w2.credited == 1 and w2.credited[1].cid == 'CID1' and w2.credited[1].amount == 9)
    -- blood clip: no fallback, no give-back, no credit
    local w3 = boot({ bag = bagOf('blood_money_clip', { amount = 9 }) })
    w3.handlers['RSGCore:Server:PlayerDropped']({ PlayerData = { source = 1, citizenid = 'CID1' } })
    w3.use(1, 'blood_money_clip')
    assert(#w3.removed == 0 and #w3.added == 0)
end)

case('money clip: no character before use fails closed, clip not removed', function()
    local w = boot({ bag = bagOf('money_clip'), cid = false })
    w.use(1, 'money_clip')
    assert(#w.removed == 0 and #w.paid == 0 and #w.credited == 0)
end)

case('blood clip: AddMoney throwing after the balance moved counts as paid (no give-back)', function()
    local w = boot({ bag = bagOf('blood_money_clip', { amount = 20 }), addMoneyThrows = true })
    w.use(1, 'blood_money_clip')
    assert((w.gaveBack or 0) == 0 and #w.added == 1 and w.notes[1]:find('20.00'))
end)

case('money clip: sub-half-cent amount is refused with a notify, clip stays', function()
    local w = boot({ bag = bagOf('money_clip', { amount = 0.004 }) })
    w.use(1, 'money_clip')
    assert(#w.removed == 0 and #w.paid == 0 and w.notes[1] == 'That clip is empty.')
end)

case('heal: no health reading fails closed', function()
    local w = boot({ bag = bagOf('bandage'), health = 'nope' })
    w.use(1, 'bandage')
    assert(#w.events == 0 and #w.removed == 0)
end)

local function size(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

case('unload maps: cleared after drop + settle once rsg-core no longer holds the cid; kept (re-checked) while it does', function()
    local w = boot({ bag = bagOf('money_clip', { amount = 9 }) })
    w.handlers['RSGCore:Server:OnPlayerUnload'](1)
    w.drop(1)
    local cidMap, seqMap = w.map('unloadCid'), w.map('unloadSeq')
    assert(cidMap and seqMap, 'maps reachable')
    T.eq('CID1', cidMap[1]) assert(seqMap[1])
    T.eq(1, #w.timers) T.eq(5000, w.timers[1].ms)
    w.tick() -- rsg-core still has CID1 on src 1 (drop-time save yielding): keep the window, look again
    T.eq('CID1', cidMap[1]) T.eq(1, #w.timers)
    w.use(1, 'money_clip')
    assert(#w.removed == 0 and #w.paid == 0, 'still fails closed before consume')
    w.cid = nil -- rsg-core removed the player after its save
    w.tick()
    T.eq(0, size(cidMap)) T.eq(0, size(seqMap)) T.eq(0, #w.timers)
end)

case('unload maps: a drop with no character settles to nothing; the settle is a no-op when already clear', function()
    local w = boot({ cid = false })
    w.drop(1)
    T.eq(0, size(w.map('unloadCid'))) T.eq(1, #w.timers)
    w.tick()
    T.eq(0, size(w.map('unloadSeq'))) T.eq(0, #w.timers)
end)

case('unload maps: seq untouched while a clip is in flight; cleared after it ends; no give-back, credit once', function()
    local seqDuring
    local w
    w = boot({ bag = bagOf('money_clip', { amount = 9 }), payFails = true, duringPay = function(ww)
        ww.drop(1)        -- disconnect while pay yields: marks the unload
        ww.cid = nil      -- rsg-core removed the player after its save
        local seq = ww.map('unloadSeq')[1]
        ww.tick()         -- settle fires mid-pay: clipBusy -> keep everything, re-check later
        seqDuring = ww.map('unloadSeq')[1]
        assert(seq ~= nil and seqDuring == seq, 'seq kept while clipBusy')
        assert(ww.map('clipBusy')[1] == true, 'playerDropped does not release the in-flight lock')
        ww.use(1, 'money_clip') -- a second use during the yield is still locked out
    end })
    w.use(1, 'money_clip')
    assert(seqDuring)
    assert((w.gaveBack or 0) == 0 and #w.credited == 1 and w.credited[1].cid == 'CID1' and #w.removed == 1)
    T.eq(nil, w.map('clipBusy')[1], 'lock released by onClip')
    T.eq(1, #w.timers, 'the deferred settle is pending')
    w.tick()
    T.eq(0, size(w.map('unloadCid'))) T.eq(0, size(w.map('unloadSeq'))) T.eq(0, #w.timers)
end)

case('unload seq stamps never repeat after a settle cleared them (global counter)', function()
    local w = boot()
    w.handlers['RSGCore:Server:OnPlayerUnload'](1)
    local first = w.map('unloadSeq')[1]
    w.cid = nil w.drop(1) w.tick()
    T.eq(nil, w.map('unloadSeq')[1])
    w.cid = 'CID1'
    w.handlers['RSGCore:Server:OnPlayerUnload'](1)
    assert(w.map('unloadSeq')[1] > first)
end)

T.finish()
