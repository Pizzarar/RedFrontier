-- fh_ui passive HUD feed (U2): buffs (fh:buffs:sync), own drop bags (fh:death:bags) and survival needs
-- (fh:survival:state). Subscribes directly to the lanes' client events (additional listeners; the lanes are
-- untouched), pushes rows to NUI. Never takes focus.
-- Natives: GetGameTimer, PlayerPedId, GetEntityCoords, SendNUIMessage. Not runtime-tested (no Cfx key).
local hud = FhUiHud
local buffRows, bagRows = {}, {}
local haveBags = false
local survivalPayload = nil

local function now() return GetGameTimer() / 1000.0 end

local function playerXY()
    local ok, c = pcall(function() return GetEntityCoords(PlayerPedId()) end)
    if ok and c then return { x = c.x + 0.0, y = c.y + 0.0 } end
    return nil
end

local function push(screen, rows)
    -- open is idempotent in app.js; an empty list makes the widget hide itself.
    SendNUIMessage({ type = 'open', screen = screen, data = { rows = hud.view(rows, now()) } })
end

local function pushBuffs() push('buffs', buffRows) end
local function pushBags() push('bags', bagRows) end
-- Survival has no countdown, so it is pushed as built (level + missing rows), not through hud.view.
local function pushSurvival()
    SendNUIMessage({ type = 'open', screen = 'survival', data = hud.survivalRows(survivalPayload) })
end
-- Deadlines are fixed only when server data arrives; the tick refreshes direction/distance, never the deadline.
local function setBags(list)
    bagRows = hud.bagRows(type(list) == 'table' and list or {}, now(), playerXY())
    pushBags()
end

FH.onNet('fh:buffs:sync', function(snapshot)
    buffRows = hud.buffRows(snapshot, now())
    pushBuffs()
end)

FH.onNet('fh:death:bags', function(list)
    haveBags = true
    setBags(list)
end)

FH.onNet('fh:survival:state', function(state)
    survivalPayload = state
    pushSurvival()
end)

-- A character switch must not show the previous character's needs until the next state arrives (same pattern as
-- client/adapter.lua clearing its quest snapshot on unload).
RegisterNetEvent('RSGCore:Client:OnPlayerUnload', function()
    survivalPayload = nil
    pushSurvival() -- empty -> the widget hides itself (level 0, no rows)
end)

-- Initial fetch: the owner may already have a bag when fh_ui starts (same callback fh_death uses).
FH.thread(function()
    if not (lib and lib.callback) then return end
    local list = lib.callback.await('fh:death:bags', false)
    if type(list) == 'table' and not haveBags then
        setBags(list)
    end
end)

-- Re-sync the NUI countdowns and bag directions every 5 s (numbers tick in JS between pushes).
FH.thread(function()
    while true do
        Wait(5000)
        hud.retarget(bagRows, playerXY())
        pushBuffs()
        pushBags()
    end
end)

FH.on('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    buffRows, bagRows = {}, {}
    survivalPayload = nil
end)
