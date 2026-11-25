-- fh_tailor client (progression-03 T2):
-- 1. Ped outfit apply on rsg-character:client:ApplySkin + spawn + fh:tailor:apply, gated by Config.FittedOutfits.
--    When FittedOutfits is false, nothing is applied to the ped so rsg-character stays completely untouched.
-- 2. Stopgap ox_lib shop + wardrobe menus at tailor stops and at homestead chests (references fh_homestead read-only).
--    The server validates everything; this client sends only ids.
-- Natives: SetPedOutfitPreset (rsg-character charselect.lua:194, functions.lua:332-337), 0xD3A7B003ED343FD9
-- (ApplyShopItemToPed, rsg-character clothes.lua:69), 0xCC8CA3E88256E58F (UpdatePedVariation, functions.lua:1143),
-- IsControlJustReleased (E = 0xCEFD9220, G = 0x760A9C6F).
local cfg = FhTailorConfig
local logic = FhTailorLogic

local INPUT_CONTEXT = 0xCEFD9220  -- E (same as fh_homestead / fh_hunting)
local INPUT_WARDROBE = 0x760A9C6F -- G (secondary interact at homestead chests so [E] chest is not shadowed)

local points = {}
local shownText = nil
local applySeq = 0
local lastLook = nil
local pendingWardrobeRefresh = false -- an equip / save / wear fired from a wardrobe menu awaits its result
local previewing = false -- a previewLook is on the ped (cleared by revertLook)

-- ---------------------------------------------------------------- UI helpers

local function showText(text)
    if text ~= shownText then
        shownText = text
        lib.showTextUI(text)
    end
end

local function hideText()
    if shownText then
        shownText = nil
        lib.hideTextUI()
    end
end

local function notify(msg, kind)
    lib.notify({ title = 'Tailor', description = msg, type = kind or 'inform' })
end

local function entryLabel(id)
    local e = type(id) == 'string' and cfg.catalog[id] or nil
    return e and e.label or tostring(id)
end

