-- fh_gunsmith server (spec L5, plan C3; C5a restores from the OPEN world container). /fh_restore <slot> at a gunsmith station.
local flow = FhGunsmithFlow

local MESSAGES = {
    fh_nothing_open = 'Open a chest, wagon or saddlebag first.',
    fh_size_class = 'That container cannot hold a rifle.',
    fh_out_of_reach = 'You are too far from that container.',
    fh_no_coords = 'That container has no location.',
    no_station = 'You need to be at a gunsmith station.',
    not_implemented = 'Gunsmith stations are not available yet.',
    bad_slot = 'Usage: /fh_restore <slot>',
    no_weapon = 'Nothing in that slot.',
    no_condition = 'That item has no condition to restore.',
    at_cap = 'That weapon is already at its best condition.',
    no_parts = 'You need gun parts.',
    no_remove = 'Removing items is not available yet.',
    no_set_info = 'Writing item condition is not available yet.',
}

---The pane the player has open (fh_inventory FhOpenRef), read the same way fh_core/server/saddlebag.lua does.
---@return table|nil ref, table|nil view, string|nil reason
local function openContainer(src)
    local ref = exports.fh_core:openRef(src)
    if not ref then return nil, nil, 'fh_nothing_open' end
    local view = exports.fh_core:view(ref)
    if not view then return nil, nil, 'fh_nothing_open' end
    return ref, view
end

---The open container must sit within reach of a gunsmith station (fh_crafting station adapter, stationAt).
---@return boolean ok, string|nil reason
local function nearGunsmithStation(coords)
    local s = exports.fh_crafting:stationAt(coords)
    if not s then return false, 'no_station' end
    if s.station_type ~= 'gunsmith' then return false, 'no_station' end
    return true
end

---@core setItemInfo contract (idea-689, not built yet). Assumed signature:
---  exports.fh_core:setItemInfo(ref, slot, info) -> boolean ok, string|nil reason
---Stubbed behind the contract: refuse 'no_set_info' only when fh_core is down or the export is missing; any other
---failure is logged at error level and reported as 'write_failed' (so no parts are taken on either path).
---@return boolean ok, string|nil reason
local function setItemInfo(ref, slot, info)
    if GetResourceState('fh_core') ~= 'started' then return false, 'no_set_info' end
    local called, ok, reason = pcall(function() return exports.fh_core:setItemInfo(ref, slot, info) end)
    if not called then
        if not tostring(ok):find('No such export', 1, true) then
            print(('^1[fh_gunsmith] fh_core.setItemInfo failed: %s^7'):format(tostring(ok)))
            return false, 'write_failed'
        end
        return false, 'no_set_info' -- export missing (contract not built yet)
    end
    if ok == true then return true end
    return false, reason or 'write_failed'
end

local function deps()
    return {
        open = openContainer,
        containers = FhContainers, -- @fh_core/shared/containers.lua
        playerCoords = function(src)
            local ped = GetPlayerPed(src)
            if not ped or ped == 0 then return nil end
            return GetEntityCoords(ped)
        end,
        nearStation = nearGunsmithStation,
        count = function(src, i) return exports.fh_crafting:invCount(src, i) end,
        setInfo = setItemInfo,
        take = function(src, i, n) return exports.fh_crafting:invTake(src, i, n) end,
    }
end

local function tell(src, msg)
    TriggerClientEvent('chat:addMessage', src, { args = { 'Gunsmith', msg } })
end

RegisterCommand('fh_restore', function(src, args)
    if src == 0 then print('[fh_gunsmith] fh_restore is a player command'); return end
    local ok, res, meta = flow.run(deps(), src, args[1])
    if meta and meta.rollbackFailed then
        print(('^1[fh_gunsmith] ERROR rollback failed src=%s slot=%s wanted_condition=%s reason=%s (condition raised, parts not taken)^7')
            :format(tostring(src), tostring(meta.slot), tostring(meta.wanted), tostring(meta.reason)))
    end
    if not ok then tell(src, MESSAGES[res] or ('Restore failed: ' .. tostring(res))); return end
    tell(src, ('Restored to %d%% condition using %d gun parts.'):format(res.to, res.parts))
    -- fh_spike_gated is server-only (`set`), so pass it down.
    local gated = GetConvar('fh_spike_gated', 'true') ~= 'false'
    TriggerClientEvent('fh_gunsmith:conditionChanged', src, tonumber(args[1]), res.to, gated)
end, false)
