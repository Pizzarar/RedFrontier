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

-- Local (never networked) event for producers that hold client-side state tied to a screen (fh_tailor's mirror preview):
-- fires on EVERY way a screen closes (server close, Esc, close button, replaced by another screen, NUI reload, unload).
local function closeScreen(p)
    if type(p) ~= 'table' or type(p.screen) ~= 'string' then return end
    open[p.screen] = nil
    send('close', p.screen)
    syncFocus()
    TriggerEvent('fh:ui:closed', { screen = p.screen })
end

-- A previewable screen opened while another previewable one is open (or re-opened) replaces it: close the old one the
-- same way Esc would, so its preview is reverted and its lane hears the close.
local function replacePreviewScreens(screen)
    if not relay.previewable[screen] then return end
    local stale = {}
    for s in pairs(open) do
        if relay.previewable[s] then stale[#stale + 1] = s end
    end
    for _, s in ipairs(stale) do
        closeScreen({ screen = s })
        if s ~= screen then TriggerServerEvent('fh:ui:action', { screen = s, action = 'close', payload = {} }) end
    end
end

local function openScreen(p)
    if type(p) ~= 'table' or type(p.screen) ~= 'string' then return end
    if not relay.screens[p.screen] then
        print(('[fh_ui] open ignored, unknown screen: %s'):format(tostring(p.screen)))
        return
    end
    replacePreviewScreens(p.screen)
    open[p.screen] = true
    send('open', p.screen, p.data)
    syncFocus()
    if FhUiClient and FhUiClient.onOpen then FhUiClient.onOpen(p.screen, p.data) end
end

-- Small surface for client/adapter.lua (loaded after this file).
FhUiClient = {
    isOpen = function(screen) return open[screen] == true end,
    update = function(screen, data) send('update', screen, data) end,
}

exports('isOpen', function(screen) return open[screen] == true end)

FH.onNet('fh:ui:open', openScreen)
FH.onNet('fh:ui:close', closeScreen)
FH.onNet('fh:ui:update', function(p)
    if type(p) ~= 'table' or type(p.screen) ~= 'string' then return end
    send('update', p.screen, p.data)
end)

-- Character switch/unload: clear the heat widget so the previous character's heat never lingers at select. The next
-- fh_heat RSGCore:Server:PlayerLoaded re-opens it with the fresh character's data.
FH.onNet('RSGCore:Client:OnPlayerUnload', function()
    closeScreen({ screen = 'heat' })
    for screen in pairs(relay.previewable) do
        if open[screen] then closeScreen({ screen = screen }) end
    end
end)

-- NUI -> server. The server validates; nothing is trusted from here.
RegisterNUICallback('action', FH.wrap(function(body, cb)
    cb('ok')
    if type(body) ~= 'table' then return end
    TriggerServerEvent('fh:ui:action', { screen = body.screen, action = body.action, payload = body.payload })
end))

-- Mirror preview request from a previewable screen: shape-checked here, then handed to the owning resource as a LOCAL
-- client event. Nothing goes to the server and fh_ui applies nothing.
RegisterNUICallback('preview', FH.wrap(function(body, cb)
    cb('ok')
    local ok, screen, look = relay.checkPreview(body)
    if ok and open[screen] then TriggerEvent('fh:ui:preview', { screen = screen, look = look }) end
end))

RegisterNUICallback('preview_end', FH.wrap(function(body, cb)
    cb('ok')
    local screen = type(body) == 'table' and body.screen or nil
    if type(screen) == 'string' and relay.previewable[screen] then TriggerEvent('fh:ui:preview_end', { screen = screen }) end
end))

-- The NUI page (re)loaded: it has lost every screen, so close what Lua thinks is open (reverts a stuck preview, frees focus).
RegisterNUICallback('ready', FH.wrap(function(_, cb)
    cb('ok')
    local list = {}
    for s in pairs(open) do list[#list + 1] = s end
    for _, s in ipairs(list) do closeScreen({ screen = s }) end
    syncFocus()
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
