-- fh_heat config (spec L7). All numbers are tuning guesses.
FhHeatConfig = {
    min = 0, max = 100,
    -- Heat per source. Data-driven: add a key here and call exports.fh_heat:addSource(src, faction, key[, mult]).
    sources = {
        camp_clear = 25,    -- clearing a faction's camp (fh_zones fh:zones:camp_cleared)
        illicit_sale = 10,  -- selling illicit cargo (fh_trade calls addSource / add later); mult scales by sale size
    },
    -- Lay low: heat falls only while the player is NOT inside that faction's territory.
    decayPerMinute = 2.0,
    decayTickSeconds = 60,
    -- Levels, ascending. R6 (roadblocks / ambush / chase) reads these via exports.fh_heat:level and the
    -- fh:heat:threshold event. A level is the highest entry whose min <= heat; below the first is nil.
    thresholds = {
        { name = 'watched', min = 25 },
        { name = 'wanted',  min = 50 },
        { name = 'hunted',  min = 75 },
    },
    -- Bounty payoff: money per heat point, rounded up per payoff. Charged through fh_economy.charge.
    bountyPerPoint = 4,
    payoffReason = 'heat_bounty',
}
