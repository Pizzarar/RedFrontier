-- fh_death config (spec L4 soft death). Times in minutes / seconds / ms as named.
FhDeathConfig = {
    despawnMinutes = 30,          -- a bag nobody empties is deleted (contents logged as lost) after this
    reach = 3.5,                  -- metres; fh_core.open re-checks with FhConfig.Access.InteractDistance
    label = 'Dropped belongings',
    -- Bag shape floor; grown to fit the contents (mirror of fh_core FhConfig.Containers.drop_bag).
    bagDefaults = { slots = 30, maxWeight = 1000000 },
    -- Prop is visual only (the stash is the truth). Model name is UNVERIFIED in game: if it does not load, the
    -- B4c request fails and the bag is still openable at its coords.
    propModel = 'p_bag_leather01x',
    deathCheckTries = 6,          -- server re-reads ped health this many times (sync can lag the client report)
    deathCheckIntervalMs = 500,
    minDeadSeconds = 5,           -- a character counts as alive again only after this long dead + health > 0
    aliveCheckMs = 2000,          -- poll of dead characters' server-side health (new life detection)
    sweepMs = 10000,              -- emptied / expired bag sweep
    -- Saddlebag stash id for a dying player (B6e): fh_core registers the character's saddlebag at the player's position
    -- so it can be read and emptied; nil when the character or ped is unknown.
    saddlebagOf = function(src, citizenid) return exports.fh_core:saddlebagOf(src) end,
}
