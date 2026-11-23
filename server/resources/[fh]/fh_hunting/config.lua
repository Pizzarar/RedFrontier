-- fh_hunting config (spec L8). Pure data: no natives, so the specs can load it.
FhHuntingConfig = {
    -- Pelt quality source (one flag, plan hunting-01-l8 "Decided"):
    --   'roll'   server maps the last damage bone to a zone and rolls inside that zone's band (default, works without
    --            the S4 spk_pelt result);
    --   'native' read _GET_PED_QUALITY / _GET_PED_DAMAGE_CLEANLINESS instead (needs the S4 verdict to be GO).
    PeltQualitySource = 'roll',

    -- Price multiplier per star (fh_economy.pay amount = base * mult), and the extra legendary multiplier.
    QualityMult = { [1] = 0.4, [2] = 1.0, [3] = 1.8 },
    LegendaryMult = 4,

    SkinRange = 5.0,   -- metres, skinner to carcass (server-read positions)
    WagonRange = 8.0,  -- metres, cargo pelts go straight into a wagon this close

    -- H2 skin flow.
    -- Where a pelt goes, tried in order; each entry is also filtered by the fh_core size-class rules (FhContainers):
    -- the backpack takes pocket items only (spec 4.1), so it is never a bulky or cargo destination.
    GrantOrder = {
        bulky = { 'saddlebag', 'wagon' },
        cargo = { 'wagon' },
    },
    SkinDurationMs = 4000,    -- client progress bar before the request is sent
    SkinCooldownMs = 1000,    -- server: one skin request per player per this many ms (extra ones are ignored)
    SkinPromptDistance = 2.5, -- rsg-target reach to the aimed point; the server re-checks SkinRange to the carcass
    DeleteCarcass = true,     -- delete the carcass after a grant (it is marked skinned either way)
    ClaimPruneMs = 30000,     -- server: forget skinned-claim entries whose carcass no longer exists
    -- Client tracking of live animals (last damage bone, weapon hits).
    TrackRadius = 150.0,
    TrackIntervalMs = 250,
    DeadCacheSeconds = 900,   -- keep a dead animal's shot data this long, by netId
    -- Cause-of-death weapons that count as explosive (1 star). UNVERIFIED names.
    ExplosiveWeapons = { 'weapon_thrown_dynamite', 'weapon_thrown_molotov' },

    -- 'roll' source. A zone sets the star band; the roll only ever lowers it by one star, with this chance.
    -- Limb / gut / explosive / multi-hit stay 1 star.
    Zones = {
        head   = { stars = 3, downgradeChance = 0 },
        vital  = { stars = 3, downgradeChance = 0 },
        body   = { stars = 2, downgradeChance = 0.10 },
        limb   = { stars = 1, downgradeChance = 0 },
        gut    = { stars = 1, downgradeChance = 0 },
    },
    MultiHitMin = 2,   -- this many damaging hits on the animal (or more) counts as multi-hit = 1 star

    -- Bone name (lowercase) -> zone. UNVERIFIED in game: the client (H2) reports the bone and the server falls back to
    -- DefaultZone for a bone not listed here. Numeric bone ids may be added as keys too.
    DefaultZone = 'body',
    BoneZones = {
        skel_head = 'head', skel_neck0 = 'head', skel_neck1 = 'head', skel_jaw = 'head',
        skel_spine3 = 'vital', skel_spine2 = 'vital', skel_l_clavicle = 'vital', skel_r_clavicle = 'vital',
        skel_spine1 = 'body', skel_spine_root = 'body',
        skel_spine0 = 'gut', skel_pelvis = 'gut',
        skel_l_thigh = 'limb', skel_r_thigh = 'limb', skel_l_calf = 'limb', skel_r_calf = 'limb',
        skel_l_foot = 'limb', skel_r_foot = 'limb', skel_l_upperarm = 'limb', skel_r_upperarm = 'limb',
        skel_l_forearm = 'limb', skel_r_forearm = 'limb', skel_l_hand = 'limb', skel_r_hand = 'limb',
        skel_tail = 'limb',
    },

    -- 'native' source. Map the native results to stars. Values are UNVERIFIED until S4 spk_pelt reports.
    --   _GET_PED_QUALITY: 0 poor, 1 good, 2 perfect.
    --   _GET_PED_DAMAGE_CLEANLINESS: 0 perfect, 1 good, 2 poor (anything above = ruined, reads as 1 star).
    -- The pelt gets the lower of the two.
    NativeQualityStars = { [0] = 1, [1] = 2, [2] = 3 },
    NativeCleanlinessStars = { [0] = 3, [1] = 2, [2] = 1 },
}

if not GetCurrentResourceName then return FhHuntingConfig end
