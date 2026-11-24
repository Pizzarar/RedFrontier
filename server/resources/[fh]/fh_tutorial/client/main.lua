-- fh_tutorial client (guide-02): show the tutorial prompts through ox_lib notify, draw the step's GPS route to its
-- waypoint, and report the client-check signals to the server. No VO, no cutscenes, no fh_ui screens (fh_ui has no
-- notify/objective export; ox_lib notify is the fallback).

local function notify(text)
    lib.notify({ title = 'Tutorial', description = text, type = 'inform' })
end

-- GPS "waypoint": RDR3 has no SET_NEW_WAYPOINT native, so the yellow route is drawn with the MAP multi-route
-- natives. Hashes verified against alloc8or rdr3-nativedb-data natives.json (MAP namespace). The colour name hash is
-- a guess (unverified in game), like every other native use in this repo.
local function clearRoute()
    pcall(function() Citizen.InvokeNative(0x9E0AB9AAEE87CE28) end) -- CLEAR_GPS_MULTI_ROUTE
end

local function setRoute(x, y, z)
    pcall(function()
        Citizen.InvokeNative(0x9E0AB9AAEE87CE28) -- CLEAR_GPS_MULTI_ROUTE
        Citizen.InvokeNative(0x3D3D15AF7BCAAF83, joaat('COLOR_YELLOW'), true, true) -- START_GPS_MULTI_ROUTE
        Citizen.InvokeNative(0x64C59DD6834FA942, x, y, z, false)                    -- ADD_POINT_TO_GPS_MULTI_ROUTE
        Citizen.InvokeNative(0x4426D65E029A4DC0, true)                              -- SET_GPS_MULTI_ROUTE_RENDER
    end)
end

FH.onNet('fh:tutorial:prompt', function(data)
    if type(data) ~= 'table' or type(data.text) ~= 'string' then return end
    local wp = data.waypoint
    if type(wp) == 'table' and type(wp.x) == 'number' and type(wp.y) == 'number' then
        setRoute(wp.x, wp.y, type(wp.z) == 'number' and wp.z or 0.0)
    else
        clearRoute()
    end
    notify(data.text)

    -- Informational step ack: a step with no player action (the greeting) carries ack = { check, after_ms }. Report
    -- its check once the prompt has had time to be read; the server ignores it unless that step is still current.
    local ack = data.ack
    if type(ack) == 'table' and type(ack.check) == 'string' then
        local check, after = ack.check, math.max(0, tonumber(ack.after_ms) or 0)
        CreateThread(function()
            Wait(after)
            TriggerServerEvent('fh:tutorial:check', check)
        end)
    end
end)

-- Client-check signals. The server only advances when the current step matches (talk is a no-op otherwise), so these
-- fire unconditionally and cost nothing. Each is a net event the owning lane already sends to this client.
FH.onNet('rsg-inventory:client:open', function()
    TriggerServerEvent('fh:tutorial:check', 'inventory')
end)
FH.onNet('fh:trade:menu', function()
    TriggerServerEvent('fh:tutorial:check', 'trade')
end)
FH.onNet('fh:ui:open', function(data)
    if type(data) == 'table' and data.screen == 'jobs' then
        TriggerServerEvent('fh:tutorial:check', 'jobs')
    end
end)
