-- fh_cargo config. Tier numbers (slots, weight, speed) live in shared/cargo_rules.lua so the specs can see them.
FhCargoConfig = {
    -- Wagon models per tier. Names are guesses from RDR2 vehicle lists: UNVERIFIED in game, fix on first test.
    Models = { t1 = 'cart01', t2 = 'wagon02x', t3 = 'supplywagon' },
    -- Loading / unloading needs the player this close to their own wagon (m). Matches fh_core wagon reach (5.0).
    Reach = 5.0,
    -- A wagon holding cargo within this distance of the player blocks fast travel (m).
    FastTravelReach = 30.0,
    SpawnAheadMetres = 4.0, -- /fh_wagon spawns this far in front of the admin
}
