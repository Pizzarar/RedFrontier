-- Craft flow (plan crafting-01 C2) and the `/fh_craft <recipe>` command.
-- FhCraftStations.isNearStation -> FhCraftRules.canCraft -> FhCraftInv.take every input -> FhCraftInv.give every
-- output, all-or-nothing with rollback (pure logic: shared/craft_flow.lua, spec/crafting_flow_spec.lua).
FhCraft = {}

local flow, recipes = FhCraftFlow, FhCraftRecipes
local busy = {}   -- src -> true while a craft runs (no overlapping crafts per player)

local function deps()
    return {
        near = FhCraftStations.isNearStation,
        count = FhCraftInv.count,
        take = FhCraftInv.take,
        give = function(src, item, amount) return FhCraftInv.give(src, item, amount) end,
        canCraft = FhCraftRules.canCraft,
    }
end

local function logRollbackFailure(src, recipeId, reason, info)
    local lost = {}
    for _, f in ipairs(info.rollbackFailed) do
        lost[#lost + 1] = ('%s %sx %s (%s)'):format(f.step.op, f.step.amount, f.step.item, tostring(f.reason))
    end
    print(('^1[fh_crafting] ROLLBACK INCOMPLETE src=%s recipe=%s failed=%s; not undone: %s^7')
        :format(tostring(src), tostring(recipeId), tostring(reason), table.concat(lost, '; ')))
end

---@param src number
---@param recipeId string
---@return boolean ok
---@return string|nil reason no_player | busy | unknown_recipe | bad_type | no_station | missing_inputs | no_remove |
---  no_add | not_enough | error | fh_core reasons
---@return table|nil info see FhCraftFlow.craft
function FhCraft.craft(src, recipeId)
    if type(src) ~= 'number' or not (src > 0) then return false, 'no_player' end -- NaN fails src > 0
    if busy[src] then return false, 'busy' end
    busy[src] = true
    local called, ok, reason, info = pcall(flow.craft, src, recipes.get(recipeId), deps())
    busy[src] = nil
    if not called then
        print(('^1[fh_crafting] craft error src=%s recipe=%s: %s^7'):format(tostring(src), tostring(recipeId), tostring(ok)))
        return false, 'error'
    end
    if not ok and type(info) == 'table' and info.rollbackFailed and #info.rollbackFailed > 0 then
        logRollbackFailure(src, recipeId, reason, info)
    end
    return ok, reason, info
end

AddEventHandler('playerDropped', function() busy[source] = nil end)

local MESSAGES = {
    busy = 'Already crafting.',
    unknown_recipe = 'Unknown recipe.',
    bad_type = 'Unknown station type.',
    no_station = 'You need to be at the right station.',
    no_remove = 'Removing items is not available yet.',
    no_add = 'Adding items is not available yet.',
    not_enough = 'You no longer have the materials.',
}

local function tell(src, msg)
    TriggerClientEvent('chat:addMessage', src, { args = { 'Crafting', msg } })
end

local function recipeIds()
    local ids = {}
    for _, r in ipairs(recipes.list) do ids[#ids + 1] = r.id end
    return table.concat(ids, ', ')
end

RegisterCommand('fh_craft', function(src, args)
    if src == 0 then print('[fh_crafting] fh_craft is a player command'); return end
    local id = args[1]
    if not id or id == '' then tell(src, 'Usage: /fh_craft <recipe>  (' .. recipeIds() .. ')'); return end
    local ok, reason, info = FhCraft.craft(src, id)
    if ok then
        local r = recipes.get(id)
        tell(src, ('Done: %s.'):format(r and r.label or id))
    elseif reason == 'missing_inputs' then
        local parts = {}
        for _, m in ipairs(info and info.missing or {}) do
            parts[#parts + 1] = ('%sx %s (have %s)'):format(m.need, m.item, m.have)
        end
        tell(src, 'Missing: ' .. table.concat(parts, ', '))
    else
        tell(src, MESSAGES[reason] or ('Crafting failed: ' .. tostring(reason)))
    end
end, false)
