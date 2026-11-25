-- rescue offers (quests-02 C4): a captive NPC spawns at an fh_zones outlaw camp on accept. The job completes when
-- the holder reaches the captive AFTER that camp is cleared with the holder among its participants; it fails if the
-- captive dies or is despawned before being freed. Pure Lua, no natives.
-- Data: data/regions/<region_id>.lua
--   rescues = { { key, name, camp, model, coords = {x,y,z}, heading, money, rep }, ... }
--   camp = an fh_zones camp id (fh_zones/config.lua). coords/model are TODO-verify-in-game guesses.
--
-- The clear rule (decided, C4): only a `fh:zones:camp_cleared` for THIS camp that lists the holder in `participants`
-- and arrives while the job's watch entry is armed (so after accept) unlocks the captive. A clear before accept, a
-- clear of another camp, or a clear the holder was not present for does nothing; reaching the captive before the
-- clear does nothing either (no credit, nothing remembered). The unlock is in memory only: after a relog or a
-- resource restart the re-armed job needs a fresh clear (the camp respawns after its respawnMinutes).
--
-- I/O lives in server/watch.lua (rescue section: requestSpawn, the camp_cleared listener, posOf, the lost check).
-- Freeing rides the shared reach-watcher as a 1-point kind; the lost rule reuses escort's (JT.escortObserve).
local JT = FhQuestsJobTypes -- the global (in-game: set by shared/jobtypes.lua; specs: set by its spec loader)
local WR = FhQuestsWatchRules or require('watch_rules')

-- Quest-owned LOCAL server events (never net events): { citizenid, offer_key, region_id }.
JT.CAPTIVE_FREED = 'fh:quests:captive_freed'
JT.CAPTIVE_LOST = 'fh:quests:captive_lost'
JT.CAMP_CLEARED = 'fh:zones:camp_cleared' -- fh_zones (local server event): { camp_id, region_id, loot, participants }
JT.RESCUE_TAG_PREFIX = 'fh_quests:rescue:'
JT.RESCUE_RADIUS = 10.0 -- metres: the holder has to walk up to the captive, not just ride past the camp

local function xyz(p)
    if type(p) ~= 'table' or type(p.x) ~= 'number' or type(p.y) ~= 'number' then return nil end
    return { x = p.x, y = p.y, z = type(p.z) == 'number' and p.z or 0.0 }
end

JT.registerBuilder('rescue', function(region_id, d)
    local out = {}
    for _, s in ipairs(d.rescues or {}) do
        local at = xyz(s.coords)
        if at and type(s.model) == 'string' and s.model ~= '' and type(s.camp) == 'string' and s.camp ~= '' then
            out[#out + 1] = {
                key = 'rescue_' .. s.key, title = 'Rescue: ' .. s.name,
                text = ('%s is held at an outlaw camp. Clear the camp, then cut them loose.'):format(s.name),
                on = JT.CAPTIVE_FREED, count = 1, rewards = JT.rewards(region_id, s.money, s.rep),
                region_id = region_id,
                -- the rest rides along to accept only (spawn setup + watcher target); rebuilt from the template on re-arm
                name = s.name, camp = s.camp, model = s.model, coords = at, heading = s.heading,
            }
        end
    end
    return out
end)

---Tag of a captive's spawn request: one per holder + region + offer key.
function JT.rescueTag(region_id, key, cid) return JT.RESCUE_TAG_PREFIX .. region_id .. ':' .. key .. ':' .. tostring(cid) end

local function payload(e) return { citizenid = e.cid, offer_key = e.offer_key, region_id = e.region_id } end
JT.rescuePayload = payload

-- Watch kind: the one target is the captive's spawn point; whose position counts is decided by JT.rescuePos.
WR.registerKind('rescue', {
    points = function(offer)
        local c = xyz(offer and offer.coords)
        return c and { c } or {}
    end,
    ordered = true,
    radius = JT.RESCUE_RADIUS,
    event = JT.CAPTIVE_FREED,
    payload = function(e) return payload(e) end,
})

---Arm-time setup of a rescue entry (server onArm calls it before spawning): the linked camp, locked.
function JT.rescueArm(e, offer)
    e.camp_id = type(offer) == 'table' and offer.camp or nil
    e.cleared = false
    return type(e.camp_id) == 'string'
end

local function listed(list, cid)
    if type(list) ~= 'table' then return false end
    for _, v in ipairs(list) do
        if v == cid then return true end
    end
    return false
end

---A camp_cleared payload against the armed watch: unlocks every rescue entry linked to that camp whose holder is
---a listed participant (not lost, not already freed). Returns the sorted keys it unlocked.
function JT.rescueOnCampCleared(watch, p)
    local out = {}
    if type(p) ~= 'table' or type(p.camp_id) ~= 'string' then return out end
    for k, e in pairs(watch) do
        if e.job_type == 'rescue' and e.camp_id == p.camp_id and not e.cleared and not e.lost
            and not WR.finished(e) and listed(p.participants, e.cid) then
            e.cleared = true
            out[#out + 1] = k
        end
    end
    table.sort(out)
    return out
end

---Position that counts for a rescue entry (the core tick tests it against the captive's spawn point).
---holder = the holder's ped coords, captive = the captive's live coords (the server passes nil when the entity does
---not exist or is dead). Locked (camp not cleared since arm), lost, spawn failed or no live captive: nil, so a
---captive that failed to spawn or despawned can never be freed (the lost check fails it instead). Otherwise the
---spawn point when the holder is within RESCUE_RADIUS of the live captive, else nil.
function JT.rescuePos(e, holder, captive)
    if not e.cleared or e.lost or e.spawnFailed or type(e.points) ~= 'table' or not e.points[1] then return nil end
    if holder == nil or captive == nil then return nil end
    local at = e.points[1]
    if WR.within(holder, captive, JT.RESCUE_RADIUS) then return at end
    return nil
end

---Rescue entries whose captive is lost this check (escort's rule, JT.escortObserve, per entry). Same contract as
---JT.escortCollectLost: sorted snapshot { key, entry }; lost entries repeat until heal drops them.
function JT.rescueCollectLost(watch, observe) return JT.escortCollectLost(watch, observe, 'rescue') end

---Verdict: freed -> complete; captive lost -> fail. Only for this holder + offer + region.
JT.registerVerdict('rescue', function(eventName, p, state, snap)
    if eventName ~= JT.CAPTIVE_FREED and eventName ~= JT.CAPTIVE_LOST then return nil end
    if p.citizenid ~= state.citizenid or p.offer_key ~= snap.key or p.region_id ~= snap.region_id then return nil end
    return eventName == JT.CAPTIVE_FREED and 'complete' or 'fail'
end)
