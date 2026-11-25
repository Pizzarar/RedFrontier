---------------------------------------------------
-- Helper tables to map money items - do not change
---------------------------------------------------

local moneyItems = {
    cash = {
        dollar = 'dollar',
        cent = 'cent',
    },
    bloodmoney = {
        dollar = 'blood_dollar',
        cent = 'blood_cent',
    },
    gold = {
        unit = RSGCore.Config.Money.GoldItem,
    },
}

local moneyMap = {
    dollar = "cashDollars",
    cent = "cashCents",
    blood_dollar = "bloodDollars",
    blood_cent = "bloodCents"
}

-------------------
-- Helper functions
-------------------

local function getInventoryMoney(playerData)
    local money = {
        cashDollars = 0,
        cashCents = 0,
        bloodDollars = 0,
        bloodCents = 0,
        gold = 0,
    }

    for _, item in pairs(playerData.items) do
        if item then
            if moneyMap[item.name] then
                money[moneyMap[item.name]] = money[moneyMap[item.name]] + item.amount
            elseif item.name == moneyItems.gold.unit then
                money.gold = money.gold + item.amount
            end
        end
    end

    return money
end

local function refreshInventory(src)
    if Player(src).state.inv_busy then
        TriggerClientEvent('rsg-inventory:client:updateInventory', src)
    end
end

-- FH (core M2-nit): one RemoveItem for the whole amount, no slot. fh_inventory's RemoveFrom counts every stack first
-- and takes the amount across stacks in one commit, so ConvertCoins (which runs on commit) cannot merge cents into a
-- dollar between two removals. Per-slot removals could: >=100 cents split over 2+ stacks (DB load / SetInventory)
-- converted after the first removal, the next found too few cents, and the first slot's cents were already gone.
-- -> true when exactly the amount went (math.huge: every stack), false with nothing removed otherwise.
local function removeItems(player, itemName, amountToRemove, reason)
    local held = 0
    for _, item in pairs(player.Functions.GetItemsByName(itemName) or {}) do held = held + (item.amount or 0) end
    if amountToRemove == math.huge then amountToRemove = held end
    if amountToRemove <= 0 then return true end
    if held < amountToRemove then return false end
    return player.Functions.RemoveItem(itemName, amountToRemove, nil, reason) == true
end

-- work in whole cents to avoid float errors (e.g. 0.29 * 100 = 28.999... which lost a cent)
local function getParts(number)
    local totalCents = math.floor(number * 100 + 0.5)
    return totalCents // 100, totalCents % 100
end

local function calculateTotal(dollars, cents)
    return tonumber(string.format("%.2f", dollars + (cents / 100)))
end

-- AddItem returns ok, err; a full inventory used to silently lose the money, so report failures
local function giveMoneyItem(player, itemName, amount)
    local ok, err = player.Functions.AddItem(itemName, amount)
    if ok == false then
        local src = player.PlayerData.source
        print(('^1[rsg-core] could not give %sx %s to %s (%s): %s^7'):format(amount, itemName, tostring(player.PlayerData.citizenid), tostring(src), tostring(err)))
        TriggerEvent('rsg-log:server:CreateLog', 'moneyitems', 'Money item failed', 'red', ('**%s** (%s) could not receive %sx %s: %s'):format(GetPlayerName(src) or 'unknown', player.PlayerData.citizenid, amount, itemName, tostring(err)))
        TriggerClientEvent('RSGCore:Client:Notify', src, { title = locale('notify_label_error'), description = locale('error.money_item_failed'), type = 'error', duration = 7000 })
        return false
    end
    return true
end

----------------------------
-- Money operations handlers
----------------------------
-- FH (core M2): every handler is all-or-nothing and returns true only when the items moved by exactly the amount.
-- The items ARE the balance (SynchronizeMoneyItems re-reads it from them), so a handler that could not place its
-- items used to leave the balance short while AddMoney / RemoveMoney / SetMoney still returned true.
-- Shape: every add first, then every remove. An add can fail (no slot, over weight); a remove of items counted a
-- moment earlier with no yield in between should not, so a failed add is undone by removing the adds already done.
-- Only a refused remove (core M2-nit) has to give items back, which could itself fail (logged by ApplyMoneyItems).

