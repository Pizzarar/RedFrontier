-- fh_gunsmith restore flow (plan crafting-01 C3). Pure and injectable: no natives, no exports.
-- Restore math lives in fh_crafting/shared/craft_rules.lua (FhCraftRules.restore); this only orchestrates.
local M = {}

---Pure plan for one weapon item (slot table, info.condition / info.stars) and the gun_parts the player holds.
---@return table|nil plan { from, to, parts, cap, stars }
---@return string|nil reason 'no_weapon' | 'no_condition' | 'at_cap' | 'no_parts'
function M.plan(item, partsAvailable, rules)
    rules = rules or FhCraftRules
    if type(item) ~= 'table' then return nil, 'no_weapon' end
    local info = type(item.info) == 'table' and item.info or {}
    local to, used, reason = rules.restore(info.condition, info.stars, partsAvailable)
    if reason then return nil, reason end
    return { from = tonumber(info.condition), to = to, parts = used, cap = rules.restoreCap(info.stars), stars = info.stars }
end

---deps (all injectable):
---  near(src, 'gunsmith') -> ok, reason       station adapter (fh_crafting isNearStation)
---  slot(src, slot) -> item|nil               fh_crafting invSlot
---  count(src, item) -> n                     fh_crafting invCount
---  setInfo(src, slot, info) -> ok, reason    condition write
---  take(src, item, amount) -> ok, reason     part removal (B7-backed; 'not_implemented'/'no_remove' => refuse)
---  rules                                     optional, defaults to FhCraftRules
---Order: station -> slot -> plan -> write condition -> consume parts. If the consume fails the
---condition write is rolled back, so parts are never consumed without a successful write and vice versa.
---@return boolean ok
---@return string|table reason_or_result
---@return table|nil meta { rollbackFailed, slot, wanted, reason } when the rollback write also failed
function M.run(deps, src, slot)
    local okNear, why = deps.near(src, 'gunsmith')
    if not okNear then return false, why or 'no_station' end
    slot = tonumber(slot)
    if not slot or slot ~= slot or slot == math.huge or slot == -math.huge or slot ~= math.floor(slot) or slot < 1 then return false, 'bad_slot' end
    local item = deps.slot(src, slot)
    local plan, reason = M.plan(item, deps.count(src, 'gun_parts'), deps.rules)
    if not plan then return false, reason end

    local newInfo = {}
    for k, v in pairs(item.info) do newInfo[k] = v end
    newInfo.condition = plan.to
    local okSet, setWhy = deps.setInfo(src, slot, newInfo)
    if not okSet then return false, setWhy or 'write_failed' end

    local okTake, takeWhy = deps.take(src, 'gun_parts', plan.parts)
    if not okTake then
        local okRb, rbWhy = deps.setInfo(src, slot, item.info) -- rollback
        local meta = (not okRb) and { rollbackFailed = true, slot = slot, wanted = item.info.condition, reason = rbWhy } or nil
        if takeWhy == 'not_implemented' or takeWhy == 'no_remove' then return false, 'no_remove', meta end
        return false, takeWhy or 'take_failed', meta
    end
    return true, plan
end

if GetCurrentResourceName then FhGunsmithFlow = M else return M end
