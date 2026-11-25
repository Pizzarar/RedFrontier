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
--   snapped           : true when client props/prompts ground-snap z from a config hint (horizontal reach + vertical snap window)
M.Containers = {
    -- equipped = the first `slots` player slots (rsg-inventory hotbar). Its own weight sub-cap sits inside the
    -- player's total; backpack gets the rest of the player slots and the rest of the total.
    equipped    = { slots = 5,  maxWeight = 8000 },
    backpack    = { slots = 20 }, -- no own cap: total carry weight minus equipped (set maxWeight to add one)
    saddlebag   = { slots = 20, maxWeight = 60000 },
    wagon       = { slots = 60, maxWeight = 500000, interactDistance = 5.0 },
    chest       = { slots = 50, maxWeight = 1000000, snapped = true },
    drop_bag    = { slots = 30, maxWeight = 1000000 },
    fence_stash = { slots = 20, maxWeight = 200000 },
}

-- Saddlebag (B6e). HorseModels: the server-side allowlist a horse entity's model must match (names or hashes; compared as
-- unsigned 32-bit hashes). Include the fh_spawn_horse default (FhAdminArgs.DEFAULT_MODELS.horse). Names are GUESSES,
-- unverified in-game: extend when a vanilla horse is refused.
M.Saddlebag = {
    HorseModels = {
        'a_c_horse_morgan_bay', 'a_c_horse_morgan_flaxenchestnut', 'a_c_horse_americanpaint_overo',
        'a_c_horse_arabian_white', 'a_c_horse_kentuckysaddle_black', 'a_c_horse_thoroughbred_brindle',
        'a_c_horse_turkoman_gold', 'a_c_horse_mustang_wildbay',
    },
    OpenCooldownMs = 500, -- per source, for fh:saddlebag:open and fh:saddlebag:transfer
}

M.Access = {
    InteractDistance = 3.5,
    -- Vertical reach bounds (metres) for ground-snapped containers (`snapped = true`), relative to the config z-hint.
    -- Derivation: every placement/prompt caller clamps FhSnap.groundZAt through FhGroundSnap.snapZ(..., SNAP_TOLERANCE)
    -- (±10.0 m max shift from the config z-hint). Adding 3.5 m vertical headroom (matching InteractDistance) gives ±13.5 m:
    --   +13.5 m above hint: +10.0 m max snap + up to +3.5 m for ped torso (~1.0 m), mounted rider (~2.0 m), wagon (~2.5 m), or slope.
    --   -13.5 m below hint: -10.0 m max snap + up to -3.5 m for a player standing downslope/below the prop within horizontal reach.
    SnapToleranceAbove = 13.5,
    SnapToleranceBelow = 13.5,
}

-- Items fh_core defines outright (pushed into rsg-core with SetItems at start). Shape: see shared/items.lua.
-- Example:
-- M.Items = {
--     gold_bar = { label = 'Gold Bar', weight = 12000, size_class = 'cargo', stackable = true, value_base = 500, illicit = true },
-- }
M.Items = {
    -- TEST-ONLY (B6d): a cargo item so the owner card can prove cargo is refused by backpack and saddlebag. Remove at M4
    -- when real cargo (bullion, big safes) exists.
    test_cargo_crate = { label = 'Test Cargo Crate', weight = 20000, size_class = 'cargo', stackable = false, value_base = 0 },
}

-- Static fh fields layered over existing rsg-core items (keyed by rsg item name). Only fh keys are read:
-- size_class, value_base, illicit (and stackable to force a value). Anything unlisted gets the defaults.
M.ItemOverrides = {}

-- Spawn-request contract (shared/spawn_rules.lua, server/spawn.lua). Unset keys fall back to FhSpawnRules.DEFAULTS.
-- The conservative/S1-proven switch is the convar fh_spike_gated (server.cfg), not a config key.
M.Spawn = {
    Range = 300.0,            -- metres: nearest ready player within this of the spawn point creates the entity
    FallbackAnyPlayer = true, -- nobody in range: nearest ready player anywhere; false = park until someone comes in range
    TimeoutMs = 10000,        -- a dispatched request with no answer retries with the next candidate after this
    Retries = 3,              -- extra attempts after the first, then onFailed
    AdoptMaxDistance = 25.0,  -- the created entity must be this close to the requested coords
    AdoptWaitMs = 3000,       -- how long the server waits for a reported netId to show up server-side
    TickMs = 1000,            -- timeout / parked / entity-gone check interval
}

if GetCurrentResourceName then
    FhConfig = M
else
    return M
end