local function applyMoves(player, adds, removes)
    local added, removed = {}, {}
    -- FH (core M2-nit): any refused step undoes every step already done: the adds are taken back (they are still
    -- there), then the removed items are given back (ConvertCoins may merge returned cents; same value). Whatever
    -- cannot be restored shows up in ApplyMoneyItems' before/after check.
    local function undo()
        for i = #added, 1, -1 do removeItems(player, added[i][1], added[i][2], 'money-item-rollback') end
        for i = #removed, 1, -1 do giveMoneyItem(player, removed[i][1], removed[i][2]) end
        return false
    end
    for _, a in ipairs(adds) do
        if a[2] > 0 then
            if not giveMoneyItem(player, a[1], a[2]) then return undo() end
            added[#added + 1] = a
        end
    end
    for _, r in ipairs(removes) do
        if r[2] > 0 then
            if not removeItems(player, r[1], r[2]) then return undo() end
            removed[#removed + 1] = r
        end
    end
    return true
end

local function handleAddMoney(player, moneytype, amount)
    if moneytype == 'gold' then
        return applyMoves(player, { { moneyItems.gold.unit, amount } }, {})
    end
    local dollars, cents = getParts(amount)
    return applyMoves(player, { { moneyItems[moneytype].dollar, dollars }, { moneyItems[moneytype].cent, cents } }, {})
end

local function handleRemoveMoney(player, moneytype, amount)
    local inventoryMoney = getInventoryMoney(player.PlayerData)

    if moneytype == 'gold' then
        if inventoryMoney.gold < amount then return false end
        return applyMoves(player, {}, { { moneyItems.gold.unit, amount } })
    end

    local centName = moneyItems[moneytype].cent
    local dollarName = moneyItems[moneytype].dollar

    local availableDollars = inventoryMoney[moneyMap[dollarName]] or 0
    local availableCents = inventoryMoney[moneyMap[centName]] or 0
    local totalAvailableCents = (availableDollars * 100) + availableCents
    local requiredCents = math.floor(amount * 100 + 0.5)

    if totalAvailableCents < requiredCents then
        return false
    end

    if requiredCents <= availableCents then
        return applyMoves(player, {}, { { centName, requiredCents } })
    end

    -- every cent goes, then whole dollars; the change comes back as cents. Net cent change = change - availableCents:
    -- added first when positive (the cents left stay under 100, so ConvertCoins never turns them into dollars).
    local remainingRequired = requiredCents - availableCents
    local dollarsToRemove = math.ceil(remainingRequired / 100)
    local changeInCents = (dollarsToRemove * 100) - remainingRequired
    local centDelta = changeInCents - availableCents

    return applyMoves(player,
        { { centName, math.max(centDelta, 0) } },
        { { centName, math.max(-centDelta, 0) }, { dollarName, dollarsToRemove } })
end

-- the value the items hold, in whole cents (gold: units)
local function itemValue(player, moneytype)
    local money = getInventoryMoney(player.PlayerData)
    if moneytype == 'gold' then return money.gold end
    local dollarName, centName = moneyItems[moneytype].dollar, moneyItems[moneytype].cent
    return (money[moneyMap[dollarName]] or 0) * 100 + (money[moneyMap[centName]] or 0)
end

local function toUnits(moneytype, amount)
    if moneytype == 'gold' then return amount end
    return math.floor(amount * 100 + 0.5)
end

-- set = an add or a remove of the difference, so it takes the same all-or-nothing paths
local function handleSetMoney(player, moneytype, amount)
    local diff = toUnits(moneytype, amount) - itemValue(player, moneytype)
    if diff == 0 then return true end
    local delta = moneytype == 'gold' and math.abs(diff) or math.abs(diff) / 100
    if diff > 0 then return handleAddMoney(player, moneytype, delta) end
    return handleRemoveMoney(player, moneytype, delta)
end

local moneyHandlers = {
    add = handleAddMoney,
    remove = handleRemoveMoney,
    set = handleSetMoney,
}

-- FH (core M2-nit): citizenids with an ApplyMoneyItems in progress. Each item step commits and runs the money-item
-- sync, which used to re-read the half-moved items as the balance and send the HUD a change per step (and a +/- pair
-- for a rolled-back add). While set, SynchronizeMoneyItems leaves the balance alone; player.lua's moveMoney syncs
-- once afterwards and sends the one change event for the whole operation.
local applying = {}

---FH (core M2): called by player.lua AddMoney / RemoveMoney / SetMoney (no longer an RSGCore:Server:OnMoneyChange
---listener, whose result nobody could read). -> true when the items now hold the change, false when nothing moved.
---The item value is checked before and after: only an exact move counts. A partial move (an inventory that changed
---under the handler) is logged, never reported as done.
function ApplyMoneyItems(player, moneytype, amount, operation)
    local handler = moneyHandlers[operation]
    if not handler or not player or not moneyItems[moneytype] then return false end
    local before = itemValue(player, moneytype)
    local want = toUnits(moneytype, amount)
    if operation == 'remove' then want = before - want elseif operation == 'add' then want = before + want end
    local cid = player.PlayerData.citizenid
    applying[cid] = true
    local ran, result = pcall(handler, player, moneytype, amount)
    applying[cid] = nil
    if not ran then print(('^1[rsg-core] money items %s %s %s failed: %s^7'):format(operation, amount, moneytype, tostring(result))) end
    local done = ran and result == true
    local after = itemValue(player, moneytype)
    refreshInventory(player.PlayerData.source)
    if done and after == want then return true end
    if after ~= before then
        local src = player.PlayerData.source
        print(('^1[rsg-core] money items for %s (%s) moved %s instead of %s (%s %s %s)^7'):format(
            tostring(player.PlayerData.citizenid), tostring(src), after - before, want - before, operation, amount, moneytype))
        TriggerEvent('rsg-log:server:CreateLog', 'moneyitems', 'Money item mismatch', 'red',
            ('**%s** (%s): %s %s %s moved %s units instead of %s'):format(GetPlayerName(src) or 'unknown',
                player.PlayerData.citizenid, operation, amount, moneytype, after - before, want - before))
    end
    return false
end

-----------------------------------------------------------------
-- If config changed, handle inventory items accordingly on login
-----------------------------------------------------------------

local initialized = {}
RegisterNetEvent('RSGCore:Server:OnPlayerLoaded', function()
    local src = source
    local player = RSGCore.Functions.GetPlayer(src)
    if not player then return end
    -- only run once per login; the client could otherwise re-trigger the item <-> balance reset at will
    if initialized[player.PlayerData.citizenid] then return end

    local money = getInventoryMoney(player.PlayerData)

    if RSGCore.Config.Money.EnableMoneyItems then
        local cash = calculateTotal(money.cashDollars, money.cashCents)
        local bloodmoney = calculateTotal(money.bloodDollars, money.bloodCents)

        if cash ~= player.PlayerData.money.cash then
            ApplyMoneyItems(player, 'cash', player.PlayerData.money.cash, 'set')
        end

        if bloodmoney ~= player.PlayerData.money.bloodmoney then
            ApplyMoneyItems(player, 'bloodmoney', player.PlayerData.money.bloodmoney, 'set')
        end
    else
        removeItems(player, moneyItems.cash.cent, math.huge, 'money-item-cleanup')
        removeItems(player, moneyItems.cash.dollar, math.huge, 'money-item-cleanup')
        removeItems(player, moneyItems.bloodmoney.cent, math.huge, 'money-item-cleanup')
        removeItems(player, moneyItems.bloodmoney.dollar, math.huge, 'money-item-cleanup')
    end

    if RSGCore.Config.Gold.EnableGoldItems then
        if money.gold ~= player.PlayerData.money.gold then
            ApplyMoneyItems(player, 'gold', player.PlayerData.money.gold, 'set')
        end
    else
        removeItems(player, moneyItems.gold.unit, math.huge, 'gold-item-cleanup')
    end

    -- failsafe to prevent early override by synchronization
    initialized[player.PlayerData.citizenid] = true
end)

local function clearInitialized(src)
    local player = RSGCore.Functions.GetPlayer(src)
    if player then initialized[player.PlayerData.citizenid] = nil end
end

AddEventHandler('RSGCore:Server:OnPlayerUnload', clearInitialized)
AddEventHandler('RSGCore:Server:PlayerDropped', function(player)
    initialized[player.PlayerData.citizenid] = nil
end)

-------------------------------------------------------------
-- Enable handlers and synchronization when enabled in config
-------------------------------------------------------------

function IsMoneyItemEnabled(moneytype)
    if moneytype == 'gold' then
        return RSGCore.Config.Gold.EnableGoldItems
    end

    return RSGCore.Config.Money.EnableMoneyItems
        and (moneytype == 'cash' or moneytype == 'bloodmoney')
end

if RSGCore.Config.Money.EnableMoneyItems or RSGCore.Config.Gold.EnableGoldItems then

    -- FH (core M2-nit): the balance still snaps to the items, but float residue (4.90 - 2.95 = 1.9500000000000002 vs
    -- the items' 1.95) is not a HUD change; only a move of at least a cent is shown
    local function hudChange(src, moneytype, new, old)
        local diff = math.abs(math.floor(new * 100 + 0.5) - math.floor(old * 100 + 0.5))
        if diff > 0 then TriggerClientEvent('hud:client:OnMoneyChange', src, moneytype, diff / 100, new < old) end
    end

    function SynchronizeMoneyItems(playerData)
        if not initialized[playerData.citizenid] or applying[playerData.citizenid] then return playerData end

        local money = getInventoryMoney(playerData)

        if RSGCore.Config.Money.EnableMoneyItems then
            local cash = calculateTotal(money.cashDollars, money.cashCents)
            local bloodmoney = calculateTotal(money.bloodDollars, money.bloodCents)

            if cash ~= playerData.money.cash then
                local old = playerData.money.cash or 0
                playerData.money.cash = cash
                hudChange(playerData.source, 'cash', cash, old)
            end

            if bloodmoney ~= playerData.money.bloodmoney then
                local old = playerData.money.bloodmoney or 0
                playerData.money.bloodmoney = bloodmoney
                hudChange(playerData.source, 'bloodmoney', bloodmoney, old)
            end
        end

        if RSGCore.Config.Gold.EnableGoldItems and money.gold ~= playerData.money.gold then
            local old = playerData.money.gold or 0
            playerData.money.gold = money.gold
            TriggerClientEvent('hud:client:OnMoneyChange', playerData.source, 'gold', math.abs(money.gold - old), money.gold < old)
        end

        return playerData
    end

end

