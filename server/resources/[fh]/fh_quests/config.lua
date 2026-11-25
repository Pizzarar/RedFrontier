-- fh_quests configuration (quests-03).
FhQuestsConfig = {
    -- Dev flag: when true, locked offers (min_tier > player tier) stay in the board payload with
    -- `locked = { min_tier = N }` so UI work can preview them. Default false (v1 hides locked offers).
    showLockedOffers = false,

    -- Contract reward multipliers by offer min_tier (quests-03 T2). Unknown or missing tier falls back to 1.0.
    tierRewardMultipliers = {
        [1] = 1.0,
        [2] = 1.5,
        [3] = 2.25,
    },
}
