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
