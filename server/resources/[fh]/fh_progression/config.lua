-- Progression config. Region ids come from fh_core/shared/regions.lua; never define new ones here.
FhProgressionConfig = {
    -- Minimum rep for each tier, per region. Tier 1 is the floor (always held). Must ascend.
    tiers = {
        heartlands = { t2 = 100, t3 = 400 },
    },
    -- unlock_id -> { region_id, min_tier } (min_tier is a number: 1, 2 or 3)
    unlocks = {
        contracts_t2         = { region_id = 'heartlands', min_tier = 2 },
        wagon_t2             = { region_id = 'heartlands', min_tier = 2 },
        fence_rare_stock     = { region_id = 'heartlands', min_tier = 2 },
        fence_treasure_leads = { region_id = 'heartlands', min_tier = 3 },
        hire_hand            = { region_id = 'heartlands', min_tier = 2 },
    },
}
