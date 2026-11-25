-- fh_tailor client (progression-03 T2):
-- 1. Ped outfit apply on rsg-character:client:ApplySkin + spawn + fh:tailor:apply, gated by Config.FittedOutfits.
--    When FittedOutfits is false, nothing is applied to the ped so rsg-character stays completely untouched.
-- 2. [E]/[G] prompts at tailor stops and [G] at homestead chests. They only ask the server to open the fh_ui `tailor` /
--    `wardrobe` screens (server/ui.lua openShop / openWardrobe: range guard + debounce live there). References
--    fh_homestead read-only. The client sends only a shop id; the server validates everything.
-- 3. Mirror preview for those screens (client/preview.lua guard): previewLook is local and cosmetic, and it is always
--    reverted when the screen goes away (see the guard's header for every path).
-- Natives: SetPedOutfitPreset (rsg-character charselect.lua:194, functions.lua:332-337), 0xD3A7B003ED343FD9
-- (ApplyShopItemToPed, rsg-character clothes.lua:69), 0xCC8CA3E88256E58F (UpdatePedVariation, functions.lua:1143),
-- IsControlJustReleased (E = 0xCEFD9220, G = 0x760A9C6F).
local cfg = FhTailorConfig
local logic = FhTailorLogic

local INPUT_CONTEXT = 0xCEFD9220  -- E (same as fh_homestead / fh_hunting)
local INPUT_WARDROBE = 0x760A9C6F -- G (wardrobe: tailor stops and homestead chests, so [E] chest is not shadowed)

local points = {}
local shownText = nil
local applySeq = 0
local lastLook = nil
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
local function previewLook(look)
    if not applyLook(look, true) then return false end
    applySeq = applySeq + 1 -- cancels a pending apply / revert that is still waiting on the server
    previewing = true
    return true
end
exports('previewLook', previewLook)

---Undo a preview. Flag on: re-applies the saved look (server's worn look, else the last one pushed; `noWait` skips the
---server ask and uses the last pushed one, for resource stop). Flag off: nothing is applied normally, so a previewed ped
---is restored by reloading the character's saved skin through rsg-character's ApplySkin export (it swaps the ped model
---briefly). Flag off and nothing previewed: does nothing.
---@return boolean reverted
local function revertLook(noWait)
    if cfg.FittedOutfits then
        applySeq = applySeq + 1
        local seq = applySeq
        previewing = false
        local look = lastLook
        if not noWait then
            local fresh = lib.callback.await('fh:tailor:worn', false)
            -- A previewLook or another apply that landed while we waited wins: do not clobber it.
            if seq ~= applySeq or previewing then return false end
            if type(fresh) == 'table' then lastLook = fresh; look = fresh end
        end
        return look ~= nil and applyLook(look)
    end
    if not previewing then return false end
    previewing = false
    local ok = pcall(function() exports['rsg-character']:ApplySkin() end)
    return ok
end
exports('revertLook', function() return revertLook(false) end)

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

-- ---------------------------------------------------------------- mirror preview wiring (fh_ui local events)
-- fh_ui emits these LOCAL client events (never from the server): fh:ui:preview { screen, look } (NUI preview button, shape
-- checked by fh_ui's relay), fh:ui:preview_end { screen } (Stop preview button), fh:ui:closed { screen } (every close path).

local previewGuard = FhTailorPreview.new({
    preview = previewLook,
    revert = function(sync) revertLook(sync == true) end,
    isOpen = function(screen) return exports.fh_ui:isOpen(screen) == true end, -- errors (fh_ui stopped) count as closed
    isDead = function() local ped = PlayerPedId() return ped ~= nil and ped ~= 0 and IsEntityDead(ped) end,
    closeScreen = function(screen) TriggerEvent('fh:ui:close', { screen = screen }) end,
    notice = function(screen, text, kind)
        TriggerEvent('fh:ui:update', { screen = screen, data = { notice = text, notice_kind = kind } })
    end,
})

AddEventHandler('fh:ui:preview', FH.wrap(function(p)
    if type(p) == 'table' then previewGuard.onPreview(p.screen, p.look) end
end))
AddEventHandler('fh:ui:preview_end', FH.wrap(function(p)
    if type(p) == 'table' then previewGuard.onEnd(p.screen) end
end))
AddEventHandler('fh:ui:closed', FH.wrap(function(p)
    if type(p) == 'table' then previewGuard.onClosed(p.screen) end
end))
FH.on('RSGCore:Client:OnPlayerUnload', function() previewGuard.onClosed('*') end)

-- Watchdog: only runs while a preview is on the ped (fh_ui crashed / stopped, screen vanished, player died).
FH.thread(function()
    while true do
        Wait(previewGuard.active() and 500 or 2000)
        if previewGuard.active() then previewGuard.tick() end
    end
end)

-- ---------------------------------------------------------------- interaction points

-- Tailor stops per enabled region: [E] catalog, [G] wardrobe. Both only ask the server to open the fh_ui screen.
FH.thread(function()
    local dist = cfg.promptDistance or 3.0
    for shopId, shop in pairs(cfg.shops) do
        if not (FhRegions and FhRegions.isEnabled) or FhRegions.isEnabled(shop.region_id) then
            local c = shop.coords
            points[#points + 1] = lib.points.new({
                coords = vector3(c.x, c.y, c.z),
                distance = dist,
                onEnter = FH.wrap(function() showText(('[E] %s   [G] Wardrobe'):format(shop.label)) end),
                onExit = FH.wrap(function() hideText() end),
                nearby = FH.wrap(function()
                    if IsControlJustReleased(0, INPUT_CONTEXT) then
                        TriggerServerEvent('fh:tailor:open_shop', shopId)
                    elseif IsControlJustReleased(0, INPUT_WARDROBE) then
                        TriggerServerEvent('fh:tailor:open_wardrobe')
                    end
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
                    if own and IsControlJustReleased(0, INPUT_WARDROBE) then TriggerServerEvent('fh:tailor:open_wardrobe') end
                end),
            })
        end
    end
end)

FH.on('onResourceStop', function(res)
    if res == 'fh_ui' then previewGuard.stop() end
    if res ~= GetCurrentResourceName() then return end
    previewGuard.stop()
    hideText()
    for _, pt in ipairs(points) do pt:remove() end
    points = {}
end)
