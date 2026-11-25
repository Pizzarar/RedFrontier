-- fh_homestead client: CLIENT-LOCAL, NON-NETWORKED chest prop + open prompt, plus (H2) a prop for every built slot.
-- Visual only; the server owns all state and re-checks ownership and distance on every open request.
-- Slot props come from the server (model + position already chosen by FhHomesteadConfig.verifiedProps, see
-- shared/build_rules.lua slotProps): asked once on join, then pushed on claim / build / unclaim.
-- Natives: see fh_core/docs/natives.md (unverified in-game).
-- TODO(waits on B4c): a networked/server-authoritative prop would go through the spawn-request contract.
local props = {}                 -- plot id -> entity
local chestPrompts = {}          -- plot id -> lib point (2.0 m [E] prompt) at the snapped z
local INPUT_CONTEXT = 0xCEFD9220 -- E (unverified)

local function ensureChestPrompt(p, z)
    if chestPrompts[p.id] then return end
    chestPrompts[p.id] = lib.points.new({
        coords = vector3(p.coords.x, p.coords.y, z), distance = 2.0,
        onEnter = FH.wrap(function() lib.showTextUI('[E] Homestead chest') end),
        onExit = FH.wrap(function() lib.hideTextUI() end),
        nearby = FH.wrap(function()
            if IsControlJustReleased(0, INPUT_CONTEXT) then TriggerServerEvent('fh:homestead:open_chest', { plot_id = p.id }) end
        end),
    })
end

local function spawn(p)
    if props[p.id] then return end
    local model = joaat(p.model or 'p_chest01x')
    if not IsModelInCdimage(model) then return end
    RequestModel(model)
    local t = GetGameTimer()
    while not HasModelLoaded(model) and GetGameTimer() - t < 5000 do Wait(50) end
    if not HasModelLoaded(model) then return end
    local plot = FhHomesteadConfig and FhHomesteadConfig.plots and FhHomesteadConfig.plots[p.id]
    local z = FhGroundSnap.snapZ(p.coords.z,
        FhSnap.groundZAt(p.id, p.coords.x, p.coords.y, p.coords.z, FhGroundSnap.probeAboveFor(plot)),
        FhGroundSnap.SNAP_TOLERANCE)
    if props[p.id] then -- re-check after the probe yielded: another spawn may have completed meanwhile
        SetModelAsNoLongerNeeded(model)
        return
    end
    local obj = CreateObject(model, p.coords.x, p.coords.y, z, false, false, false) -- isNetwork = false
    if not obj or obj == 0 then
        SetModelAsNoLongerNeeded(model)
        return
    end
    SetEntityHeading(obj, p.heading or 0.0)
    PlaceObjectOnGroundProperly(obj)
    FreezeEntityPosition(obj, true)
    SetModelAsNoLongerNeeded(model)
    props[p.id] = obj
    ensureChestPrompt(p, z)
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
    end
end)

-- ---------------------------------------------------------------- H2: built slot props

local slotSets = {} -- plot id -> { points = {lib points}, ents = { [slot_id] = entity } } (current set per plot)
local pushed = {}   -- plot id -> true once a server push arrived (newer than the join snapshot)

local function ensureSlotPrompt(set, p, z)
    if set.promptPoints[p.slot_id] then return end
    set.promptPoints[p.slot_id] = lib.points.new({
        coords = vector3(p.coords.x, p.coords.y, z), distance = 2.0,
        onEnter = FH.wrap(function() set.prompt = true; lib.showTextUI('[E] Homestead chest ' .. p.chest) end),
        onExit = FH.wrap(function() set.prompt = nil; lib.hideTextUI() end),
        nearby = FH.wrap(function()
            if IsControlJustReleased(0, INPUT_CONTEXT) then
                TriggerServerEvent('fh:homestead:open_chest', { plot_id = p.plot_id, chest = p.chest })
            end
        end),
    })
