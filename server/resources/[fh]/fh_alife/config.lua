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

    -- Camp-ownership shortage effects. `item` is the region's initialShortages good (fh_trade config).
    -- `raised` restores the shortage when outlaws retake a camp; `relieved` clears it when law holds the camp.
    shortages = {
        heartlands       = { item = 'trade_salt',    raised = 0.5, relieved = 0 },
        scarlett_meadows = { item = 'trade_whiskey', raised = 0.6, relieved = 0 },
    },
}
