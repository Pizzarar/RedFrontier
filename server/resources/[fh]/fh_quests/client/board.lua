-- Jobs board entry points: `/jobs` and an rsg-target sphere zone (plus prop) at each board spot open the fh_ui jobs
-- screen through the fh:quests:ui_open server event (server/ui.lua). Board spots come from shared/board_spots.lua
-- (also read by fh_ui's map blips, so the coordinates are defined once). Spots are guesses: TODO-verify-in-game.
local B = FhQuestsBoardSpots
local function openBoard(region_id) TriggerServerEvent('fh:quests:ui_open', region_id) end

RegisterCommand('jobs', function() openBoard(B.regionFor(GetEntityCoords(PlayerPedId()))) end, false)

-- Board spots (rsg-target is optional: without it only /jobs works). Zones and props are removed on stop.
local zones, props, stopping = {}, {}, false

CreateThread(function()
    if GetResourceState('rsg-target') ~= 'started' then return end
    for _, b in ipairs(B.spots) do
        zones[#zones + 1] = exports['rsg-target']:addSphereZone({
            coords = vector3(b.coords.x, b.coords.y, b.coords.z), radius = 1.5, debug = false,
            options = { { label = b.label, icon = 'fa-solid fa-clipboard-list', distance = 2.0,
                onSelect = function() openBoard(b.region_id) end } },
        })
        local hash = joaat(b.model)
        if IsModelValid(hash) then -- unverified model: skip the prop when RedM does not know it
            RequestModel(hash)
            local t = GetGameTimer() + 3000
            while not HasModelLoaded(hash) and GetGameTimer() < t and not stopping do Wait(50) end
            if HasModelLoaded(hash) and not stopping then
                local prop = CreateObject(hash, b.coords.x, b.coords.y, b.coords.z, false, false, false)
                props[#props + 1] = prop
                PlaceObjectOnGroundProperly(prop)
                FreezeEntityPosition(prop, true)
            end
            SetModelAsNoLongerNeeded(hash)
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    stopping = true
    for _, prop in ipairs(props) do
        if DoesEntityExist(prop) then DeleteEntity(prop) end
    end
    if GetResourceState('rsg-target') == 'started' then
        for _, id in ipairs(zones) do pcall(function() exports['rsg-target']:removeZone(id) end) end
    end
end)
