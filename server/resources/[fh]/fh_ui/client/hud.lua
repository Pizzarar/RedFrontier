-- fh_ui passive HUD feed (U2): buffs (fh:buffs:sync) and own drop bags (fh:death:bags). Subscribes directly to the
-- lanes' client events (additional listeners; the lanes are untouched), pushes rows to NUI. Never takes focus.
-- Natives: GetGameTimer, PlayerPedId, GetEntityCoords, SendNUIMessage. Not runtime-tested (no Cfx key).
local hud = FhUiHud
local buffRows, bagRows = {}, {}
local haveBags = false

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
end)
