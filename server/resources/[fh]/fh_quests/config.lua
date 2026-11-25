-- fh_quests configuration (quests-03).
FhQuestsConfig = {
    -- When true, locked offers (min_tier > player tier) stay in the board payload with
    -- `locked = { min_tier = N }`; fh_ui's jobs board shows them greyed ("Needs tier N") with no accept button.
    showLockedOffers = true,

    -- Contract reward multipliers by offer min_tier (quests-03 T2). Unknown or missing tier falls back to 1.0.
    tierRewardMultipliers = {
        [1] = 1.0,
        [2] = 1.5,
        [3] = 2.25,
    },
}
