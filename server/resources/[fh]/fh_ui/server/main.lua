-- fh_ui server: relays validated NUI actions to the owning lane. No game authority here (see shared/relay.lua).
local relay = FhUiRelay
local limiter = relay.newLimiter()

local function log(fmt, ...) print(('[fh_ui] ' .. fmt):format(...)) end

local function now() return GetGameTimer() / 1000.0 end

RegisterNetEvent('fh:ui:action', function(msg)
    local src = source
    if not src or src <= 0 then return end
    local ok, name, ev = relay.relay(limiter, src, msg, now())
    if not ok then
        log('dropped action from %s: %s', tostring(src), tostring(name))
        return
    end
    TriggerEvent(name, ev)
end)

AddEventHandler('playerDropped', function()
    relay.forget(limiter, source)
end)

-- Map blips: claimed homestead plot ids, read from fh_homestead (read-only, presentation only). `/where plot` uses
-- this to pick the nearest UNCLAIMED plot. Returns {} while fh_homestead is down or not ready.
lib.callback.register('fh:ui:plot_claims', function()
    if GetResourceState('fh_homestead') ~= 'started' or not exports.fh_homestead.claimedPlots then return {} end
    local ok, list = pcall(function() return exports.fh_homestead:claimedPlots() end)
    if not ok or type(list) ~= 'table' then return {} end
    return list
end)

-- Map blips & /where: enabled-region trappers, read from fh_hunting (read-only, presentation only). Returns nil while
-- fh_hunting is down or not ready so the client falls back to FhHuntingConfig.Trapper (heartlands).
lib.callback.register('fh:ui:trappers', function()
    if GetResourceState('fh_hunting') ~= 'started' or not exports.fh_hunting.getTrappers then return nil end
    local ok, list = pcall(function() return exports.fh_hunting:getTrappers() end)
    if not ok or type(list) ~= 'table' then return nil end
    return list
end)

-- world-04 M: /where shows place ids to admins / fh_dev. The decision is fh_core's (exports.fh_core:canSeeIds, server-side).
lib.callback.register('fh:ui:show_ids', function(src)
    local ok, show = pcall(function() return exports.fh_core:canSeeIds(src) end)
    return ok and show == true
end)

-- Dev demo (U3): `fh_ui_demo <screen|close [screen]>` opens a fixture screen for the caller. Gated by the command ACE (same pattern as fh_homestead's fh_unclaim); console has no client.
local fx = FhUiFixtures
local function reply(src, msg)
    if src == 0 then log('%s', msg) else TriggerClientEvent('chat:addMessage', src, { args = { 'fh_ui', msg } }) end
end

RegisterCommand('fh_ui_demo', function(src, args)
    if src == 0 then return reply(0, 'fh_ui_demo: run in-game') end
    if not IsPlayerAceAllowed(src, 'command.fh_ui_demo') then return reply(src, 'fh_ui_demo: not allowed') end
    local p, err = fx.parseDemo(args)
    if not p then return reply(src, 'fh_ui_demo: ' .. err .. ' (screens: heat insurance jobs journal dialogue station fence tradepost fieldguide trapper tailor wardrobe)') end
    if p.action == 'close' then
        local list = {}
        if p.screen then list[1] = p.screen else for s in pairs(fx.fixtures) do list[#list + 1] = s end end
        for _, s in ipairs(list) do TriggerClientEvent('fh:ui:close', src, { screen = s }) end
    else
        TriggerClientEvent('fh:ui:open', src, { screen = p.screen, data = fx.fixtures[p.screen] })
    end
end, true)
