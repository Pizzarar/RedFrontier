local RSGCore = exports['rsg-core']:GetCoreObject()
AddEventHandler('RSGCore:Server:UpdateObject', function() RSGCore = exports['rsg-core']:GetCoreObject() end) -- FH

-- Legacy rsg-inventory exports and player methods, so existing RSG scripts keep working.
-- All of these are thin wrappers over the API in server/main.lua.

local API = InvCore.API

local function GetItemsByName(target, name)
    local c = InvCore.GetContainer(target)
    local out = {}
    if not c or not name then return out end
    name = tostring(name):lower()
    for _, it in pairs(c.items) do
        if it.name == name then out[#out + 1] = it end
    end
    table.sort(out, function(a, b) return a.slot < b.slot end)
    return out
end

local function GetSlots(target)
    local c = InvCore.GetContainer(target)
    if not c then return 0, 0 end
    local used = 0
    for _ in pairs(c.items) do used = used + 1 end
    return used, c.slots - used
end

local function GetFreeWeight(target)
    local c = InvCore.GetContainer(target)
    return c and (c.maxWeight - InvCore.TotalWeight(c.items)) or 0
end

-- FH: a whole-layout write is vetoed like any other mutation: every item must sit in a valid slot of the
-- section (equipped / backpack) that accepts its size class, within that section's and the player's weight.
-- A refused layout leaves the inventory untouched. -> true | false, reason
local function SetInventory(src, items)
    local c = InvCore.GetContainer(tonumber(src))
    if not c then return false, 'fh_unknown_container' end
    items = InvCore.Normalize(items)
    local ok, why = InvCore.FhCheckLayout(c, items)
    if not ok then
        InvCore.Log('SetInventory refused', ('%s: %s (caller %s)'):format(tostring(src), tostring(why),
            tostring(GetInvokingResource() or GetCurrentResourceName())))
        InvCore.Refresh(src)
        return false, why
    end
    c.player.Functions.SetPlayerData('items', items)
    InvCore.Refresh(src)
    return true
end

-- FH: item keys SetItemData may not touch (they change where an item fits or how much there is)
local FH_STRUCTURAL = { name = true, slot = true, amount = true, weight = true, unique = true, type = true }

local function SetItemData(src, itemName, key, val)
    local c = InvCore.GetContainer(src)
    if not c or not itemName or not key then return false end
    -- FH: structural keys go through AddItem/RemoveItem/move (and the fh_core veto), never through here
    if FH_STRUCTURAL[key] then return false end
    itemName = tostring(itemName):lower()
    local item
    for _, it in pairs(c.items) do
        if it.name == itemName and (not item or it.slot < item.slot) then item = it end
    end
    if not item then return false end
    item[key] = val
    InvCore.Commit(c)
    InvCore.Refresh(src)
    return true
end

local function GetItemWeight(name)
    local s = InvCore.SharedItem(name)
    return s and s.weight or nil
end

local function CreateInventory(id, data)
    data = data or {}
    API.RegisterStash(id, { label = data.label, slots = data.slots, maxWeight = data.maxweight or data.maxWeight })
end

-- removes the stash from memory AND the database (a later stash with the same id starts empty)
local function DeleteInventory(id)
    if type(id) ~= 'string' then return false end
    if InvCore.FhMeta[id] and not InvCore.FhCallerAllowed() then return false end -- FH: fh_core containers
    local inv = InvCore.Inventories[id]
    if inv and inv.type ~= 'stash' then return false end
    for watcher, openId in pairs(InvCore.OpenInv) do
        if openId == id then API.CloseInventory(watcher) end
    end
    InvCore.Inventories[id] = nil
    InvCore.FhMeta[id] = nil -- FH
    MySQL.prepare('DELETE FROM inventories WHERE identifier = ?', { id })
    return true
end

local function ClearStash(id)
    if type(id) == 'string' and InvCore.FhMeta[id] and not InvCore.FhCallerAllowed() then return end -- FH
    local c = InvCore.GetContainer(id)
    if c and c.type == 'stash' then API.ClearInventory(id) end
end

local function ForceDropItem(src, item, amount, info, reason)
    local ped = GetPlayerPed(src)
    if ped == 0 then return false end
    local id = API.CreateDrop(GetEntityCoords(ped), {})
    if not id then return false end
    if not InvCore.AddTo(InvCore.Inventories[id], item, amount, info) then
        InvCore.RemoveDrop(id)
        return false
    end
    InvCore.Log('ForceDrop', ('%sx %s dropped for %s (%s)'):format(amount or 1, item, GetPlayerName(src), reason or 'unknown'))
    return true
end

exports('CanAddItem', API.CanCarry)
exports('OpenInventoryById', API.OpenPlayerInventory)
exports('GetItemsByName', GetItemsByName)
exports('GetSlots', GetSlots)
exports('GetFreeWeight', GetFreeWeight)
exports('SetInventory', SetInventory)
exports('SetItemData', SetItemData)
exports('GetItemWeight', GetItemWeight)
exports('CreateInventory', CreateInventory)
exports('DeleteInventory', DeleteInventory)
exports('ClearStash', ClearStash)
exports('ForceDropItem', ForceDropItem)

-- the main API (AddItem, RemoveItem, HasItem, OpenInventory, ...)
for name, fn in pairs(API) do exports(name, fn) end

--------------------------------------------------------------------------------
-- Player.Functions.AddItem / RemoveItem / ... (used by rsg-core money items and most scripts)
--------------------------------------------------------------------------------
local function RegisterPlayerMethods(src)
    local methods = {
        AddItem        = function(item, amount, slot, info, reason) return API.AddItem(src, item, amount, slot, info, reason) end,
        RemoveItem     = function(item, amount, slot, reason) return API.RemoveItem(src, item, amount, slot, reason) end,
        GetItemBySlot  = function(slot) return API.GetItemBySlot(src, slot) end,
        GetItemByName  = function(item) return API.GetItemByName(src, item) end,
        GetItemsByName = function(item) return GetItemsByName(src, item) end,
        ClearInventory = function(keep) return API.ClearInventory(src, keep) end,
        SetInventory   = function(items) return SetInventory(src, items) end,
    }
    for name, fn in pairs(methods) do
        RSGCore.Functions.AddPlayerMethod(src, name, fn)
    end
end

AddEventHandler('RSGCore:Server:PlayerLoaded', function(Player)
    RegisterPlayerMethods(Player.PlayerData.source)
end)

AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    for src in pairs(RSGCore.Functions.GetRSGPlayers()) do
        RegisterPlayerMethods(src)
    end
end)
