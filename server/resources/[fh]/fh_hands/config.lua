-- Hired hands config. Region ids come from fh_core/shared/regions.lua; never define new ones here.
FhHandsConfig = {
    regionId = 'heartlands',      -- region the wage ledger row is booked under
    unlockId = 'hire_hand',       -- fh_progression unlock required to hire (any hand)
    -- G3: hiring while already employing N hands also needs extraHandUnlocks[N + 1] (plus unlockId). A hire whose
    -- extraHandUnlocks[N + 1] slot is empty (past the last configured slot) is refused (max_hands); with only
    -- [2] = 'hire_hand_2' set, two hands is the cap. hire_hand_2 is added by fh_progression (heartlands t3);
    -- until it exists canUnlock answers unknown_unlock and the second hire fails closed ('locked').
    extraHandUnlocks = { [2] = 'hire_hand_2' },
    tickSeconds = 600,            -- one wage tick per this many seconds
    pollSeconds = 30,             -- how often the server checks online owners for due ticks
    maxCatchupTicks = 6,          -- offline/lag catch-up never processes more ticks than this
    quitAfterUnpaid = 3,          -- consecutive unpaid ticks before the hand quits
    -- hand kind -> { label, wage (per tick, whole dollars), task (registered task kind) }
    hands = {
        ranch_hand = { label = 'Ranch hand', wage = 5, task = 'feed_topup' },
        woodcutter = { label = 'Woodcutter', wage = 6, task = 'lumber_topup' },
    },
    feed = {
        item = 'feed',            -- registered through fh_core registerItems (we own it)
        cap = 40,                 -- hand tops the chest up to this many feed
        perTick = 10,             -- at most this much added per working tick
    },
    lumber = {
        item = 'lumber',          -- registered by fh_homestead (buildItems); fh_hands never registers it
        cap = 40,                 -- woodcutter tops the chest up to this many lumber
        perTick = 5,              -- at most this much added per working tick
    },
}
