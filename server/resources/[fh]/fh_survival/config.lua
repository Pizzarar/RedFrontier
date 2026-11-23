-- fh_survival config. Sectioned: later blocks (S3 actions, S4 rest, S5 effects) append their own section.
FhSurvivalConfig = {
    -- == Core (S2) ==
    TickSeconds = 15,              -- needs evaluation interval
    LoginGraceSeconds = 600,       -- characters with no saved row are never sluggish this long after load
    -- Buff durations in seconds (shared/needs.lua falls back to its defaults for missing/invalid entries).
    Durations = { well_fed = 3600, hydrated = 2700, rested = 7200, clean = 5400, warm = 1200 },
    -- Region ids (spec 4.4, FhRegions) where `warm` counts as a core need. `heartlands` is temperate, so
    -- empty until a cold region exists. Format: { some_region = true }.
    ColdRegions = {},
    -- Missing-needs count -> sluggish level (0-3). Counts above the last key use the last level.
    LevelMap = { [0] = 0, 1, 2, 3 },
    SluggishEffect = 'notify',     -- 'notify' (text + level only, no natives) | 'native' (S5, unverified in game)

    -- == S3 food / water / wash / warmth ==
    -- == S4 rest / comfort ==
    -- == S5 sluggish effect ==
}
