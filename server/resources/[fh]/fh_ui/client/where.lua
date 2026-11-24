-- fh_ui client: /where command (mapblips). Lists the findable places with their distance, or picks one and marks it
-- as your destination. Pure matching/distance logic is in FhUiPlaces; this file only talks to the game.
--
-- RedM has no SetNewWaypoint native (verified against alloc8or natives.json: only SET_WAYPOINT_OFF 0xFA8C41E8020D3439
-- and IS_WAYPOINT_ACTIVE 0x202B1BBFC6AB5EE4 exist), so `/where <place>` marks the destination with a named blip
-- instead of the pause-map red X. A true GPS route is a queued follow-up if a native is ever found.
--
-- Blip natives, copied from the known-working pattern in rsg-character/client/clothes.lua (CreateBlips, lines 796-823):
--   BLIP_ADD_FOR_COORDS 0x554D9D53F696D002 (STYLE hash, x, y, z) -> blip   first arg is a blip STYLE, not a sprite
--   SetBlipSprite(blip, spriteHash, 1)   [exposed by name]
--   SetBlipScale(blip, scale)            [exposed by name]
--   _SET_BLIP_NAME      0x9CB1A1623062F402 (blip, name)   plain string, not a VarString
--   RemoveBlip(blip)                     [exposed by name]  REMOVE_BLIP 0xF2C3C9DA47AAA54A takes Blip* (pointer)
-- Style 1664425300 = BLIP_STYLE_PICKUP_WEAPON (base style rsg-character uses; the sprite is overridden anyway).
local P = FhUiPlaces

local BLIP_ADD_FOR_COORDS = 0x554D9D53F696D002
local BLIP_STYLE = 1664425300 -- BLIP_STYLE_PICKUP_WEAPON
local _SET_BLIP_NAME = 0x9CB1A1623062F402

local dest = nil -- the current /where destination blip

local function playerPos()
    local ok, c = pcall(function() return GetEntityCoords(PlayerPedId()) end)
    if ok and c then return { x = c.x + 0.0, y = c.y + 0.0, z = c.z + 0.0 } end
    return nil
end

local function chat(msg) TriggerEvent('chat:addMessage', { args = { 'fh', msg } }) end

local function distText(place, player)
    local d = P.distance(place, player)
    if d == nil then return '' end
    return ('%d m'):format(math.floor(d + 0.5))
end

-- The lane configs, read from the `@`-includes (read-only). nil when a lane did not provide one.
local function sources()
    return {
        homestead = FhHomesteadConfig, trade = FhTradeConfig, hunting = FhHuntingConfig,
        zones = FhZonesConfig, crafting = FhCraftingConfig, fence = FhFenceConfig,
        quests = { givers = FhQuestsGivers, boards = FhQuestsBoardSpots },
    }
end

-- Claimed homestead plots, from the read-only `fh:ui:plot_claims` callback (fh_ui server -> fh_homestead getClaims).
-- nil when the fetch fails (then every plot looks unclaimed, same as before).
local function claimedSet()
    local claimed
    if lib and lib.callback then
        local ok, list = pcall(function() return lib.callback.await('fh:ui:plot_claims', false) end)
        if ok and type(list) == 'table' then
            claimed = {}
            for _, id in ipairs(list) do claimed[id] = true end
        end
    end
    return claimed
end

local function setDest(place)
    if dest then RemoveBlip(dest) end
    dest = Citizen.InvokeNative(BLIP_ADD_FOR_COORDS, BLIP_STYLE, place.x + 0.0, place.y + 0.0, place.z + 0.0)
    if dest and dest ~= 0 then
        SetBlipSprite(dest, joaat(P.sprite(place)), 1)
        SetBlipScale(dest, 1.0)
        Citizen.InvokeNative(_SET_BLIP_NAME, dest, 'Destination: ' .. place.label)
    end
end

local function run(query)
    local player = playerPos()
    local places = P.gather(sources(), { claimed = claimedSet() })

    if (query or ''):gsub('%s+', '') == '' then
        local rows = P.list(places, player)
        if #rows == 0 then return chat('/where: no places known') end
        for _, r in ipairs(rows) do
            chat(('%s (%s)%s'):format(r.label, r.id, r.dist and (' — ' .. ('%d m'):format(math.floor(r.dist + 0.5))) or ''))
        end
        return
    end

    local place, why = P.pick(places, query, player)
    if not place then
        if why == 'all_claimed' then return chat('/where plot: every plot is claimed') end
        if why == 'none' then return chat('/where: no place of that kind') end
        return chat('/where: unknown place "' .. query .. '"')
    end
    chat(('%s (%s): %s'):format(place.label, place.id, distText(place, player)))
    setDest(place)
end

RegisterCommand('where', function(_, args)
    local query = args and table.concat(args, ' ') or ''
    FH.thread(function() run(query) end)
end, false)

FH.on('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if dest then RemoveBlip(dest) end
    dest = nil
end)
