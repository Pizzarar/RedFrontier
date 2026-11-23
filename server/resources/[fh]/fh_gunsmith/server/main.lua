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
    local ok, res = flow.run(deps(), src, args[1])
    if not ok then tell(src, MESSAGES[res] or ('Restore failed: ' .. tostring(res))); return end
    tell(src, ('Restored to %d%% condition using %d gun parts.'):format(res.to, res.parts))
    TriggerClientEvent('fh_gunsmith:conditionChanged', src, args[1] and tonumber(args[1]), res.to)
end, false)
