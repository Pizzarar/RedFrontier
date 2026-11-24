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

    -- Camp-ownership shortage effects. `item` is the region's initialShortages good (fh_trade config).
    -- `raised` restores the shortage when outlaws retake a camp; `relieved` clears it when law holds the camp.
    shortages = {
        heartlands       = { item = 'trade_salt',    raised = 0.5, relieved = 0 },
        scarlett_meadows = { item = 'trade_whiskey', raised = 0.6, relieved = 0 },
    },
}
