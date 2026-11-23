-- Craft flow (C1 stub; C2 fills it).
-- C2: FhCraftStations.isNear -> FhCraftRules.canCraft -> FhCraftInv.take all inputs -> FhCraftInv.give outputs,
-- rollback on any failure. The `/fh_craft <recipe>` command is registered here.
FhCraft = {}

---@param src number
---@param recipeId string
---@return boolean ok
---@return string|nil reason
function FhCraft.craft(src, recipeId)
    return false, 'not_implemented'
end

-- TODO(C2): RegisterCommand('fh_craft', ...)
