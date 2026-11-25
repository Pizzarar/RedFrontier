-- Stubbed-server spec (core M2, A1 money audit): loads rsg-core's real server/player.lua + server/moneyitems.lua with
-- EnableMoneyItems = true, against a fake inventory that copies fh_inventory's add / remove / commit semantics
-- (stack into an existing stack, else the first empty slot; a weight check that refuses even a 0-weight add once the
-- player is over weight; ConvertCoins on commit; every commit is SetPlayerData('items') -> UpdatePlayerData -> the
-- money-item sync, which re-reads cash from the items).
-- Invariant: AddMoney / RemoveMoney / SetMoney return true only when the money items moved by exactly the amount, and
-- false with nothing moved (items and balance as before) otherwise. Before M2, a cash add whose items could not be
-- placed returned true while the sync reset cash to the item total: fh_economy's ledger said "paid", the money was gone.
-- Not a substitute for a live boot.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local CORE = here .. '../server/resources/[rsg]/rsg-core/server/'

local handlers, serverEvents = {}, {}
function AddEventHandler(name, fn) handlers[name] = handlers[name] or {}; table.insert(handlers[name], fn) end
function RegisterNetEvent(name, fn) if fn then AddEventHandler(name, fn) end end
function TriggerEvent(name, ...)
    serverEvents[#serverEvents + 1] = { name = name, args = { ... } }
    for _, fn in ipairs(handlers[name] or {}) do fn(...) end
end
local clientEvents = {}
function TriggerClientEvent(name, ...) clientEvents[#clientEvents + 1] = { name = name, args = { ... } } end
function GetCurrentResourceName() return 'rsg-core' end
function GetPlayerName(src) return 'P' .. tostring(src) end
function Player() return { state = {} } end
function locale(k) return k end
function PaycheckInterval() end
local realPrint = print
print = function(...) -- moneyitems prints a failure line per refused item; keep the runner output clean
    if tostring((...)):find('could not give', 1, true) then return end
    realPrint(...)
end

RSGCore = {
    Config = {
        Money = { EnableMoneyItems = true, GoldItem = 'gold', DontAllowMinus = { 'cash', 'gold', 'bloodmoney', 'bank' },
            MinusLimit = -5000 },
        Gold = { EnableGoldItems = false },
    },
    Functions = {},
}
dofile(CORE .. 'player.lua')
dofile(CORE .. 'moneyitems.lua')
RSGCore.Functions.GetPlayer = function(src) return RSGCore.Players[src] end
RSGCore.Player.Save = function() end

---------------------------------------------------------------------------------------------------------------------
-- fake fh_inventory (server/main.lua AddToRaw / RemoveFrom / ConvertCoins / Commit; compat.lua GetItemsByName)
---------------------------------------------------------------------------------------------------------------------
local WEIGHT = { dollar = 0, cent = 0, blood_dollar = 0, blood_cent = 0, gold = 0, rock = 1000 }
local COINS = { { cent = 'cent', dollar = 'dollar' }, { cent = 'blood_cent', dollar = 'blood_dollar' } }

local function mkItem(name, amount, slot)
    return { name = name, amount = amount, slot = slot, weight = WEIGHT[name], info = {} }
end

-- GetContainer: a fresh copy of the player's items every call (rsg-core hands out copies across resources)
local function container(src)
    local P = RSGCore.Players[src]
    local items = {}
    for k, it in pairs(P.PlayerData.items) do
        local slot = tonumber(it.slot) or k
        items[slot] = mkItem(it.name, it.amount, slot)
    end
    return { P = P, items = items, slots = P.PlayerData.slots, maxWeight = P.PlayerData.weight }
end

local function totalWeight(items)
    local w = 0
    for _, it in pairs(items) do w = w + it.weight * it.amount end
    return w
end

local function countIn(c, name)
    local n = 0
    for _, it in pairs(c.items) do if it.name == name then n = n + it.amount end end
    return n
end

local function addTo(c, name, amount)
    if totalWeight(c.items) + WEIGHT[name] * amount > c.maxWeight then return false, 'too_heavy' end
    local target
    for slot = 1, c.slots do
        if c.items[slot] and c.items[slot].name == name then target = slot break end
    end
    if not target then
        for slot = 1, c.slots do if not c.items[slot] then target = slot break end end
    end
    if not target then return false, 'no_space' end
    if c.items[target] then
        c.items[target].amount = c.items[target].amount + amount
    else
        c.items[target] = mkItem(name, amount, target)
    end
    return true
end

local function removeFrom(c, name, amount, slot)
    if slot then
        local it = c.items[slot]
        if not it or it.name ~= name or it.amount < amount then return false end
        it.amount = it.amount - amount
        if it.amount <= 0 then c.items[slot] = nil end
        return true
    end
    if countIn(c, name) < amount then return false end
    for s = 1, c.slots do
        local it = c.items[s]
        if amount <= 0 then break end
        if it and it.name == name then
            local take = math.min(it.amount, amount)
            it.amount = it.amount - take
            if it.amount <= 0 then c.items[s] = nil end
            amount = amount - take
        end
    end
    return true
end

local function commit(c)
    for _, pair in ipairs(COINS) do -- ConvertCoins: 100 cents -> 1 dollar, cents put back when the dollars don't fit
        local dollars = countIn(c, pair.cent) // 100
        if dollars > 0 then
            removeFrom(c, pair.cent, dollars * 100)
            if not addTo(c, pair.dollar, dollars) then addTo(c, pair.cent, dollars * 100) end
        end
    end
    c.P.Functions.SetPlayerData('items', c.items)
    local hook = onCommit; onCommit = nil -- one-shot listener inside the commit (spec hook: a nested money op)
    if hook then hook(c.P) end
end

AddEventHandler('RSGCore:Server:PlayerLoaded', function(P) -- compat.lua RegisterPlayerMethods
    local src = P.PlayerData.source
    P.Functions.AddMethod('AddItem', function(name, amount)
        local c = container(src)
        local ok, why = addTo(c, name, amount)
        if not ok then return false, why end
        commit(c)
        return true
    end)
    P.Functions.AddMethod('RemoveItem', function(name, amount, slot)
        if refuseRemove == name then refuseRemove = nil; return false end -- one-shot refusal (spec hook)
        local c = container(src)
        if not removeFrom(c, name, amount, slot) then return false end
        commit(c)
        return true
    end)
    P.Functions.AddMethod('GetItemsByName', function(name)
        local out = {}
        for _, it in pairs(container(src).items) do if it.name == name then out[#out + 1] = it end end
        table.sort(out, function(a, b) return a.slot < b.slot end)
        return out
    end)
end)

---------------------------------------------------------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------------------------------------------------------
local nextSrc = 0

-- opts: slots, maxWeight, items = { {name, amount, slot}, ... }, fill = rock in every other empty slot
local function newPlayer(opts)
    nextSrc = nextSrc + 1
    local src = nextSrc
    local items, cents, blood = {}, 0, 0
    for _, it in ipairs(opts.items or {}) do
        items[it[3]] = mkItem(it[1], it[2], it[3])
        if it[1] == 'dollar' then cents = cents + it[2] * 100 elseif it[1] == 'cent' then cents = cents + it[2] end
        if it[1] == 'blood_dollar' then blood = blood + it[2] * 100 elseif it[1] == 'blood_cent' then blood = blood + it[2] end
    end
    local slots = opts.slots or 10
    if opts.fill then
        for s = 1, slots do if not items[s] then items[s] = mkItem('rock', 1, s) end end
    end
    RSGCore.Player.CreatePlayer({
        source = src, citizenid = 'CID' .. src, license = 'l' .. src, charinfo = {}, metadata = {},
        money = { cash = cents / 100, bloodmoney = blood / 100, gold = 0, bank = 0 },
        items = items, slots = slots, weight = opts.maxWeight or 100000,
    }, false)
    source = src -- the client's RSGCore:Server:OnPlayerLoaded: moneyitems reconciles, then starts the sync
    for _, fn in ipairs(handlers['RSGCore:Server:OnPlayerLoaded']) do fn() end
    source = nil
    return RSGCore.Players[src]
end

local function itemCents(P, dollarName, centName)
    local n = 0
    for _, it in pairs(P.PlayerData.items) do
        if it.name == (dollarName or 'dollar') then n = n + it.amount * 100 end
        if it.name == (centName or 'cent') then n = n + it.amount end
    end
    return n
end
local function cents(x) return math.floor(x * 100 + 0.5) end
local function layout(P)
    local out = {}
    for slot, it in pairs(P.PlayerData.items) do out[slot] = it.name .. 'x' .. it.amount end
    return out
end
local function moneyChanges()
    local n = 0
    for _, e in ipairs(serverEvents) do if e.name == 'RSGCore:Server:OnMoneyChange' then n = n + 1 end end
    return n
end
-- hud:client:OnMoneyChange events sent to the player since index `from`
local function hudEvents(P, from)
    local out = {}
    for i = from + 1, #clientEvents do
        local e = clientEvents[i]
        if e.name == 'hud:client:OnMoneyChange' and e.args[1] == P.PlayerData.source then out[#out + 1] = e.args end
    end
    return out
end
-- the next sync: any later inventory commit re-reads cash from the items
local function sync(P) P.Functions.UpdatePlayerData() end
-- fh_economy addMoneyChecked (server/main.lua): a call that returns is trusted as-is
local function checkedAdd(P, amount)
    local called, added = pcall(P.Functions.AddMoney, 'cash', amount, 'spec')
    assert(called, tostring(added))
    return added == true
end

local function same(P, beforeLayout, beforeCash, what)
    T.same(beforeLayout, layout(P), what .. ': items untouched')
    T.eq(beforeCash, cents(P.PlayerData.money.cash), what .. ': balance untouched')
    sync(P)
    T.eq(beforeCash, cents(P.PlayerData.money.cash), what .. ': balance after the next sync')
    T.eq(itemCents(P), cents(P.PlayerData.money.cash), what .. ': balance == items')
end

---------------------------------------------------------------------------------------------------------------------
T.describe('money items: AddMoney', function()
    T.it('room in the inventory: true, items and balance both move', function()
        local P = newPlayer({ items = { { 'dollar', 2, 1 } } })
        T.eq(true, checkedAdd(P, 3.25))
        T.eq(525, cents(P.PlayerData.money.cash))
        sync(P)
        T.eq(525, cents(P.PlayerData.money.cash))
        T.eq(525, itemCents(P))
    end)

    T.it('full inventory, no money stack: false, nothing moved, no phantom balance after a sync', function()
        local P = newPlayer({ slots = 4, fill = true })
        local L, ev = layout(P), moneyChanges()
        T.eq(false, checkedAdd(P, 5))
        same(P, L, 0, 'full')
        T.eq(ev, moneyChanges(), 'no RSGCore:Server:OnMoneyChange for money that did not move')
    end)

    T.it('full inventory, dollar stack but no cent stack: all-or-nothing (the dollars are taken back)', function()
        local P = newPlayer({ slots = 4, fill = true, items = { { 'dollar', 3, 2 } } })
        local L = layout(P)
        T.eq(false, checkedAdd(P, 1.50))
        same(P, L, 300, 'split add')
    end)

    T.it('full inventory with both stacks: the add merges and fits', function()
        local P = newPlayer({ slots = 4, fill = true, items = { { 'dollar', 3, 2 }, { 'cent', 40, 3 } } })
        T.eq(true, checkedAdd(P, 1.50))
        sync(P)
        T.eq(490, cents(P.PlayerData.money.cash))
        T.eq(490, itemCents(P))
    end)

    T.it('over weight (0-weight money is refused too): false, nothing moved', function()
        local P = newPlayer({ slots = 10, maxWeight = 1500, items = { { 'rock', 2, 1 }, { 'dollar', 1, 2 } } })
        local L = layout(P)
        T.eq(false, checkedAdd(P, 4))
        same(P, L, 100, 'over weight')
    end)

    T.it('bloodmoney follows the same rule', function()
        local P = newPlayer({ slots = 3, fill = true })
        T.eq(false, P.Functions.AddMoney('bloodmoney', 2, 'spec'))
        sync(P)
        T.eq(0, cents(P.PlayerData.money.bloodmoney))
    end)

    T.it('a failed add then room again: the next add lands in full', function()
        local P = newPlayer({ slots = 2, fill = true })
        T.eq(false, checkedAdd(P, 2.10))
        P.Functions.RemoveItem('rock', 1, 1)
        P.Functions.RemoveItem('rock', 1, 2)
        T.eq(true, checkedAdd(P, 2.10))
        sync(P)
        T.eq(210, cents(P.PlayerData.money.cash))
        T.eq(210, itemCents(P))
    end)
end)

T.describe('money items: RemoveMoney', function()
    T.it('dollars and cents split across several stacks: exact amount taken', function()
        local P = newPlayer({ slots = 10, items = {
            { 'dollar', 3, 2 }, { 'dollar', 4, 7 }, { 'cent', 20, 3 }, { 'cent', 15, 9 } } })
        T.eq(735, itemCents(P))
        T.eq(true, P.Functions.RemoveMoney('cash', 5.30, 'spec'))
        sync(P)
        T.eq(205, cents(P.PlayerData.money.cash))
        T.eq(205, itemCents(P))
    end)

    T.it('change needed, cent stack present, inventory full: true, change merges into the cents', function()
        local P = newPlayer({ slots = 4, fill = true, items = { { 'dollar', 5, 1 }, { 'cent', 30, 2 } } })
        T.eq(true, P.Functions.RemoveMoney('cash', 1.50, 'spec'))
        sync(P)
        T.eq(380, cents(P.PlayerData.money.cash))
        T.eq(380, itemCents(P))
    end)

    T.it('change needed, no cent stack, inventory full: false, nothing taken (the change would be lost)', function()
        local P = newPlayer({ slots = 3, fill = true, items = { { 'dollar', 10, 1 } } })
        local L = layout(P)
        T.eq(false, P.Functions.RemoveMoney('cash', 2.50, 'spec'))
        same(P, L, 1000, 'no room for change')
    end)

    T.it('change needed, over weight: false, nothing taken', function()
        local P = newPlayer({ slots = 10, maxWeight = 500, items = { { 'rock', 1, 1 }, { 'dollar', 10, 2 } } })
        local L = layout(P)
        T.eq(false, P.Functions.RemoveMoney('cash', 0.25, 'spec'))
        same(P, L, 1000, 'over weight change')
    end)

    T.it('the whole cent stack and some dollars: change replaces the cents', function()
        local P = newPlayer({ slots = 10, items = { { 'dollar', 4, 1 }, { 'dollar', 1, 5 }, { 'cent', 90, 2 } } })
        T.eq(true, P.Functions.RemoveMoney('cash', 2.95, 'spec'))
        sync(P)
        T.eq(295, cents(P.PlayerData.money.cash))
        T.eq(295, itemCents(P))
    end)

    T.it('balance ahead of the items (not reconciled): false, nothing taken', function()
        local P = newPlayer({ slots = 10, items = { { 'dollar', 1, 1 } } })
        P.PlayerData.money.cash = 50 -- e.g. an offline AddMoney the login reconcile could not place
        T.eq(false, P.Functions.RemoveMoney('cash', 10, 'spec'))
        T.eq(100, itemCents(P))
    end)
end)

T.describe('money items: SetMoney', function()
    T.it('room: items match the new balance', function()
        local P = newPlayer({ slots = 10, items = { { 'dollar', 2, 1 }, { 'cent', 5, 2 } } })
        T.eq(true, P.Functions.SetMoney('cash', 7.40, 'spec'))
        sync(P)
        T.eq(740, cents(P.PlayerData.money.cash))
        T.eq(740, itemCents(P))
    end)

    T.it('full inventory, no money stack: false, nothing moved', function()
        local P = newPlayer({ slots = 3, fill = true })
        local L = layout(P)
        T.eq(false, P.Functions.SetMoney('cash', 9.99, 'spec'))
        same(P, L, 0, 'set full')
    end)
end)

T.describe('money items: reconcile and odd layouts', function()
    T.it('login reconcile (OnPlayerLoaded) places a balance the items lacked, through the same path', function()
        nextSrc = nextSrc + 1
        local src = nextSrc
        RSGCore.Player.CreatePlayer({ source = src, citizenid = 'CID' .. src, license = 'l' .. src, charinfo = {},
            metadata = {}, money = { cash = 3.75, bloodmoney = 0, gold = 0, bank = 0 }, items = {}, slots = 5,
            weight = 1000 }, false)
        source = src
        for _, fn in ipairs(handlers['RSGCore:Server:OnPlayerLoaded']) do fn() end
        source = nil
        local P = RSGCore.Players[src]
        T.eq(375, itemCents(P))
        sync(P)
        T.eq(375, cents(P.PlayerData.money.cash))
    end)

    T.it('cents never converted (no room for dollars back then): set and remove still land exactly', function()
        local P = newPlayer({ slots = 4, items = { { 'cent', 250, 1 } } })
        T.eq(true, P.Functions.SetMoney('cash', 2.50, 'spec'), 'same value: no move')
        T.eq(true, P.Functions.RemoveMoney('cash', 1.50, 'spec'))
        sync(P)
        T.eq(100, cents(P.PlayerData.money.cash))
        T.eq(100, itemCents(P))
    end)
end)

T.describe('money items: atomic cent removal (core M2-nit)', function()
    T.it('>=100 cents split over 3 stacks: ConvertCoins cannot fire between removals, exact amount taken', function()
        -- per-slot removals: 80 taken, the 160 left converted to 1 dollar + 60 cents, then only 60 of the 120 more
        -- were there: false, and the balance put back to 2.40 was then synced down to the 1.00 the items held
        local P = newPlayer({ slots = 6, items = { { 'cent', 80, 1 }, { 'cent', 80, 2 }, { 'cent', 80, 3 } } })
        T.eq(true, P.Functions.RemoveMoney('cash', 2.00, 'spec'))
        sync(P)
        T.eq(40, cents(P.PlayerData.money.cash))
        T.eq(40, itemCents(P))
    end)

    T.it('a refused removal after cents were taken: false, the cents go back, nothing lost', function()
        -- 120 unconverted cents in 2 stacks; 2.50 = 50 cents + 2 dollars (70 change kept). The dollar removal is
        -- refused after the 50 cents went: they are restored (ConvertCoins may merge them, same value)
        local P = newPlayer({ slots = 6, items = { { 'dollar', 5, 1 }, { 'cent', 60, 2 }, { 'cent', 60, 3 } } })
        refuseRemove = 'dollar'
        T.eq(false, P.Functions.RemoveMoney('cash', 2.50, 'spec'))
        refuseRemove = nil
        T.eq(620, itemCents(P), 'items still hold 6.20')
        T.eq(620, cents(P.PlayerData.money.cash), 'balance put back')
        sync(P)
        T.eq(620, cents(P.PlayerData.money.cash), 'balance after the next sync')
    end)

    T.it('a refused removal after change was added: false, the change is taken back', function()
        local P = newPlayer({ slots = 6, items = { { 'dollar', 5, 1 } } })
        local L = layout(P)
        refuseRemove = 'dollar'
        T.eq(false, P.Functions.RemoveMoney('cash', 0.25, 'spec'))
        refuseRemove = nil
        same(P, L, 500, 'refused dollar removal')
    end)
end)

T.describe('money items: one HUD money change per operation (core M2-nit)', function()
    T.it('AddMoney of dollars + cents (two item steps): one hud event, the full amount', function()
        local P = newPlayer({ slots = 6, items = { { 'dollar', 2, 1 } } })
        local from = #clientEvents
        T.eq(true, checkedAdd(P, 1.50))
        local ev = hudEvents(P, from)
        T.eq(1, #ev, 'one hud:client:OnMoneyChange')
        T.same({ P.PlayerData.source, 'cash', 1.50, false }, ev[1])
    end)

    T.it('RemoveMoney with change (add cents, remove cents and dollars): one hud event', function()
        local P = newPlayer({ slots = 6, items = { { 'dollar', 4, 1 }, { 'cent', 90, 2 } } })
        local from = #clientEvents
        T.eq(true, P.Functions.RemoveMoney('cash', 2.95, 'spec'))
        local ev = hudEvents(P, from)
        T.eq(1, #ev, 'one hud:client:OnMoneyChange')
        T.same({ P.PlayerData.source, 'cash', 2.95, true }, ev[1])
    end)

    T.it('a failed all-or-nothing add (dollars placed, then taken back): no hud event', function()
        local P = newPlayer({ slots = 4, fill = true, items = { { 'dollar', 3, 2 } } })
        local from = #clientEvents
        T.eq(false, checkedAdd(P, 1.50))
        T.eq(0, #hudEvents(P, from), 'no hud:client:OnMoneyChange')
    end)

    T.it('a player-driven item move still reaches the HUD through the sync', function()
        local P = newPlayer({ slots = 6, items = { { 'dollar', 3, 1 } } })
        local from = #clientEvents
        P.Functions.RemoveItem('dollar', 1, 1)
        local ev = hudEvents(P, from)
        T.eq(1, #ev)
        T.same({ P.PlayerData.source, 'cash', 1, true }, ev[1])
    end)
end)

T.describe('money items: nested money op keeps the sync suppressed (core-09 N1)', function()
    T.it('a bloodmoney AddMoney fired inside a cash RemoveMoney: one cash hud event, the full amount, balances exact', function()
        -- the nested op ends first: with a boolean flag it cleared the outer op's suppression, so its own and the
        -- outer's later commits synced half-moved cash items to the HUD (a change per step)
        local P = newPlayer({ slots = 8, items = { { 'dollar', 4, 1 }, { 'cent', 90, 2 } } })
        local from = #clientEvents
        local nested
        onCommit = function(PP) nested = PP.Functions.AddMoney('bloodmoney', 1.00, 'spec nested') end
        T.eq(true, P.Functions.RemoveMoney('cash', 2.95, 'spec'))
        T.eq(true, nested, 'nested add ran and succeeded')
        local cash = {}
        for _, e in ipairs(hudEvents(P, from)) do if e[2] == 'cash' then cash[#cash + 1] = e end end
        T.eq(1, #cash, 'one cash hud:client:OnMoneyChange')
        T.same({ P.PlayerData.source, 'cash', 2.95, true }, cash[1])
        T.eq(195, cents(P.PlayerData.money.cash))
        T.eq(100, cents(P.PlayerData.money.bloodmoney))
        sync(P)
        T.eq(195, cents(P.PlayerData.money.cash), 'cash after the next sync')
        T.eq(195, itemCents(P))
        T.eq(100, itemCents(P, 'blood_dollar', 'blood_cent'))
    end)
end)

print = realPrint
T.finish()
