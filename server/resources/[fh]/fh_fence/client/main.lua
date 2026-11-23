-- fh_fence client: E near the current stop opens the fh_ui `fence` screen (idea-601).
-- Server decides everything; this only fetches the screen data and opens it.
-- Natives: IsControlJustReleased (fh_core/docs/natives.md, unverified in-game). Not runtime-tested.
local INPUT_CONTEXT = 0xCEFD9220 -- E (unverified)
local point = nil
local stopId = nil

local why = FhFenceLogic.why -- shared/fence_logic.lua (messages cover every B7 charge/pay code)

local function notify(msg) lib.notify({ description = msg, type = 'inform' }) end

-- E: fetch the screen data (server-priced) and open the fh_ui `fence` screen. Trades and their results run
-- server-side (fh:fence:ui_buy / ui_sell -> fh:ui:update with a notice); Esc closes via fh_ui.
local function openMenu()
    local data, err = lib.callback.await('fh:fence:screen', false)
    if not data then return notify(why(err)) end
    TriggerEvent('fh:ui:open', { screen = 'fence', data = data })
end

local function setStop(w)
    if point then point:remove(); point = nil; lib.hideTextUI() end
    stopId = w and w.id
    if not w then return end
    point = lib.points.new({
        coords = vec3(w.coords.x, w.coords.y, w.coords.z), distance = w.range,
        onEnter = FH.wrap(function() lib.showTextUI('[E] ' .. w.label) end),
        onExit = FH.wrap(function() lib.hideTextUI() end),
        nearby = FH.wrap(function()
            if IsControlJustReleased(0, INPUT_CONTEXT) then openMenu() end
        end),
    })
end

FH.thread(function()
    while true do
        local w = lib.callback.await('fh:fence:where', false)
        if (w and w.id) ~= stopId then setStop(w) end
        Wait(15000)
    end
end)

FH.on('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    lib.hideTextUI()
end)
