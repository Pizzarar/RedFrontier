-- fh_alife config (A-Life camp ownership sim, plan a-life-01). Pure data: no natives. Global FhAlifeConfig.
-- Pacing: when the owner clears an outlaw camp, Valentine Law holds it and an outlaw squad marches back to retake
-- it ~retake.minTicks..maxTicks ticks later (1 tick = tickSeconds). Squad strength is a weighted-dice roll per squad.
FhAlifeConfig = {
    tickSeconds = 60, -- seconds between server ticks (the camp-ownership sim clock)

    retake = {
        minTicks = 20, -- ~20 min at 60 s/tick
        maxTicks = 30, -- ~30 min at 60 s/tick
        strengthMin = 3, -- squad strength roll range (weighted dice)
        strengthMax = 6,
    },

    -- a-life-02 B1 road raids. Ambush nodes come ONLY from @world `regions[id].ambush` (fh_core shared/regions.lua) in
    -- enabled regions; a region without that data gets no raids. Each tick, each outlaw-held camp in a region with
    -- nodes rolls chancePct (out of 100) to send a squad to a free node: it travels travelMin..travelMax ticks, holds
    -- the node holdTicks, then walks home. One live squad per node; at most regionCap per region.
    -- Each outlaw killed on the road adds 1 to regionPressure (max pressureMax), subtracted from that faction's next
    -- retake roll in the region.
    raids = {
        chancePct = 5,
        regionCap = 2,
        travelMin = 2,
        travelMax = 4,
        holdTicks = 15, -- ~15 min at 60 s/tick
        strengthMin = 2,
        strengthMax = 4,
        pressureMax = 6,
    },

    -- a-life-02 B2 squad materialisation (server/squads.lua). A held ambush squad spawns on foot only when a player is
    -- within ambushRadius (metres, 3D) of its node; the same radius decides who is credited (participants) when the
    -- squad is wiped. pedModel = the ped model of every squad member. Both TODO-verify-in-game.
    squads = {
        ambushRadius = 45.0,
        pedModel = 'g_m_m_unibanditos_01',
    },

    -- Law patrols (data only, never spawn peds): a law-held camp gets one reinforce squad of `strength` that arrives
    -- after travelTicks and holds while law keeps the camp (re-checked every holdTicks). A retake lands only when its
    -- strength less regionPressure beats the holders. strength 2 < retake.strengthMin 3: an unpressured retake still
    -- lands, as in a-life-01; road kills are what make it fail.
    reinforce = {
        strength = 2,
        travelTicks = 3,
        holdTicks = 10,
    },

    -- a-life-03 claim raids (shared/raid_rules.lua; Implemented A-Life — Thanks to S.T.A.L.K.E.R. A-Life by GSC Game
    -- World). Only a raidable wilderness claim (never a town lot) whose owner is online can be raided. Each tick, each
    -- eligible claim rolls baseChance x (outlaw-held camps in its region) x (1 - fenceMitigation if a fence is built).
    -- The owner is warned; the squad arrives warnTicks later. Owner at the claim (within raidRadius metres) -> a fight
    -- on foot for up to fightTicks; owner away -> the raiders take up to stealStacks stacks from chest 1, at most
    -- stealMaxFraction of each stack (always >= 1 item), into the raiding camp's stash. Then they ride home
    -- (returnTicks). One raid per claim per cooldownTicks; at most liveCap live raids in the world.
    claimRaids = {
        baseChance = 0.01,      -- per tick, per outlaw-held camp in the region (1% at 60 s/tick)
        fenceMitigation = 0.5,  -- a built fence halves the odds
        cooldownTicks = 180,    -- ~3 h at 60 s/tick, from the warning
        liveCap = 2,            -- world-wide live (not returning) raids
        warnTicks = 5,          -- ~5 min warning before arrival
        fightTicks = 10,        -- an unbeaten raid squad withdraws after ~10 min
        returnTicks = 3,        -- ride home (data only, never visible)
        strengthMin = 3,
        strengthMax = 5,
        stealStacks = 2,
        stealMaxFraction = 0.5,
        raidRadius = 60.0,      -- metres: owner "home" at arrival (server/C2 reads it). TODO-verify-in-game.
        bootGraceTicks = 3,     -- server: raid steps skipped after start while fh_homestead shows 0 claims (cache load)
    },

    -- Camp-ownership shortage effects. `item` is the region's initialShortages good (fh_trade config).
    -- `raised` restores the shortage when outlaws retake a camp; `relieved` clears it when law holds the camp.
    shortages = {
        heartlands       = { item = 'trade_salt',    raised = 0.5, relieved = 0 },
        scarlett_meadows = { item = 'trade_whiskey', raised = 0.6, relieved = 0 },
    },
}
