-- fh_buffs: server-side buff state only (spec 4.5). Stacking rules live in shared/buff_logic.lua.
local cfg = FhBuffsConfig
local logic = FhBuffLogic

local states = {} -- [src] = { [buff_id] = { magnitude, expires_at } }

local function now() return GetGameTimer() / 1000.0 end

---@return boolean ok, table|string result
local function apply(src, buff_id, magnitude, duration)
    if type(src) ~= 'number' or not GetPlayerName(tostring(src)) then return false, 'no_player' end
    states[src] = states[src] or {}
    local ok, res = logic.apply(states[src], cfg.caps, buff_id, magnitude, duration, now())
    if not ok then return false, res end
    TriggerEvent('fh:buffs:applied', { src = src, buff_id = buff_id, magnitude = res.magnitude,
        expires_at = res.expires_at, refreshed = res.refreshed })
    TriggerClientEvent('fh:buffs:sync', src, logic.snapshot(states[src], now()))
    return true, res
end

---@return table<string, { magnitude:number, expires_at:number }>
local function get(src)
    if not states[src] then return {} end
    return logic.snapshot(states[src], now())
end

exports('apply', apply)
exports('get', get)

CreateThread(function()
    while true do
        Wait(cfg.tickMs)
        local t = now()
        for src, st in pairs(states) do
            if #logic.expire(st, t) > 0 then
                TriggerClientEvent('fh:buffs:sync', src, logic.snapshot(st, t))
            end
        end
    end
end)

AddEventHandler('playerDropped', function() states[source] = nil end)

-- Server-console test helper (source 0 only): `fh_buff <serverId> <buff_id> <magnitude> <seconds>`
RegisterCommand('fh_buff', function(source, args)
    if source ~= 0 then return end
    print(json.encode({ apply(tonumber(args[1]), args[2], tonumber(args[3]), tonumber(args[4])) }))
    print(json.encode(get(tonumber(args[1]))))
end, true)