local function formatLookSummary(look)
    if type(look) ~= 'table' or type(look.outfit) ~= 'string' then return 'None' end
    local parts = { entryLabel(look.outfit) }
    if type(look.items) == 'table' and #look.items > 0 then
        local labels = {}
        for _, id in ipairs(look.items) do labels[#labels + 1] = entryLabel(id) end
        parts[#parts + 1] = '+ ' .. table.concat(labels, ', ')
    end
    return table.concat(parts, ' ')
end

-- ---------------------------------------------------------------- client apply (Config.FittedOutfits)

---@param force boolean|nil preview only: apply even when Config.FittedOutfits is off
---@return boolean applied
local function applyLook(look, force)
    if not cfg.FittedOutfits and not force then return false end
    local plan = logic.resolveApply(cfg, look, force)
    if not plan then return false end
    local ped = PlayerPedId()
    if not ped or ped == 0 or not DoesEntityExist(ped) then return false end
    -- Replaces rsg-character clothes with the fitted outfit preset; face/body stay as rsg-character set them.
    SetPedOutfitPreset(ped, plan.preset, true)
    for _, comp in ipairs(plan.components) do
        local hash = type(comp) == 'number' and comp or joaat(comp)
        if hash and hash ~= 0 then
            Citizen.InvokeNative(0xD3A7B003ED343FD9, ped, hash, false, true, true)
        end
    end
    Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)
    return true
end

local function refreshAndApply(delayMs)
    if not cfg.FittedOutfits then return end
    applySeq = applySeq + 1
    local seq = applySeq
    FH.thread(function()
        if delayMs and delayMs > 0 then Wait(delayMs) end
        if seq ~= applySeq then return end
        local look = lib.callback.await('fh:tailor:worn', false)
        if seq ~= applySeq then return end
        if type(look) == 'table' then
            lastLook = look
            applyLook(look)
        elseif lastLook then
            applyLook(lastLook)
        end
    end)
end

-- Preview API for the @ui mirror screen (README "Client exports"). Local and cosmetic only: nothing is saved or sent.
-- Allowed with Config.FittedOutfits off so a catalog can be previewed before the flag flips; the look is validated
-- against the catalog like any apply (unknown ids / wrong kind -> false), and revertLook undoes it.
---@param look table { outfit = id, items = { id, ... } }
---@return boolean applied
exports('previewLook', function(look)
    if not applyLook(look, true) then return false end
    previewing = true
    return true
end)

---Undo a preview. Flag on: re-applies the saved look (server's worn look, else the last one pushed). Flag off: nothing
---is applied normally, so a previewed ped is restored by reloading the character's saved skin through rsg-character's
---ApplySkin export (it swaps the ped model briefly). Flag off and nothing previewed: does nothing.
---@return boolean reverted
exports('revertLook', function()
    if cfg.FittedOutfits then
        applySeq = applySeq + 1
        previewing = false
        local look = lib.callback.await('fh:tailor:worn', false)
        if type(look) == 'table' then lastLook = look else look = lastLook end
        return look ~= nil and applyLook(look)
    end
    if not previewing then return false end
    previewing = false
    local ok = pcall(function() exports['rsg-character']:ApplySkin() end)
    return ok
end)

FH.onNet('fh:tailor:apply', function(look)
    if type(look) ~= 'table' then return end
    lastLook = look
    applyLook(look)
end)

-- rsg-character's ApplySkin yields while swapping model / applying skin+clothes; wait briefly then re-apply our outfit.
FH.on('rsg-character:client:ApplySkin', function()
    refreshAndApply(cfg.applyDelayMs or 750)
end)

FH.on('RSGCore:Client:OnPlayerLoaded', function()
    refreshAndApply(250)
end)

FH.on('playerSpawned', function()
    refreshAndApply(250)
end)

-- ---------------------------------------------------------------- stopgap ox_lib menus

local function openShopMenu(shopId)
    pendingWardrobeRefresh = false
    local ok, res = lib.callback.await('fh:tailor:stock', false, shopId)
    if not ok then
        return notify(logic.message(res), 'error')
    end
    local options = {}
    if #res.rows == 0 then
        options[#options + 1] = { title = 'Nothing in stock for your current standing.', disabled = true }
    else
        for _, r in ipairs(res.rows) do
            local kindLabel = r.kind == 'outfit' and 'Outfit' or 'Item'
            options[#options + 1] = {
                title = r.label .. (r.owned and ' (Owned)' or ''),
                description = ('%s · %s · Tier %d'):format(logic.formatPrice(r.price), kindLabel, r.min_tier),
                disabled = r.owned,
                onSelect = function()
                    TriggerServerEvent('fh:tailor:buy', { shop_id = shopId, entry_id = r.id })
                end,
            }
        end
    end
    lib.registerContext({
        id = 'fh_tailor_shop',
        title = ('%s (Tier %d)'):format(res.shop.label, res.tier),
        menu = 'fh_tailor_stop',
        options = options,
    })
    lib.showContext('fh_tailor_shop')
end

local function promptSaveSlot(slot, currentLabel, worn)
    local input = lib.inputDialog(('Save Outfit (Slot %d)'):format(slot), {
        { type = 'input', label = 'Outfit Name (optional)', default = currentLabel or '', max = logic.MAX_LABEL },
    })
    if not input then return end
    pendingWardrobeRefresh = true
    TriggerServerEvent('fh:tailor:save_outfit', {
        slot = slot,
        label = input[1] or '',
        outfit_id = worn.outfit,
        items = worn.items or {},
    })
end

local function openOutfitsMenu(data)
    local options = {}
    local wornOutfit = data.worn and data.worn.outfit or nil
    local wornItems = data.worn and data.worn.items or {}
    for _, item in ipairs(data.owned or {}) do
        if item.kind == 'outfit' then
            local wearing = item.id == wornOutfit
            options[#options + 1] = {
                title = item.label .. (wearing and ' (Worn)' or ''),
                description = wearing and 'Currently worn' or 'Equip this outfit',
                disabled = wearing,
                onSelect = function()
                    pendingWardrobeRefresh = true
                    TriggerServerEvent('fh:tailor:equip', { outfit_id = item.id, items = wornItems })
                end,
            }
        end
    end
    if #options == 0 then
        options[#options + 1] = { title = 'No owned outfits.', disabled = true }
    end
    lib.registerContext({
        id = 'fh_tailor_outfits',
        title = 'Owned Outfits',
        menu = 'fh_tailor_wardrobe',
        options = options,
    })
    lib.showContext('fh_tailor_outfits')
end

local function openItemsMenu(data)
    local options = {}
    local wornOutfit = data.worn and data.worn.outfit or nil
    local wornItems = data.worn and data.worn.items or {}
    local wornSet = {}
    for _, id in ipairs(wornItems) do wornSet[id] = true end
    for _, item in ipairs(data.owned or {}) do
        if item.kind == 'item' then
            local wearing = wornSet[item.id] == true
            options[#options + 1] = {
                title = item.label .. (wearing and ' (Worn)' or ''),
                description = wearing and 'Click to remove' or 'Click to wear over current outfit',
                disabled = wornOutfit == nil,
                onSelect = function()
                    local nextItems, action = logic.toggleItem(wornItems, item.id, data.maxItems)
                    if action == 'full' then
                        return notify(logic.message('too_many_items'), 'error')
                    end
                    pendingWardrobeRefresh = true
                    TriggerServerEvent('fh:tailor:equip', { outfit_id = wornOutfit, items = nextItems })
                end,
            }
        end
    end
    if #options == 0 then
        options[#options + 1] = { title = 'No owned accessories.', disabled = true }
    end
    lib.registerContext({
        id = 'fh_tailor_items',
        title = ('Accessories (%d/%d)'):format(#wornItems, data.maxItems or 0),
        menu = 'fh_tailor_wardrobe',
        options = options,
    })
    lib.showContext('fh_tailor_items')
end

local function openSlotMenu(slot, savedEntry, worn)
    local title = (savedEntry.label and savedEntry.label ~= '') and savedEntry.label or ('Slot ' .. slot)
    local options = {
        {
            title = 'Wear',
            description = savedEntry.valid and formatLookSummary(savedEntry) or 'Unavailable (missing piece)',
            disabled = not savedEntry.valid,
            onSelect = function()
                pendingWardrobeRefresh = true
                TriggerServerEvent('fh:tailor:wear_saved', { slot = slot })
            end,
        },
        {
            title = 'Overwrite with Current Look',
            description = worn and formatLookSummary(worn) or 'Equip an outfit first',
            disabled = worn == nil,
            onSelect = function()
                promptSaveSlot(slot, savedEntry.label, worn)
            end,
        },
    }
    lib.registerContext({
        id = 'fh_tailor_slot',
        title = title,
        menu = 'fh_tailor_saved',
        options = options,
    })
    lib.showContext('fh_tailor_slot')
end

local function openSavedMenu(data)
    local options = {}
    local maxSaved = data.maxSaved or 0
    for slot = 1, maxSaved do
        local s = data.saved and data.saved[slot] or nil
        if s then
            local name = (s.label and s.label ~= '') and s.label or ('Slot ' .. slot)
            options[#options + 1] = {
                title = ('%d. %s%s'):format(slot, name, s.valid and '' or ' (Unavailable)'),
                description = formatLookSummary(s),
                onSelect = function()
                    openSlotMenu(slot, s, data.worn)
                end,
            }
        else
            options[#options + 1] = {
                title = ('%d. Empty Slot'):format(slot),
                description = data.worn and 'Save current look here' or 'Equip an outfit first',
                disabled = data.worn == nil,
                onSelect = function()
                    promptSaveSlot(slot, '', data.worn)
                end,
            }
        end
    end
    lib.registerContext({
        id = 'fh_tailor_saved',
        title = 'Saved Outfits',
        menu = 'fh_tailor_wardrobe',
        options = options,
    })
    lib.showContext('fh_tailor_saved')
end

local wardrobeReturnShop = nil
local refreshWardrobeMenu

local function openWardrobeMenu(returnShopId)
    wardrobeReturnShop = returnShopId
    local ok, data = lib.callback.await('fh:tailor:wardrobe', false)
    if not ok then
        return notify(logic.message(data), 'error')
    end
    local summary = formatLookSummary(data.worn)
    if not data.fitted then summary = summary .. ' (preview off)' end
    local options = {
        { title = 'Currently Wearing', description = summary, disabled = true },
        {
            title = 'Outfits',
            description = 'Equip an owned outfit',
            onSelect = function() openOutfitsMenu(data) end,
        },
    }
    if (data.maxItems or 0) > 0 then
        options[#options + 1] = {
            title = 'Accessories',
            description = 'Wear or remove single items over your outfit',
            onSelect = function() openItemsMenu(data) end,
        }
    end
    options[#options + 1] = {
        title = 'Saved Outfits',
        description = 'Save your current look or wear a saved slot',
        onSelect = function() openSavedMenu(data) end,
    }
    lib.registerContext({
        id = 'fh_tailor_wardrobe',
        title = 'Wardrobe',
        menu = returnShopId and 'fh_tailor_stop' or nil,
        options = options,
    })
    lib.showContext('fh_tailor_wardrobe')
end

-- ox_lib clears the open context menu BEFORE onSelect runs, so we cannot ask "is our menu open". Instead the wardrobe
-- sub-menus set pendingWardrobeRefresh when they fire equip / save / wear; the result reopens the wardrobe with fresh
-- (Worn) labels unless another menu has been opened meanwhile.
refreshWardrobeMenu = function()
    if not pendingWardrobeRefresh then return end
    pendingWardrobeRefresh = false
    if lib.getOpenContextMenu and lib.getOpenContextMenu() then return end
    FH.thread(function() openWardrobeMenu(wardrobeReturnShop) end)
end

local function openTailorMenu(shopId)
    pendingWardrobeRefresh = false
    local shop = cfg.shops[shopId]
    if not shop then return end
    lib.registerContext({
        id = 'fh_tailor_stop',
        title = shop.label,
        options = {
            {
                title = 'Browse Catalog',
                description = 'View stock and buy outfits or items',
                onSelect = function() openShopMenu(shopId) end,
            },
            {
                title = 'Open Wardrobe',
                description = 'Change outfits, accessories, and saved looks',
                onSelect = function() openWardrobeMenu(shopId) end,
            },
        },
    })
    lib.showContext('fh_tailor_stop')
end

-- ---------------------------------------------------------------- server action feedback

FH.onNet('fh:tailor:result', function(res)
    if type(res) ~= 'table' then return end
    if not res.ok then
        pendingWardrobeRefresh = false
        return notify(logic.message(res.code), 'error')
    end
    if res.action == 'buy' then
        if res.unverified then
            notify(logic.message('charge_unavailable'), 'warning')
        else
            notify(('Purchased %s (%s).'):format(entryLabel(res.entry_id), logic.formatPrice(res.price)), 'success')
        end
    elseif res.action == 'equip' then
        notify(('Equipped %s.'):format(entryLabel(res.outfit_id)), 'success')
        refreshWardrobeMenu()
    elseif res.action == 'save_outfit' then
        notify(('Saved outfit to slot %s.'):format(tostring(res.slot)), 'success')
        refreshWardrobeMenu()
    elseif res.action == 'wear_saved' then
        notify(('Equipped saved outfit (slot %s).'):format(tostring(res.slot)), 'success')
        refreshWardrobeMenu()
    end
end)

-- ---------------------------------------------------------------- interaction points

-- Tailor stops per enabled region.
FH.thread(function()
    local dist = cfg.promptDistance or 3.0
    for shopId, shop in pairs(cfg.shops) do
        if not (FhRegions and FhRegions.isEnabled) or FhRegions.isEnabled(shop.region_id) then
            local c = shop.coords
            points[#points + 1] = lib.points.new({
                coords = vector3(c.x, c.y, c.z),
                distance = dist,
                onEnter = FH.wrap(function() showText('[E] ' .. shop.label) end),
                onExit = FH.wrap(function() hideText() end),
                nearby = FH.wrap(function()
                    if IsControlJustReleased(0, INPUT_CONTEXT) then openTailorMenu(shopId) end
                end),
            })
        end
    end
end)

-- Homestead wardrobe: references fh_homestead's chest points read-only (does not edit fh_homestead).
-- Uses [G] so fh_homestead's own [E] Homestead chest prompt is not shadowed. The prompt shows only at a chest of one of
-- the player's OWN plots (server callback fh:tailor:own_plots, asked on entering the chest radius so a fresh claim counts).
FH.thread(function()
    local plots
    for _ = 1, 60 do -- fh_homestead may start after us (or its callback not be registered yet): retry for ~5 min
        if GetResourceState('fh_homestead') == 'started' then
            local ok, res = pcall(function() return lib.callback.await('fh:homestead:plots', false) end)
            if ok and type(res) == 'table' then plots = res break end
        end
        Wait(5000)
    end
    if not plots then return end
    local dist = cfg.homesteadWardrobeDistance or 3.0
    for _, p in ipairs(plots) do
        if type(p) == 'table' and type(p.id) == 'string' and p.coords then
            local own, inside = false, false
            points[#points + 1] = lib.points.new({
                coords = vector3(p.coords.x, p.coords.y, p.coords.z),
                distance = dist,
                onEnter = FH.wrap(function()
                    own, inside = false, true
                    FH.thread(function()
                        local ids = lib.callback.await('fh:tailor:own_plots', false)
                        if type(ids) == 'table' then
                            for _, id in ipairs(ids) do if id == p.id then own = true end end
                        end
                        if not inside then own = false end
                        if own then showText('[G] Wardrobe') end
                    end)
                end),
                onExit = FH.wrap(function() own, inside = false, false; hideText() end),
                nearby = FH.wrap(function()
                    if own and IsControlJustReleased(0, INPUT_WARDROBE) then openWardrobeMenu(nil) end
                end),
            })
        end
    end
end)

FH.on('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    hideText()
    for _, pt in ipairs(points) do pt:remove() end
    points = {}
end)
