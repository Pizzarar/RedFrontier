-- Hired hands config. Region ids come from fh_core/shared/regions.lua; never define new ones here.
FhHandsConfig = {
    regionId = 'heartlands',      -- region the wage ledger row is booked under
    unlockId = 'hire_hand',       -- fh_progression unlock required to hire
    tickSeconds = 600,            -- one wage tick per this many seconds
    pollSeconds = 30,             -- how often the server checks online owners for due ticks
    maxCatchupTicks = 6,          -- offline/lag catch-up never processes more ticks than this
    quitAfterUnpaid = 3,          -- consecutive unpaid ticks before the hand quits
    -- hand kind -> { label, wage (per tick, whole dollars), task (registered task kind) }
    hands = {
        ranch_hand = { label = 'Ranch hand', wage = 5, task = 'feed_topup' },
    },
    feed = {
        item = 'feed',            -- registered through fh_core registerItems (we own it)
        cap = 40,                 -- hand tops the chest up to this many feed
        perTick = 10,             -- at most this much added per working tick
    },
}
