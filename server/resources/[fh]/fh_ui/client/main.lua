-- fh_ui client: opens/updates/closes NUI screens and owns NUI focus. Natives: SendNUIMessage, SetNuiFocus,
-- RegisterNUICallback. Not runtime-tested (no Cfx key).
local relay = FhUiRelay
local open = {}          -- screen -> true (open screens)
local focused = false

local function wantFocus()
    for screen in pairs(open) do
        if not relay.passive[screen] then return true end
    end
    return false
end

local function syncFocus()
    local want = wantFocus()
    if want ~= focused then
        focused = want
        SetNuiFocus(want, want)
    end
end

local function send(kind, screen, data)
    SendNUIMessage({ type = kind, screen = screen, data = data })
end

local function openScreen(p)
    if type(p) ~= 'table' or type(p.screen) ~= 'string' then return end
    if not relay.screens[p.screen] then
        print(('[fh_ui] open ignored, unknown screen: %s'):format(tostring(p.screen)))
        return
    end
    open[p.screen] = true
    send('open', p.screen, p.data)
    syncFocus()
    if FhUiClient and FhUiClient.onOpen then FhUiClient.onOpen(p.screen, p.data) end
end

local function closeScreen(p)
    if type(p) ~= 'table' or type(p.screen) ~= 'string' then return end
    open[p.screen] = nil
    send('close', p.screen)
    syncFocus()
end

-- Small surface for client/adapter.lua (loaded after this file).
FhUiClient = {
    isOpen = function(screen) return open[screen] == true end,
    update = function(screen, data) send('update', screen, data) end,
}

FH.onNet('fh:ui:open', openScreen)
FH.onNet('fh:ui:close', closeScreen)
FH.onNet('fh:ui:update', function(p)
    if type(p) ~= 'table' or type(p.screen) ~= 'string' then return end
    send('update', p.screen, p.data)
end)

-- Character switch/unload: clear the heat widget so the previous character's heat never lingers at select. The next
-- fh_heat RSGCore:Server:PlayerLoaded re-opens it with the fresh character's data.
FH.onNet('RSGCore:Client:OnPlayerUnload', function() closeScreen({ screen = 'heat' }) end)

-- NUI -> server. The server validates; nothing is trusted from here.
RegisterNUICallback('action', FH.wrap(function(body, cb)
    cb('ok')
    if type(body) ~= 'table' then return end
    TriggerServerEvent('fh:ui:action', { screen = body.screen, action = body.action, payload = body.payload })
end))

-- Esc (app.js) or a screen's own close button: release focus; a named screen also tells its owning lane.
RegisterNUICallback('close', FH.wrap(function(body, cb)
    cb('ok')
    local screen = type(body) == 'table' and body.screen or nil
    if type(screen) == 'string' then
        closeScreen({ screen = screen })
        TriggerServerEvent('fh:ui:action', { screen = screen, action = 'close', payload = {} })
    else
        local list = {}
        for s in pairs(open) do
            if not relay.passive[s] then list[#list + 1] = s end
        end
        for _, s in ipairs(list) do
            closeScreen({ screen = s })
            TriggerServerEvent('fh:ui:action', { screen = s, action = 'close', payload = {} })
        end
        syncFocus()
    end
end))

-- Always give focus back, even if a screen never closed cleanly.
FH.on('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    open = {}
    focused = false
    SetNuiFocus(false, false)
end)
