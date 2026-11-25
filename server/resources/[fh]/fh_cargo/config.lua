-- fh_cargo config. Tier numbers (slots, weight, speed) live in shared/cargo_rules.lua so the specs can see them.
FhCargoConfig = {
    -- Wagon models per tier. Names are guesses from RDR2 vehicle lists: UNVERIFIED in game, fix on first test.
    Models = { t1 = 'cart01', t2 = 'wagon02x', t3 = 'supplywagon' },
    -- Loading / unloading needs the player this close to their own wagon (m). Matches fh_core wagon reach (5.0).
    Reach = 5.0,
    -- A wagon holding cargo within this distance of the player blocks fast travel (m).
    FastTravelReach = 30.0,
    SpawnAheadMetres = 4.0, -- /fh_wagon spawns this far in front of the admin
    -- R16 (roads-04): buy price per tier, whole dollars, charged once via fh_economy:charge ('wagon_buy'). t1 < t2 < t3.
    -- Sized against freight pay (fh_trade config freight): a T1 run pays ~$50-1000 (qty x quote x 1.25), T2 ~3x,
    -- T3 ~6x, so each wagon pays itself back in a few contracts of its own tier. Must stay under fh_economy maxCharge.
    Prices = { t1 = 150, t2 = 600, t3 = 1800 },
    -- fh_economy:charge returns fh_charge_busy while another charge for the character is in flight: retry this many
    -- times (after BuyRetryMs) before refusing.
    BuyChargeRetries = 1,
    BuyRetryMs = 250,
}
