-- fh_quests reach-watcher rules (quests-02 C2). Pure Lua, no natives: server/watch.lua does the I/O (coarse tick,
-- server-side coords, events). Shared by every job type that completes by *being somewhere*: survey now, escort (C3)
-- and rescue (C4) register themselves through M.registerKind and need no edit here.
--
-- A watch entry is one held job: { cid, src, qid, job_type, offer_key, region_id, points, ordered, radius, done,
-- visited }. points = { { x, y, z }, ... } (index = point number, 1-based); done = points credited so far;
-- visited = set of credited point numbers (any-order only).
--
-- Ordered entries are restart-safe: the next point is always done + 1, and done comes back from the persisted
-- progress count. Any-order entries keep `visited` in memory only: after a restart or relog it starts empty while
-- `done` is restored, so the verdict (not this module) is what bounds credit to the job's count.
local M = {}

M.POINT_EVENT = 'fh:quests:point_reached' -- { citizenid, offer_key, region_id, point }
M.DEFAULT_RADIUS = 25.0 -- metres, horizontal; coords are TODO-verify-in-game guesses, so be forgiving
M.TICK_MS = 3000         -- coarse: reach checks need no precision

-- ---------------------------------------------------------------- kind registry (the C3/C4 hook)
-- M.registerKind(job_type, def). def fields (all optional but `points`):
--   points(offer) -> { {x,y,z}, ... }   the targets of an accepted offer (required)
--   ordered    boolean (default true)   visit points in list order, or any order (offer.ordered overrides)
--   radius     number (default DEFAULT_RADIUS)
--   event      string (default POINT_EVENT) local server event emitted per reached point
--   payload(entry, point) -> table      event payload (default { citizenid, offer_key, region_id, point })
--   -- server-only, called by server/watch.lua (pcall'd), never by these rules:
--   posOf(entry) -> {x,y,z}|nil         whose position counts (default: the holder's ped, server coords)
--   onArm(entry, offer) -> ok, err      extra setup on accept / re-arm (e.g. requestSpawn an escortee)
--   onDisarm(entry, why)                cleanup ('done' | 'gone' | 'abandon' | 'rearm' | 'stop')
M.KINDS = {}

function M.registerKind(job_type, def)
    assert(type(job_type) == 'string' and job_type ~= '', 'watch kind needs a job type name')
    assert(type(def) == 'table' and type(def.points) == 'function', 'watch kind needs def.points(offer)')
    M.KINDS[job_type] = def
end

function M.isWatched(job_type) return M.KINDS[job_type] ~= nil end

---Is a player's held job a watched type? quest_id 'job:<type>:<key>' (shared/jobs.lua). Returns job_type, key.
function M.watchedJob(quest_id)
    if type(quest_id) ~= 'string' then return nil end
    local jt, key = quest_id:match('^job:([a-z0-9_]+):(.+)$')
    if jt and M.KINDS[jt] then return jt, key end
    return nil
end

-- ---------------------------------------------------------------- geometry
local function num(v) return type(v) == 'number' and v == v end

---Horizontal (x/y) distance check. Missing or malformed coords never count as reached.
function M.within(pos, point, radius)
    if type(pos) ~= 'table' or type(point) ~= 'table' then return false end
    local px, py, qx, qy = pos.x, pos.y, point.x, point.y
    if not (num(px) and num(py) and num(qx) and num(qy)) then return false end
    local r = num(radius) and radius or M.DEFAULT_RADIUS
    local dx, dy = px - qx, py - qy
    return dx * dx + dy * dy <= r * r
end

-- ---------------------------------------------------------------- visit order
---Build a watch entry for a held job. done = points already credited (persisted progress count).
function M.entry(job_type, fields, offer, done)
    local kind = M.KINDS[job_type]
    if not kind then return nil, 'fh_not_watched' end
    local ok, points = pcall(kind.points, offer)
    if not ok or type(points) ~= 'table' or #points == 0 then return nil, 'fh_no_points' end
    local ordered = kind.ordered ~= false
    if type(offer) == 'table' and type(offer.ordered) == 'boolean' then ordered = offer.ordered end -- per template
    local e = {
        job_type = job_type, cid = fields.cid, src = fields.src, qid = fields.qid,
        offer_key = fields.offer_key, region_id = fields.region_id,
        points = points, ordered = ordered, radius = kind.radius or M.DEFAULT_RADIUS,
        done = math.max(0, math.min(math.tointeger(done) or 0, #points)), visited = {},
        pending = true, -- until the cached row is seen active (M.heal)
    }
    return e
end

---Point numbers the entry may reach next: ordered -> { done + 1 }; any-order -> every unvisited point.
function M.nextTargets(e)
    local out = {}
    if e.done >= #e.points then return out end
    if e.ordered then
        out[1] = e.done + 1
    else
        for i = 1, #e.points do
            if not e.visited[i] then out[#out + 1] = i end
        end
    end
    return out
end

---The point the entry reaches at pos (lowest eligible number in range), or nil. A point out of order never counts.
function M.reached(e, pos)
    for _, i in ipairs(M.nextTargets(e)) do
        if M.within(pos, e.points[i], e.radius) then return i end
    end
    return nil
end

---Record a reached point. Returns true when that was the last one (the entry is finished).
function M.mark(e, i)
    e.visited[i] = true
    e.done = e.done + 1
    return e.done >= #e.points
end

function M.finished(e) return e.done >= #e.points end

---Verdict helper for a point event against a held job: is `point` a valid next point given the persisted
---progress count? ordered: exactly count + 1. any-order: any 1..total while count < total.
function M.acceptsPoint(ordered, total, count, point)
    point, count, total = math.tointeger(point), math.tointeger(count) or 0, math.tointeger(total)
    if not point or not total or count >= total or point < 1 or point > total then return false end
    if ordered ~= false then return point == count + 1 end
    return true
end

---Default event payload for a reached point.
function M.payload(e, point)
    local kind = M.KINDS[e.job_type]
    if kind and kind.payload then return kind.payload(e, point) end
    return { citizenid = e.cid, offer_key = e.offer_key, region_id = e.region_id, point = point }
end

function M.eventOf(job_type)
    local kind = M.KINDS[job_type]
    return kind and kind.event or M.POINT_EVENT
end

-- ---------------------------------------------------------------- one tick
---Check every watched entry once. posOf(entry) is asked ONLY for entries in `watch` (holders of a watched job),
---at most once per entry; it may throw or return nil (that entry is skipped this tick). Marks reached points and
---returns a sorted snapshot list of hits { entry, point, last }, so the caller can fire events (which yield) and
---mutate `watch` afterwards. One point per entry per tick.
function M.tick(watch, posOf)
    local hits, keys = {}, {}
    for k in pairs(watch) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do
        local e = watch[k]
        if not M.finished(e) then
            local ok, pos = pcall(posOf, e)
            local i = ok and pos and M.reached(e, pos) or nil
            if i then hits[#hits + 1] = { key = k, entry = e, point = i, last = M.mark(e, i) } end
        end
    end
    return hits
end

---Reconcile an entry with the holder's cached quest state (read-only, no lock). Returns 'keep' or 'drop'.
---  nil state (rows not cached): keep, decide nothing. Not active any more (done, failed, abandoned elsewhere): drop.
---  A pending entry (armed by accept, which runs before the row is committed) is kept until its row reads active once,
---  so the previous run's 'done' row never drops a fresh accept.
---  Persisted count behind the entry's `done` on M.HEAL_TICKS checks in a row (an emitted point was never
---  credited: lock timeout, dropped event): roll back to the persisted count so the point can be reached again.
---  One tick of lag is normal (the intake may still hold the lock), so it is tolerated. Credit stays bounded by
---  the verdict (count + 1 / count < total), so a roll-back can never over-pay.
M.HEAL_TICKS = 2
function M.heal(e, state)
    if type(state) ~= 'table' then return 'keep' end
    if state.status ~= 'active' then return e.pending and 'keep' or 'drop' end
    e.pending = nil
    local count = math.tointeger(type(state.progress) == 'table' and state.progress.count or 0) or 0
    if count >= e.done then
        e.lag = nil
        if count > e.done then e.done = math.min(count, #e.points) end -- credited elsewhere: catch up
        return 'keep'
    end
    e.lag = (e.lag or 0) + 1
    if e.lag >= M.HEAL_TICKS then
        e.lag, e.done, e.visited = nil, count, {}
    end
    return 'keep'
end

---Watch key of a held job: one entry per character + quest id.
function M.key(cid, qid) return tostring(cid) .. '|' .. tostring(qid) end

---Keys of entries owned by player src (they left), sorted.
function M.ownedBy(watch, src)
    local out = {}
    for k, e in pairs(watch) do
        if e.src == src then out[#out + 1] = k end
    end
    table.sort(out)
    return out
end

if GetCurrentResourceName then
    FhQuestsWatchRules = M
else
    return M
end
