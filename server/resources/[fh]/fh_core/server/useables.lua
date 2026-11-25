-- fh_core useables (core-08 P2): use handlers for the medical / tonic / money-clip items that loot and the starter kit
-- hand out. They were useable=true in rsg-core with no handler, so pressing use did nothing (audit H2).
-- Registered via rsg-core CreateUseableItem (pattern + re-register on rsg-core restart: fh_survival/server/actions.lua).
-- Health / stamina are client natives: the server validates and consumes the item, THEN tells the client to apply the
-- effect (fh:core:useable:restore). The client never names the item or the amount.
-- Money clips pay through fh_economy first and are consumed only after the payment succeeded (a failed consume is
-- charged back).

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

local function giveBack(src, item)
    local ok, added = pcall(function() return inv():AddItem(src, item.name, 1, nil, item.info, 'fh_core clip give-back') end)
    return ok and added and true or false
end

local function playerOf(src)
    local ok, p = pcall(function() return exports['rsg-core']:GetCoreObject().Functions.GetPlayer(src) end)
    return ok and p or nil
end

local function clipInner(src, item, clip)
    local amount = tonumber(item.info and item.info.amount)
    if not (amount and amount > 0) then amount = math.random(clip.min, clip.max) end
    local cents = math.floor(amount * 100 + 0.5)
    if cents <= 0 then notify(src, 'That clip is empty.', 'error') return end
    amount = cents / 100 -- whole cents
    -- Remove first (synchronous, exact slot), verify, THEN pay: never pay without a confirmed removal, so the clip
    -- cannot be moved while pay yields and then also pay out.
    if not consume(src, item.name, item.slot, 'fh_core use') then
        notify(src, "You can't use that right now.", 'error')
        return
    end
    local paid, why = false, nil
    if clip.moneyType then
        -- blood money is not ledgered cash: rsg-core AddMoney (false = items did not fit, balance restored)
        local p = playerOf(src)
        local ok, res = pcall(function() return p and p.Functions.AddMoney(clip.moneyType, amount, clip.reason) end)
        paid, why = ok and res and true or false, 'addmoney_refused'
    else
        local ok, res, err = pcall(function() return exports.fh_economy:pay(src, amount, clip.reason) end)
        paid, why = ok and res and true or false, ok and err or res
    end
    if paid then notify(src, ('You find $%.2f in the clip.'):format(amount), 'success') return end
    print(('[fh_core] useables: pay for %s refused for %s: %s'):format(item.name, tostring(src), tostring(why)))
    if giveBack(src, item) then
        notify(src, "You can't use that right now.", 'error')
        return
    end
    -- the clip will not go back (full bag): cash is credited instead (offline-safe, whole cents); blood money has no fallback
    local p = playerOf(src)
    local cid = p and p.PlayerData and p.PlayerData.citizenid
    local cok, credited = false, false
    if not clip.moneyType and cid then
        cok, credited = pcall(function() return exports.fh_economy:credit(cid, amount, clip.reason .. '_giveback') end)
    end
    print(('[fh_core] useables: give-back of %s to %s FAILED; credit %s'):format(item.name, tostring(src), (cok and credited) and 'ok' or 'not paid'))
    notify(src, (cok and credited) and ('Your bag is full: $%.2f was paid instead.'):format(amount) or "You can't use that right now.", 'error')
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

local function names()
    local list = {}
    for n in pairs(C.heal) do list[#list + 1] = n end
    for n in pairs(C.clips) do list[#list + 1] = n end
    table.sort(list)
    return list
end

local function register()
    for _, name in ipairs(names()) do
        local ok, err = pcall(function() exports['rsg-core']:CreateUseableItem(name, onUse) end)
        if not ok then print(('[fh_core] CreateUseableItem %s failed: %s'):format(name, tostring(err))) end
    end
end

AddEventHandler('playerDropped', function() lastUse[source] = nil clipBusy[source] = nil end)

AddEventHandler('onResourceStart', function(res)
    if res == GetCurrentResourceName() then
        CreateThread(register)
    elseif res == 'rsg-core' then
        register() -- rsg-core restart wipes its useable table
    end
end)
