-- fh_homestead client: CLIENT-LOCAL, NON-NETWORKED chest prop + open prompt. Visual only; the server owns all state and
-- re-checks ownership and distance on every open request. Natives: see fh_core/docs/natives.md (unverified in-game).
-- TODO(waits on B4c): a networked/server-authoritative prop would go through the spawn-request contract.
local props = {}                 -- plot id -> entity
local INPUT_CONTEXT = 0xCEFD9220 -- E (unverified)

local function spawn(p)
    if props[p.id] then return end
    local model = joaat(p.model or 'p_chest01x')
    if not IsModelInCdimage(model) then return end
    RequestModel(model)
    local t = GetGameTimer()
    while not HasModelLoaded(model) and GetGameTimer() - t < 5000 do Wait(50) end
    if not HasModelLoaded(model) then return end
    local obj = CreateObject(model, p.coords.x, p.coords.y, p.coords.z, false, false, false) -- isNetwork = false
    if not obj or obj == 0 then
        SetModelAsNoLongerNeeded(model)
        return
    end
    SetEntityHeading(obj, p.heading or 0.0)
    PlaceObjectOnGroundProperly(obj)
    FreezeEntityPosition(obj, true)
    SetModelAsNoLongerNeeded(model)
    props[p.id] = obj
end

local function despawn(id)
    if props[id] then
        if DoesEntityExist(props[id]) then DeleteObject(props[id]) end
        props[id] = nil
    end
end

FH.thread(function()
    local list = lib.callback.await('fh:homestead:plots', false) or {}
    for _, p in ipairs(list) do
        lib.points.new({
            coords = p.coords, distance = 40.0,
            onEnter = FH.wrap(function() spawn(p) end),
            onExit = FH.wrap(function() despawn(p.id) end),
        })
        lib.points.new({
            coords = p.coords, distance = 2.0,
            onEnter = FH.wrap(function() lib.showTextUI('[E] Homestead chest') end),
            onExit = FH.wrap(function() lib.hideTextUI() end),
            nearby = FH.wrap(function()
                if IsControlJustReleased(0, INPUT_CONTEXT) then TriggerServerEvent('fh:homestead:open_chest', { plot_id = p.id }) end
            end),
        })
    end
end)

FH.on('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for id in pairs(props) do despawn(id) end
    lib.hideTextUI()
end)
