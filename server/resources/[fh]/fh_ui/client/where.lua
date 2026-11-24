-- fh_ui client: /where command (mapblips). Lists the findable places with their distance, or picks one and marks it
-- as your destination. Pure matching/distance logic is in FhUiPlaces; this file only talks to the game.
--
-- RedM has no SetNewWaypoint native (verified against alloc8or natives.json: only SET_WAYPOINT_OFF 0xFA8C41E8020D3439
-- and IS_WAYPOINT_ACTIVE 0x202B1BBFC6AB5EE4 exist), so `/where <place>` marks the destination with a named blip
-- instead of the pause-map red X. A true GPS route is a queued follow-up if a native is ever found.
--
-- Natives (hashes verified against alloc8or rdr3-nativedb-data natives.json):
--   BLIP_ADD_FOR_COORDS 0x554D9D53F696D002 (blipHash, x, y, z) -> blip
--   _SET_BLIP_NAME      0x9CB1A1623062F402 (blip, name string)
--   SET_BLIP_SCALE      0xD38744167B2FA257 (blip, scale)
--   DOES_BLIP_EXIST     0xCD82FA174080B3B1 (blip)
--   REMOVE_BLIP         0xF2C3C9DA47AAA54A (blip)
local P = FhUiPlaces

local BLIP_ADD_FOR_COORDS = 0x554D9D53F696D002
local _SET_BLIP_NAME = 0x9CB1A1623062F402
local SET_BLIP_SCALE = 0xD38744167B2FA257
local DOES_BLIP_EXIST = 0xCD82FA174080B3B1
local REMOVE_BLIP = 0xF2C3C9DA47AAA54A

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

local function setDest(place)
    if dest and Citizen.InvokeNative(DOES_BLIP_EXIST, dest) then Citizen.InvokeNative(REMOVE_BLIP, dest) end
    dest = Citizen.InvokeNative(BLIP_ADD_FOR_COORDS, joaat(P.sprite(place)), place.x + 0.0, place.y + 0.0, place.z + 0.0)
    if dest and dest ~= 0 then
        Citizen.InvokeNative(_SET_BLIP_NAME, dest, 'Destination: ' .. place.label)
        Citizen.InvokeNative(SET_BLIP_SCALE, dest, 1.0)
    end
end

local function run(query)
    local player = playerPos()
    local places = P.gather({
        homestead = FhHomesteadConfig, trade = FhTradeConfig, hunting = FhHuntingConfig,
        zones = FhZonesConfig, crafting = FhCraftingConfig, fence = FhFenceConfig,
        quests = { givers = FhQuestsGivers, boards = FhQuestsBoardSpots },
    })

    local q = type(query) == 'string' and query or ''
    if q:gsub('%s+', '') == '' then
        local rows = P.list(places, player)
        if #rows == 0 then return chat('/where: no places known') end
        for _, r in ipairs(rows) do
            chat(('%s (%s)%s'):format(r.label, r.id, r.dist and (' — ' .. ('%d m'):format(math.floor(r.dist + 0.5))) or ''))
        end
        return
    end

    local place, why = P.pick(places, q, player)
    if not place then
        if why == 'all_claimed' then return chat('/where plot: every plot is claimed') end
        if why == 'none' then return chat('/where: no place of that kind') end
        return chat('/where: unknown place "' .. q .. '"')
    end
    chat(('%s (%s): %s'):format(place.label, place.id, distText(place, player)))
    setDest(place)
end

RegisterCommand('where', function(_, args)
    run(args and args[1])
end, false)
