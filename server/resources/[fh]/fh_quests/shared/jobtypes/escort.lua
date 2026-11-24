-- escort offers (quests-02 C3): an NPC (the escortee) spawns at `start` on accept and follows the holder; the job
-- completes when the escortee reaches `destination` and fails if it dies or is despawned. Pure Lua, no natives.
-- Data: data/regions/<region_id>.lua
--   escorts = { { key, name, model, start = {x,y,z}, heading, destination = {x,y,z}, money, rep }, ... }
-- start/destination/model are TODO-verify-in-game guesses.
-- I/O lives in server/watch.lua (escort section: requestSpawn, posOf = the escortee, the lost check) and
-- client/escort.lua (follow task). Arrival rides the shared reach-watcher as a 1-point kind.
local JT = FhQuestsJobTypes -- the global (in-game: set by shared/jobtypes.lua; specs: set by its spec loader)
local WR = FhQuestsWatchRules or require('watch_rules')

-- Quest-owned LOCAL server events (never net events): { citizenid, offer_key, region_id }.
JT.ESCORT_ARRIVED = 'fh:quests:escort_arrived'
JT.ESCORT_LOST = 'fh:quests:escort_lost'
JT.ESCORT_TAG_PREFIX = 'fh_quests:escort:'
JT.ESCORT_LOST_TICKS = 2 -- checks in a row with the adopted escortee missing before it counts as despawned

local function xyz(p)
    if type(p) ~= 'table' or type(p.x) ~= 'number' or type(p.y) ~= 'number' then return nil end
    return { x = p.x, y = p.y, z = type(p.z) == 'number' and p.z or 0.0 }
end

JT.registerBuilder('escort', function(region_id, d)
    local out = {}
    for _, s in ipairs(d.escorts or {}) do
        local start, dest = xyz(s.start), xyz(s.destination)
        if start and dest and type(s.model) == 'string' and s.model ~= '' then
            out[#out + 1] = {
                key = 'escort_' .. s.key, title = 'Escort: ' .. s.name,
                text = ('Meet %s and see them safely to their destination.'):format(s.name),
                on = JT.ESCORT_ARRIVED, count = 1, rewards = JT.rewards(region_id, s.money, s.rep),
                region_id = region_id,
                -- the rest rides along to accept only (spawn setup + watcher target); rebuilt from the template on re-arm
                name = s.name, model = s.model, start = start, heading = s.heading, destination = dest,
            }
        end
    end
    return out
end)

---Tag of an escortee's spawn request: one per holder + region + offer key (client/escort.lua matches the prefix).
function JT.escortTag(region_id, key, cid) return JT.ESCORT_TAG_PREFIX .. region_id .. ':' .. key .. ':' .. tostring(cid) end

local function payload(e) return { citizenid = e.cid, offer_key = e.offer_key, region_id = e.region_id } end
JT.escortLostPayload = payload

-- Watch kind: the one target is the destination; the escortee's position counts (posOf, set in server/watch.lua).
WR.registerKind('escort', {
    points = function(offer)
        local d = xyz(offer and offer.destination)
        return d and { d } or {}
    end,
    ordered = true,
    event = JT.ESCORT_ARRIVED,
    payload = function(e) return payload(e) end,
})

---Position that counts for an escort entry: the escortee's coords (pos, read by the server), nil once lost.
function JT.escortPos(e, pos)
    if e.lost then return nil end
    return pos
end

---Lost rule for one check of an escort entry. obs = { spawn = getSpawn(reqId) result | nil, exists, dead, failed }
---(read server-side). Returns 'ok' | 'wait' | 'lost'.
---  pending (accept not committed) or finished (arrived) entries: wait, never lost.
---  failed (onFailed fired), request gone / failed / despawned: lost.
---  not adopted yet (pending / dispatching / verifying, also a re-request after its spawner dropped): wait.
---  adopted + dead: lost. adopted + entity missing: lost after ESCORT_LOST_TICKS checks in a row.
function JT.escortObserve(e, obs)
    if e.pending or WR.finished(e) or type(obs) ~= 'table' then return 'wait' end
    local spawn = obs.spawn
    if obs.failed or type(spawn) ~= 'table' or spawn.state == 'failed' or spawn.state == 'despawned' then
        return 'lost'
    end
    if spawn.state ~= 'adopted' then
        e.gone = nil
        return 'wait'
    end
    if obs.exists then
        e.gone = nil
        return obs.dead and 'lost' or 'ok'
    end
    e.gone = (e.gone or 0) + 1
    return e.gone >= JT.ESCORT_LOST_TICKS and 'lost' or 'wait'
end

---Escort entries of `watch` that are lost this check, as a sorted snapshot list { key, entry } (taken before
---anything yields). observe(e) -> obs is asked ONLY for escort entries that are not pending or finished, once each;
---it may throw (that entry is skipped). Lost entries are marked e.lost (no more arrival) and listed again on every
---check until heal drops them (the row left active), so a fail that never landed is said again.
function JT.escortCollectLost(watch, observe)
    local keys, out = {}, {}
    for k, e in pairs(watch) do
        if e.job_type == 'escort' and not e.pending and not WR.finished(e) then keys[#keys + 1] = k end
    end
    table.sort(keys)
    for _, k in ipairs(keys) do
        local e = watch[k]
        if e.lost then
            out[#out + 1] = { key = k, entry = e }
        else
            local ok, obs = pcall(observe, e)
            if ok and JT.escortObserve(e, obs) == 'lost' then
                e.lost = true
                out[#out + 1] = { key = k, entry = e }
            end
        end
    end
    return out
end

---Verdict: the escortee arrived -> complete; lost -> fail. Only for this holder + offer + region.
JT.registerVerdict('escort', function(eventName, p, state, snap)
    if eventName ~= JT.ESCORT_ARRIVED and eventName ~= JT.ESCORT_LOST then return nil end
    if p.citizenid ~= state.citizenid or p.offer_key ~= snap.key or p.region_id ~= snap.region_id then return nil end
    return eventName == JT.ESCORT_ARRIVED and 'complete' or 'fail'
end)
