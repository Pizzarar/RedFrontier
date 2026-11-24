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
    refundReason = 'heat_bounty_refund', -- fh_economy.pay credit when the heat reset fails after the charge
}

-- ---------------------------------------------------------------- R6: roadblocks (always on), night ambush + chase (gated)
-- ALL coordinates are APPROXIMATE (Heartlands / Valentine area, from fh_core regions.lua) and UNVERIFIED in game:
-- stand on the road, read coords/heading, adjust. Models / weapons are also unverified names.
FhHeatConfig.roadblock = {
    enabled = true,
    minLevel = 'wanted',       -- a roadblock spawns when the level RISES onto/past this (fh:heat:threshold)
    cooldownSeconds = 600,     -- per player + faction, measured from the last spawn
    maxConcurrent = 4,         -- live roadblocks across the whole server
    despawnMinutes = 10,       -- or sooner when that player's heat for the faction drops below minLevel
    maxPlayerDistance = 2500.0,-- no chokepoint within this of the player = no roadblock
    pedSpacing = 2.5,          -- metres between peds across the road
    tickSeconds = 15,          -- expiry / heat-drop / player-gone sweep
    -- heading = direction the road runs (degrees); region ties to fh_core regions.lua ids. unverified = true: never checked in game.
    chokepoints = {
        { id = 'hl_valentine_road',  region = 'heartlands', coords = { x = -190.0, y = 800.0, z = 118.0 }, heading = 90.0,  unverified = true },
        { id = 'hl_north_bridge',    region = 'heartlands', coords = { x = -250.0, y = 880.0, z = 120.0 }, heading = 0.0,   unverified = true },
        { id = 'hl_south_crossing',  region = 'heartlands', coords = { x = -340.0, y = 700.0, z = 115.0 }, heading = 45.0,  unverified = true },
        { id = 'rh_north_road',      region = 'scarlett_meadows', coords = { x = 1270.0, y = -1200.0, z = 77.0 }, heading = 0.0,   unverified = true },
        { id = 'rh_south_road',      region = 'scarlett_meadows', coords = { x = 1300.0, y = -1450.0, z = 76.0 }, heading = 0.0,   unverified = true },
        { id = 'rh_east_road',       region = 'scarlett_meadows', coords = { x = 1450.0, y = -1300.0, z = 76.0 }, heading = 90.0,  unverified = true },
    },
    factions = {
        outlaws    = { model = 'g_m_m_unibanditos_01', count = 4, weapon = 'WEAPON_REPEATER_CARBINE' },
        lawmen     = { model = 's_m_m_valdeputy_01',   count = 4, weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
        raiders    = { model = 'g_m_m_unibanditos_01', count = 4, weapon = 'WEAPON_REPEATER_CARBINE' },
        rhodes_law = { model = 's_m_m_valdeputy_01',   count = 4, weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
    },
}

-- Night ambush. ONLY runs when convar fh_spike_gated=false (gated = no-op + log). Peds ring the player.
FhHeatConfig.ambush = {
    enabled = true, minLevel = 'hunted', nightFrom = 21, nightTo = 5, -- game hours, wraps midnight
    cooldownSeconds = 900, radius = 60.0, despawnMinutes = 5,
    factions = {
        outlaws    = { model = 'g_m_m_unibanditos_01', count = 5, weapon = 'WEAPON_REPEATER_CARBINE' },
        lawmen     = { model = 's_m_m_valdeputy_01',   count = 5, weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
        raiders    = { model = 'g_m_m_unibanditos_01', count = 5, weapon = 'WEAPON_REPEATER_CARBINE' },
        rhodes_law = { model = 's_m_m_valdeputy_01',   count = 5, weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
    },
}

-- Mounted chase of a player on a wagon/horse. ONLY when fh_spike_gated=false (S2 spk_chase). Riders + horses spawn behind.
FhHeatConfig.chase = {
    enabled = true, minLevel = 'hunted', cooldownSeconds = 900, despawnMinutes = 5, behind = 80.0,
    horseModel = 'a_c_horse_morgan_bay',
    factions = {
        outlaws    = { model = 'g_m_m_unibanditos_01', count = 3, weapon = 'WEAPON_REPEATER_CARBINE' },
        lawmen     = { model = 's_m_m_valdeputy_01',   count = 3, weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
        raiders    = { model = 'g_m_m_unibanditos_01', count = 3, weapon = 'WEAPON_REPEATER_CARBINE' },
        rhodes_law = { model = 's_m_m_valdeputy_01',   count = 3, weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
    },
}
