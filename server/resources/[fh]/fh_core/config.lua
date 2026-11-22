-- fh_core tuning (spec §4.1 / §4.2). Pure data: no natives, so busted can load it.
-- Global name is FhConfig, never Config (fh_inventory's vendored code owns `Config`).
-- Weights are grams, the same unit rsg-inventory uses (Config.PlayerMaxWeight = 35000).
local M = {}

-- Fallbacks only. The player's real total carry weight and slot count stay with rsg-inventory
-- (Config.PlayerMaxWeight / PlayerSlots + capacity bonus); fh_inventory passes them to FhRules.playerViews.
M.Player = {
    Slots = 25,
    MaxWeight = 35000,
}

-- Size class used when an item has no definition or override (spec §4.1 default).
M.DefaultSizeClass = 'pocket'

-- Per-container capacity. Which size classes a container accepts lives in shared/containers.lua (contract, not tuning).
--   slots / maxWeight : defaults for a new container of that type
--   interactDistance  : reach override in metres (falls back to Access.InteractDistance)
M.Containers = {
    -- equipped = the first `slots` player slots (rsg-inventory hotbar). Its own weight sub-cap sits inside the
    -- player's total; backpack gets the rest of the player slots and the rest of the total.
    equipped    = { slots = 5,  maxWeight = 8000 },
    backpack    = { slots = 20, maxWeight = 35000 },
    saddlebag   = { slots = 20, maxWeight = 60000 },
    wagon       = { slots = 60, maxWeight = 500000, interactDistance = 5.0 },
    chest       = { slots = 50, maxWeight = 1000000 },
    drop_bag    = { slots = 30, maxWeight = 1000000 },
    fence_stash = { slots = 20, maxWeight = 200000 },
}

M.Access = {
    InteractDistance = 3.5,
}

-- Items fh_core defines outright (pushed into rsg-core with SetItems at start). Shape: see shared/items.lua.
-- Example:
-- M.Items = {
--     gold_bar = { label = 'Gold Bar', weight = 12000, size_class = 'cargo', stackable = true, value_base = 500, illicit = true },
-- }
M.Items = {}

-- Static fh fields layered over existing rsg-core items (keyed by rsg item name). Only fh keys are read:
-- size_class, value_base, illicit (and stackable to force a value). Anything unlisted gets the defaults.
M.ItemOverrides = {}

if GetCurrentResourceName then
    FhConfig = M
else
    return M
end
