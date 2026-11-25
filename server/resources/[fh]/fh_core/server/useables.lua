-- fh_core useables (core-08 P2): use handlers for the medical / tonic / money-clip items that loot and the starter kit
-- hand out. They were useable=true in rsg-core with no handler, so pressing use did nothing (audit H2).
-- Registered via rsg-core CreateUseableItem (pattern + re-register on rsg-core restart: fh_survival/server/actions.lua).
-- Health / stamina are client natives: the server validates and consumes the item, THEN tells the client to apply the
-- effect (fh:core:useable:restore). The client never names the item or the amount.
-- Money clips are removed FIRST (exact slot, confirmed), under a per-player in-flight lock, and only then paid: cash through
-- fh_economy:pay, blood money through rsg-core AddMoney('bloodmoney') with a balance check. A refused payment gives the
-- clip back, but only to the same character (citizenid captured before the removal); otherwise cash clips are credited.

local DEFAULTS = {
    -- hp = fraction of max health restored, stamina = fraction of max stamina restored
    heal = {
        bandage       = { hp = 0.15 },
        fieldbandage  = { hp = 0.25 },
        firstaid      = { hp = 0.60 },
        tonic_healing = { hp = 0.40 },
        tonic_stamina = { stamina = 0.60 },
        tonic_energy  = { hp = 0.10, stamina = 0.40 },
    },
    -- money clips: item.info.amount (whole cents, positive) if present, else a random whole-cent sum in [min, max]
    clips = {
        money_clip       = { min = 5, max = 25, reason = 'money_clip' },
        blood_money_clip = { min = 5, max = 25, reason = 'blood_money_clip', moneyType = 'bloodmoney' },
    },
    cooldown = 1.0, -- seconds between uses per player (double-fire guard)
}

local C = (type(FhCoreUseables) == 'table') and FhCoreUseables or DEFAULTS
local lastUse = {}

local function now() return GetGameTimer() / 1000.0 end

local function notify(src, msg, kind)
    TriggerClientEvent('RSGCore:Client:Notify', src, { title = 'Frontier', description = msg, type = kind or 'inform', duration = 4000 })
end

local function inv() return exports['rsg-inventory'] end

local function liveItem(src, name, slot)
    local ok, item = pcall(function()
        if slot then
            local it = inv():GetItemBySlot(src, slot)
            if it and it.name == name then return it end
        end
        return inv():GetItemByName(src, name)
    end)
    return ok and item or nil
end

local function consume(src, name, slot, why)
    local ok, removed = pcall(function() return inv():RemoveItem(src, name, 1, slot, why) end)
    return ok and removed and true or false
end

