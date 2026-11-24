-- fh_homestead client: CLIENT-LOCAL, NON-NETWORKED chest prop + open prompt, plus (H2) a prop for every built slot.
-- Visual only; the server owns all state and re-checks ownership and distance on every open request.
-- Slot props come from the server (model + position already chosen by FhHomesteadConfig.verifiedProps, see
-- shared/build_rules.lua slotProps): asked once on join, then pushed on claim / build / unclaim.
-- Natives: see fh_core/docs/natives.md (unverified in-game).
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
    local obj = CreateObject(model, p.coords.x, p.coords.y, FhSnap.groundZAt(p.id, p.coords.x, p.coords.y, p.coords.z), false, false, false) -- isNetwork = false
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

-- ---------------------------------------------------------------- H2: built slot props

local slotSets = {} -- plot id -> { points = {lib points}, ents = { [slot_id] = entity } } (current set per plot)
local pushed = {}   -- plot id -> true once a server push arrived (newer than the join snapshot)

local function spawnSlot(set, p)
    if set.ents[p.slot_id] then return end
    local model = joaat(p.model)
    if not IsModelInCdimage(model) then return end
    RequestModel(model)
    local t = GetGameTimer()
    while not HasModelLoaded(model) and GetGameTimer() - t < 5000 do Wait(50) end
    if not HasModelLoaded(model) then return end
    -- the plot's props may have been replaced/cleared while the model loaded: draw nothing for a stale set
    if slotSets[p.plot_id] ~= set or set.ents[p.slot_id] then
        SetModelAsNoLongerNeeded(model)
        return
    end
    local obj = CreateObject(model, p.coords.x, p.coords.y, FhSnap.groundZAt(p.plot_id .. ':' .. p.slot_id, p.coords.x, p.coords.y, p.coords.z), false, false, false) -- isNetwork = false
    SetModelAsNoLongerNeeded(model)
    if not obj or obj == 0 then return end
    SetEntityHeading(obj, p.heading or 0.0)
    PlaceObjectOnGroundProperly(obj)
    FreezeEntityPosition(obj, true)
    set.ents[p.slot_id] = obj
end

local function despawnSlot(set, slotId)
    local e = set.ents[slotId]
    if e then
        if DoesEntityExist(e) then DeleteObject(e) end
        set.ents[slotId] = nil
    end
end

local function clearPlot(plotId)
    local set = slotSets[plotId]
    if not set then return end
    slotSets[plotId] = nil
    for _, pt in ipairs(set.points) do pt:remove() end
    for slotId in pairs(set.ents) do despawnSlot(set, slotId) end
    if set.prompt then lib.hideTextUI() end
end

local function drawPlot(plotId, list)
    clearPlot(plotId)
    if type(list) ~= 'table' or #list == 0 then return end
    local set = { points = {}, ents = {} }
    slotSets[plotId] = set
    for _, p in ipairs(list) do
        p.plot_id = plotId
        local c = vector3(p.coords.x, p.coords.y, p.coords.z)
        set.points[#set.points + 1] = lib.points.new({
            coords = c, distance = 60.0,
            onEnter = FH.wrap(function() spawnSlot(set, p) end),
            onExit = FH.wrap(function() despawnSlot(set, p.slot_id) end),
        })
        if p.chest then
            set.points[#set.points + 1] = lib.points.new({
                coords = c, distance = 2.0,
                onEnter = FH.wrap(function() set.prompt = true; lib.showTextUI('[E] Homestead chest ' .. p.chest) end),
                onExit = FH.wrap(function() set.prompt = nil; lib.hideTextUI() end),
                nearby = FH.wrap(function()
                    if IsControlJustReleased(0, INPUT_CONTEXT) then
                        TriggerServerEvent('fh:homestead:open_chest', { plot_id = plotId, chest = p.chest })
                    end
                end),
            })
        end
    end
end

FH.onNet('fh:homestead:slot_props', function(plotId, list)
    if type(plotId) ~= 'string' then return end
    pushed[plotId] = true
    drawPlot(plotId, list)
end)

FH.thread(function()
    -- nil = the server has not finished loading slots yet: ask again a little later
    for _ = 1, 30 do
        local all = lib.callback.await('fh:homestead:slot_props', false)
        if type(all) == 'table' then
            for plotId, list in pairs(all) do
                if not pushed[plotId] then drawPlot(plotId, list) end -- a push that arrived first is newer
            end
            return
        end
        Wait(5000)
    end
end)

FH.on('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for id in pairs(props) do despawn(id) end
    for plotId in pairs(slotSets) do clearPlot(plotId) end
    lib.hideTextUI()
end)
