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

local function applyLook(look)
    if not cfg.FittedOutfits then return end
    local plan = logic.resolveApply(cfg, look)
    if not plan then return end
    local ped = PlayerPedId()
    if not ped or ped == 0 or not DoesEntityExist(ped) then return end
    -- Replaces rsg-character clothes with the fitted outfit preset; face/body stay as rsg-character set them.
    SetPedOutfitPreset(ped, plan.preset, true)
    for _, comp in ipairs(plan.components) do
        local hash = type(comp) == 'number' and comp or joaat(comp)
        if hash and hash ~= 0 then
            Citizen.InvokeNative(0xD3A7B003ED343FD9, ped, hash, false, true, true)
        end
    end
    Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)
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

local function openWardrobeMenu(returnShopId)
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

local function openTailorMenu(shopId)
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
    elseif res.action == 'save_outfit' then
        notify(('Saved outfit to slot %s.'):format(tostring(res.slot)), 'success')
    elseif res.action == 'wear_saved' then
        notify(('Equipped saved outfit (slot %s).'):format(tostring(res.slot)), 'success')
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
-- Uses [G] so fh_homestead's own [E] Homestead chest prompt is not shadowed.
FH.thread(function()
    if GetResourceState('fh_homestead') ~= 'started' then return end
    local ok, plots = pcall(function() return lib.callback.await('fh:homestead:plots', false) end)
    if not ok or type(plots) ~= 'table' then return end
    local dist = cfg.homesteadWardrobeDistance or 3.0
    for _, p in ipairs(plots) do
        if type(p) == 'table' and p.coords then
            points[#points + 1] = lib.points.new({
                coords = vector3(p.coords.x, p.coords.y, p.coords.z),
                distance = dist,
                onEnter = FH.wrap(function() showText('[G] Wardrobe') end),
                onExit = FH.wrap(function() hideText() end),
                nearby = FH.wrap(function()
                    if IsControlJustReleased(0, INPUT_WARDROBE) then openWardrobeMenu(nil) end
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
