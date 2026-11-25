-- fh_tailor config (progression-03). Region ids come from fh_core/shared/regions.lua; never define new ones here.
-- T1 ships only a placeholder starter entry per sex and one placeholder shop. Real stock (outfits per tier, per town
-- size, single items) is T3 content; tailor stops per town are T2.
FhTailorConfig = {
    -- Everything that applies visuals or needs the @spikes S1 verdict (outfit presets coexisting with the rsg-character
    -- face/body, which single items layer cleanly) stays off until S1 PASS. Off: ownership, buying, grants and the
    -- saved look still work and persist; nothing is put on the ped.
    FittedOutfits = false,

    maxItems = 3,           -- single items worn over an outfit (per look / saved outfit)
    maxSavedOutfits = 5,    -- wardrobe slots 1..N
    chargeRetries = 3,      -- extra charge attempts after fh_charge_busy (nothing was taken on busy)
    chargeRetryMs = 250,    -- wait between those attempts
    lockWaitMs = 10000,     -- grant / load / equip wait this long for the character's lock; buy never waits

    -- Shops: { id, label, region_id, size, coords, radius }. size = town size (1 small / general store, 2 town,
    -- 3 city): an entry with `size = n` is stocked where shop.size >= n. Town size is not in FhRegions, so it lives here.
    -- coords/radius: the server refuses a buy from further away (out_of_range).
    shops = {
        -- Placeholder (T1): Valentine town centre from FhRegions, wide radius. T2 sets the real tailor stops.
        valentine_general = {
            id = 'valentine_general', label = 'Valentine General Store', region_id = 'heartlands', size = 1,
            coords = { x = -169.47, y = 629.38, z = 113.03 }, radius = 75.0,
        },
    },

    -- Catalog: id -> { id, label, sex = 'male'|'female'|'any', kind = 'outfit'|'item',
    --   preset (outfit: SetPedOutfitPreset index) | component (item: component hash or name),
    --   price (whole cents ok, not needed when earned_only), min_tier (1-3, regional tier of the shop's region),
    --   shops = { shopId, ... } (only these shops) or size = n (shops with size >= n; default 1),
    --   earned_only = true (never for sale: grant export / starter only) }
    -- Placeholder presets (0): S1 records the good indices per sex; T3 fills the real catalog.
    catalog = {
        starter_male = { id = 'starter_male', label = 'Work Clothes', sex = 'male', kind = 'outfit', preset = 0,
            min_tier = 1, earned_only = true },
        starter_female = { id = 'starter_female', label = 'Work Clothes', sex = 'female', kind = 'outfit', preset = 0,
            min_tier = 1, earned_only = true },
    },

    -- Granted once on a character's first load (the first id must be an outfit: it becomes the worn look).
    starter = {
        male = { 'starter_male' },
        female = { 'starter_female' },
    },
}
