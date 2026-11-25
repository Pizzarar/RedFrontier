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
    actionDebounceMs = 750, -- per-player cooldown on equip / save outfit / wear saved (code 'too_fast'); 0 = off
    lockWaitMs = 10000,     -- grant / load / equip wait this long for the character's lock; buy never waits
    promptDistance = 3.0,            -- [E] tailor stop prompt distance (m)
    homesteadWardrobeDistance = 3.0, -- [G] wardrobe prompt distance at homestead chests (m)
    homesteadWardrobeRadius = 35.0,  -- server-side range check from the player's claimed homestead plot center (m)
    applyDelayMs = 750,              -- settle wait after rsg-character:client:ApplySkin before re-applying outfit

    -- Shops: { id, label, region_id, size, coords, radius }. size = town size (1 small / general store, 2 town,
    -- 3 city): an entry with `size = n` is stocked where shop.size >= n. Town size is not in FhRegions, so it lives here.
    -- coords/radius: approximate town positions from FhRegions (unverified in-game); the server refuses a buy from
    -- further away (out_of_range). Client points are gated on FhRegions.isEnabled(shop.region_id).
    shops = {
        valentine_general = {
            id = 'valentine_general', label = 'Valentine General Store', region_id = 'heartlands', size = 2,
            coords = { x = -169.47, y = 629.38, z = 113.03 }, radius = 75.0,
        },
        emerald_ranch_general = {
            id = 'emerald_ranch_general', label = 'Emerald Ranch General Store', region_id = 'heartlands', size = 1,
            coords = { x = 1411.0, y = 355.0, z = 96.0 }, radius = 75.0,
        },
        rhodes_general = {
            id = 'rhodes_general', label = 'Rhodes General Store', region_id = 'scarlett_meadows', size = 2,
            coords = { x = 1263.6, y = -1305.7, z = 77.9 }, radius = 75.0,
        },
        lagras_general = {
            id = 'lagras_general', label = 'Lagras General Store', region_id = 'bayou_nwa', size = 1,
            coords = { x = 2174.0, y = -1120.0, z = 25.0 }, radius = 75.0,
        },
        saint_denis_tailor = {
            id = 'saint_denis_tailor', label = 'Saint Denis Tailor', region_id = 'bayou_nwa', size = 3,
            coords = { x = 2694.69, y = -1448.48, z = 45.27 }, radius = 75.0,
        },
        blackwater_tailor = {
            id = 'blackwater_tailor', label = 'Blackwater Tailor', region_id = 'great_plains', size = 2,
            coords = { x = -858.67, y = -1337.61, z = 44.49 }, radius = 75.0,
        },
        strawberry_general = {
            id = 'strawberry_general', label = 'Strawberry General Store', region_id = 'big_valley', size = 2,
            coords = { x = -1814.0, y = -440.0, z = 120.0 }, radius = 75.0,
        },
        annesburg_general = {
            id = 'annesburg_general', label = 'Annesburg General Store', region_id = 'roanoke_ridge', size = 1,
            coords = { x = 2921.0, y = 1290.0, z = 96.0 }, radius = 75.0,
        },
        armadillo_general = {
            id = 'armadillo_general', label = 'Armadillo General Store', region_id = 'cholla_springs', size = 1,
            coords = { x = -3711.0, y = -2581.0, z = 70.0 }, radius = 75.0,
        },
        tumbleweed_general = {
            id = 'tumbleweed_general', label = 'Tumbleweed General Store', region_id = 'gaptooth_ridge', size = 1,
            coords = { x = -5522.0, y = -2938.0, z = 90.0 }, radius = 75.0,
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
