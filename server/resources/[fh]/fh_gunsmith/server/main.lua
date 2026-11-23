-- fh_gunsmith server (spec L5, plan C3). /fh_restore <slot> at a gunsmith station.
local flow = FhGunsmithFlow

local MESSAGES = {
    no_station = 'You need to be at a gunsmith station.',
    not_implemented = 'Gunsmith stations are not available yet.',
    bad_slot = 'Usage: /fh_restore <slot>',
    no_weapon = 'Nothing in that slot.',
    no_condition = 'That item has no condition to restore.',
    at_cap = 'That weapon is already at its best condition.',
    no_parts = 'You need gun parts.',
    no_remove = 'Removing items is not available yet.',
}

local function deps()
    return {
        near = function(src, t) return exports.fh_crafting:isNearStation(src, t) end,
        slot = function(src, s) return exports.fh_crafting:invSlot(src, s) end,
        count = function(src, i) return exports.fh_crafting:invCount(src, i) end,
        setInfo = function(src, s, info) return exports.fh_crafting:invSetInfo(src, s, info) end,
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
