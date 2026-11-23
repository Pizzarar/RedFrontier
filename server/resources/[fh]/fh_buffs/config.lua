FhBuffsConfig = {
    tickMs = 1000, -- expiry sweep interval
    -- Magnitude cap per known buff id. apply() refuses ids not listed here.
    -- Magnitude is a multiplier/strength unit defined by the consuming lane.
    caps = {
        well_fed     = 1.25,
        rested       = 1.20,
        warm         = 1.0,
        trophy_luck  = 1.15,
        homestead_comfort = 1.10,
        tonic_vigor  = 1.15,
        tonic_steady = 1.10,
        hydrated     = 1.0,
        clean        = 1.0,
    },
}