local function alive(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    local ok, hp = pcall(GetEntityHealth, ped)
    return ok and type(hp) == 'number' and hp > 0 -- fail closed: no reading, no heal
end

local function onHeal(src, item, eff)
    if not alive(src) then notify(src, "You can't do that right now.", 'error') return end
    -- consume first, effect after: a failed inventory update never gives a free heal
    if not consume(src, item.name, item.slot, 'fh_core use') then
        print(('[fh_core] useables: RemoveItem %s failed for %s; nothing granted'):format(item.name, tostring(src)))
        notify(src, "You can't use that right now.", 'error')
        return
    end
    TriggerClientEvent('fh:core:useable:restore', src, { hp = eff.hp or 0, stamina = eff.stamina or 0 })
end

local clipBusy = {} -- [src] = true while a clip is in flight (pay yields; one clip at a time per player)

-- Unload window, mirroring fh_economy's unloadTracker (fh_economy/server/main.lua:17-36; it exports nothing for this).
-- rsg-core's Logout fires OnPlayerUnload, SAVES, then Wait(200)s with Players[src] still set: anything removed from or
-- given to that in-memory character after the save is lost, and a credit on top of a clip the DB still holds would dupe.
-- unloadCid[src] = citizenid from the unload event until a character loads on the src again (or it settles after a drop);
-- unloadSeq[src] = stamp of the latest mark, from one global counter that only grows, so "an unload began while pay
-- yielded" is visible even if the flag was cleared since, and a stamp never repeats after the entry is dropped.
local unloadCid, unloadSeq = {}, {}
local unloadGen = 0
local function markUnload(src, cid)
    src = tonumber(src)
    if not src or not cid then return end
    unloadCid[src] = cid
    unloadGen = unloadGen + 1
    unloadSeq[src] = unloadGen
end
-- Re-check delay after playerDropped (fh_economy's UNLOAD_SETTLE_MS): well past rsg-core's Logout Wait(200) and its
-- drop-time save.
local UNLOAD_SETTLE_MS = 5000
local function unloadBlocks(src, cid) return unloadCid[src] ~= nil and unloadCid[src] == cid end

local function giveBack(src, item)
    local ok, added = pcall(function() return inv():AddItem(src, item.name, 1, nil, item.info, 'fh_core clip give-back') end)
    return ok and added and true or false
end

local function playerOf(src)
    local ok, p = pcall(function() return exports['rsg-core']:GetCoreObject().Functions.GetPlayer(src) end)
    return ok and p or nil
end

local function cents(x) return math.floor((tonumber(x) or 0) * 100 + 0.5) end

-- AddMoney twin of fh_economy's addMoneyChecked (integer cents, never float compare): a false return is refused; a throw
-- after the balance moved still counts as paid, else the clip would be given back on top of the money.
local function addChecked(Player, moneyType, amount, reason)
    local before = cents(Player.PlayerData.money and Player.PlayerData.money[moneyType])
    local called, added = pcall(Player.Functions.AddMoney, moneyType, amount, reason)
    if called then return added == true end
    local after = cents(Player.PlayerData.money and Player.PlayerData.money[moneyType])
    return after - before == cents(amount)
end

local function clipInner(src, item, clip)
    local amount = tonumber(item.info and item.info.amount)
    if not (amount and amount > 0) then amount = math.random(clip.min, clip.max) end
    local c = cents(amount)
    if c <= 0 then notify(src, 'That clip is empty.', 'error') return end
    amount = c / 100 -- whole cents
    -- who is using it, captured BEFORE anything yields: fail closed without a character
    local p = playerOf(src)
    local cid = p and p.PlayerData and p.PlayerData.citizenid
    if not cid then notify(src, "You can't use that right now.", 'error') return end
    if unloadBlocks(src, cid) then notify(src, "You can't use that right now.", 'error') return end -- fail closed BEFORE consume
    local seq0 = unloadSeq[src] or 0
    -- Remove first (synchronous, exact slot), verify, THEN pay: never pay without a confirmed removal, so the clip
    -- cannot be moved while pay yields and then also pay out.
    if not consume(src, item.name, item.slot, 'fh_core use') then
        notify(src, "You can't use that right now.", 'error')
        return
    end
    local paid, why = false, nil
    if clip.moneyType then
        -- blood money is not ledgered cash: rsg-core AddMoney (false = items did not fit, balance restored)
        paid, why = addChecked(p, clip.moneyType, amount, clip.reason), 'addmoney_refused'
    else
        local ok, res, err = pcall(function() return exports.fh_economy:pay(src, amount, clip.reason) end)
        paid, why = ok and res and true or false, ok and err or res
    end
    if paid then notify(src, ('You find $%.2f in the clip.'):format(amount), 'success') return end
    print(('[fh_core] useables: pay for %s refused for %s: %s'):format(item.name, tostring(src), tostring(why)))
    -- pay may have yielded: the same character must still be on this src before the clip goes back into its bag
    local now_p = playerOf(src)
    -- (an unload that began during the yield counts as gone: the give-back would land in memory already saved)
    local same = now_p and now_p.PlayerData and now_p.PlayerData.citizenid == cid
        and not unloadBlocks(src, cid) and (unloadSeq[src] or 0) == seq0
    if same and giveBack(src, item) then
        notify(src, "You can't use that right now.", 'error')
        return
    end
    -- clip cannot go back (character gone/switched, or full bag): cash is credited to the ORIGINAL character (offline-safe,
    -- whole cents); blood money has no fallback
    local cok, credited = false, false
    if not clip.moneyType then
        cok, credited = pcall(function() return exports.fh_economy:credit(cid, amount, clip.reason .. '_giveback') end)
    end
    print(('[fh_core] useables: give-back of %s to %s (%s) FAILED; credit %s'):format(
        item.name, tostring(src), tostring(cid), (cok and credited) and 'ok' or 'not paid'))
    if same then
        notify(src, (cok and credited) and ('Your bag is full: $%.2f was paid instead.'):format(amount) or "You can't use that right now.", 'error')
    end
end

local function onClip(src, item, clip)
    if clipBusy[src] then return end
    clipBusy[src] = true
    local ok, err = pcall(clipInner, src, item, clip)
    clipBusy[src] = nil -- released on every path, errors included
    if not ok then print(('[fh_core] useables: clip use errored for %s: %s'):format(tostring(src), tostring(err))) end
end

local function onUse(src, item)
    if type(item) ~= 'table' or type(item.name) ~= 'string' then return end
    local t = now()
    if lastUse[src] and t - lastUse[src] < C.cooldown then return end
    lastUse[src] = t
    local live = liveItem(src, item.name, item.slot)
    if not live then return end -- not actually in the inventory: trust the server's view, not the callback arg
    live.slot = live.slot or item.slot
    local eff, clip = C.heal[item.name], C.clips[item.name]
    if eff then onHeal(src, live, eff) elseif clip then onClip(src, live, clip) end
end

local function register()
    -- two literal pairs() loops: tools/check-contracts.py resolves handler names from loops like these
    for name in pairs(C.heal) do
        local ok, err = pcall(function() exports['rsg-core']:CreateUseableItem(name, onUse) end)
        if not ok then print(('[fh_core] CreateUseableItem %s failed: %s'):format(name, tostring(err))) end
    end
    for name in pairs(C.clips) do
        local ok, err = pcall(function() exports['rsg-core']:CreateUseableItem(name, onUse) end)
        if not ok then print(('[fh_core] CreateUseableItem %s failed: %s'):format(name, tostring(err))) end
    end
end

AddEventHandler('RSGCore:Server:OnPlayerUnload', function(src)
    local p = playerOf(tonumber(src))
    markUnload(src, p and p.PlayerData and p.PlayerData.citizenid)
end)
AddEventHandler('RSGCore:Server:PlayerDropped', function(Player)
    local pd = type(Player) == 'table' and Player.PlayerData
    if type(pd) == 'table' then markUnload(pd.source, pd.citizenid) end
end)
AddEventHandler('RSGCore:Server:PlayerLoaded', function(Player)
    local pd = type(Player) == 'table' and Player.PlayerData
    if type(pd) == 'table' and tonumber(pd.source) then unloadCid[tonumber(pd.source)] = nil end
end)
-- Server ids are not reused soon, so a dropped src would keep its unload entries forever (core-09 N1). After the
-- playerDropped native, drop them once rsg-core no longer has the marked character on the src (removed after its
-- save) AND no clip is in flight there (its seq0 compare must keep seeing the mark); otherwise look again later, so
-- the window never reopens. clipBusy is left to onClip, which releases it on every path: clearing it here let the
-- settle run under a clip still yielding in pay.
local function settle(src)
    if unloadCid[src] == nil and unloadSeq[src] == nil then return end
    local p = playerOf(src)
    local cur = p and p.PlayerData and p.PlayerData.citizenid
    if clipBusy[src] or (unloadCid[src] ~= nil and cur == unloadCid[src]) then
        SetTimeout(UNLOAD_SETTLE_MS, function() settle(src) end)
        return
    end
    unloadCid[src], unloadSeq[src] = nil, nil
end
AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    if not src then return end
    lastUse[src] = nil
    local p = playerOf(src)
    if p and p.PlayerData then markUnload(src, p.PlayerData.citizenid) end
    SetTimeout(UNLOAD_SETTLE_MS, function() settle(src) end)
end)

AddEventHandler('onResourceStart', function(res)
    if res == GetCurrentResourceName() then
        CreateThread(register)
    elseif res == 'rsg-core' then
        register() -- rsg-core restart wipes its useable table
    end
end)