end

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
    local plot = FhHomesteadConfig and FhHomesteadConfig.plots and FhHomesteadConfig.plots[p.plot_id]
    local z = FhGroundSnap.snapZ(p.coords.z,
        FhSnap.groundZAt(p.plot_id .. ':' .. p.slot_id, p.coords.x, p.coords.y, p.coords.z, FhGroundSnap.probeAboveFor(plot)),
        FhGroundSnap.SNAP_TOLERANCE)
    -- re-check after the probe yielded: the set may have been cleared/replaced meanwhile
    if slotSets[p.plot_id] ~= set or set.ents[p.slot_id] then
        SetModelAsNoLongerNeeded(model)
        return
    end
    local obj = CreateObject(model, p.coords.x, p.coords.y, z, false, false, false) -- isNetwork = false
    SetModelAsNoLongerNeeded(model)
    if not obj or obj == 0 then return end
    SetEntityHeading(obj, p.heading or 0.0)
    PlaceObjectOnGroundProperly(obj)
    FreezeEntityPosition(obj, true)
    set.ents[p.slot_id] = obj
    if p.chest then ensureSlotPrompt(set, p, z) end
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
    for _, pt in pairs(set.promptPoints or {}) do pt:remove() end
    for slotId in pairs(set.ents) do despawnSlot(set, slotId) end
    if set.prompt then lib.hideTextUI() end
end

local function drawPlot(plotId, list)
    clearPlot(plotId)
    if type(list) ~= 'table' or #list == 0 then return end
    local set = { points = {}, ents = {}, promptPoints = {} }
    slotSets[plotId] = set
    for _, p in ipairs(list) do
        p.plot_id = plotId
        local c = vector3(p.coords.x, p.coords.y, p.coords.z)
        set.points[#set.points + 1] = lib.points.new({
            coords = c, distance = 60.0,
            onEnter = FH.wrap(function() spawnSlot(set, p) end),
            onExit = FH.wrap(function() despawnSlot(set, p.slot_id) end),
        })
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

-- ---------------------------------------------------------------- H16: /fh_plotcheck probe (admin report)
-- The server (server/plotcheck.lua) sends the plots to check; this client reuses world-01 D's FhSnap.groundZAt (read-only,
-- one probe per plot, no second probe) plus a water-height read, and reports back with the same token. No natives are
-- called for a plot that is not in the list, and a native that is missing is reported as "unknown", never an error.
local function waterAt(x, y, z)
    if type(GetWaterHeight) ~= 'function' then return false, nil end -- native name unverified in RedM
    local ok, found, h = pcall(GetWaterHeight, x + 0.0, y + 0.0, z + 0.0)
    if not ok then return false, nil end
    if found and type(h) == 'number' then return true, h end
    return true, nil
end

local plotcheckToken -- newest probe run wins: a re-run after a server timeout stops the older loop instead of stacking a second one
local function runPlotcheckProbe(token, list)
    if type(list) ~= 'table' then return end
    plotcheckToken = token
    local results = {}
    for _, p in ipairs(list) do
        if plotcheckToken ~= token then return end -- superseded (the server already dropped this token)
        if type(p) == 'table' and type(p.id) == 'string' and type(p.x) == 'number' and type(p.y) == 'number' and type(p.z) == 'number' then
            local gz, found = FhSnap.groundZAt('plotcheck:' .. p.id, p.x, p.y, p.z, FhGroundSnap.probeAboveFor(p))
            local known, wz = waterAt(p.x, p.y, found and gz or p.z)
            results[#results + 1] = { id = p.id, groundZ = gz, found = found == true, waterKnown = known, waterZ = wz }
        end
    end
    if plotcheckToken ~= token then return end
    plotcheckToken = nil
    TriggerServerEvent('fh:homestead:plotcheck:result', token, results)
end

FH.onNet('fh:homestead:plotcheck:probe', runPlotcheckProbe)
