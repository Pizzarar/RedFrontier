-- fh_hands pure logic: tick math, wage state machine, per-owner lock, the wage-tick sequence (runOwner), top-up
-- amount. No FiveM globals: every DB / export / event call goes through an injected io table (unit-tested with lupa).
local M = {}

local function isNum(v) return type(v) == 'number' and v == v and v ~= math.huge and v ~= -math.huge end
local function isInt(v) return isNum(v) and v == math.floor(v) end
local function isStr(v) return type(v) == 'string' and v ~= '' end

---Elapsed time -> whole ticks, capped. Returns ticks, new_last_tick.
---Under the cap last_tick advances by exactly ticks*interval (remainder is kept). Over the cap the excess is
---dropped: last_tick jumps to `now`. A clock that went backwards yields 0 ticks and re-bases last_tick.
---@return integer ticks, number newLastTick
function M.ticksDue(last_tick, now, interval, maxCatchup)
    if not (isNum(last_tick) and isNum(now) and isNum(interval) and interval > 0 and isNum(maxCatchup)) then
        return 0, isNum(now) and now or 0
    end
    if now < last_tick then return 0, now end
    local n = math.floor((now - last_tick) / interval)
    if n <= 0 then return 0, last_tick end
    if n > maxCatchup then return math.max(0, math.floor(maxCatchup)), now end
    return n, last_tick + n * interval
end

---ticksDue as a list of per-tick last_tick targets, so every tick can be claimed (persisted) on its own.
---plan[#plan] == newLast. Over the cap the plan starts at now - n*interval (the excess is dropped).
---An empty plan with newLast ~= last_tick means "re-base only" (clock went backwards or a bad stored value).
---@return number[] plan, number newLast
function M.tickPlan(last_tick, now, interval, maxCatchup)
    local n, newLast = M.ticksDue(last_tick, now, interval, maxCatchup)
    local plan = {}
    if n == 0 then return plan, newLast end
    local start = newLast - n * interval
    for i = 1, n do plan[i] = start + i * interval end
    return plan, newLast
end

---Wage state machine for ONE tick. state = { unpaid = int, status = 'working'|'idle' }.
---paid=true  -> unpaid resets, hand works (runTask = true).
---paid=false -> unpaid+1, hand idles (no task); reaching quitAfter makes the hand quit.
---@return table newState, boolean runTask
function M.step(state, paid, quitAfter)
    local unpaid = (state and state.unpaid) or 0
    if paid then return { unpaid = 0, status = 'working' }, true end
    unpaid = unpaid + 1
    if quitAfter and unpaid >= quitAfter then return { unpaid = unpaid, status = 'quit' }, false end
    return { unpaid = unpaid, status = 'idle' }, false
end

-- fh_economy charge errors (core B7). Nothing was debited for any of them.
local RETRY = { fh_charge_busy = true, ledger_failed = true } -- transient on the economy side: try the tick again later
local GONE = { no_player = true, player_changed = true }      -- owner left / switched character: stop, no strike
-- The export call threw (Lua error inside fh_economy, or fh_economy mid-restart): the outcome is unknown, so the tick is NOT handed back
-- (never charged twice) and it is no strike either (not the owner's fault): that wage is skipped, owner's favour.
local SKIP = { charge_unavailable = true }

---Classify a charge result. 'paid' | 'retry' (no strike, tick handed back) | 'gone' (owner left, tick handed back)
---| 'skip' (charge_unavailable: tick stays claimed, no strike, no task)
---| 'unpaid' (fh_insufficient_funds, removemoney_refused, validation codes, anything else: a strike, no task).
---@return string outcome
function M.chargeOutcome(ok, err)
    if ok == true then return 'paid' end
    if RETRY[err] then return 'retry' end
    if GONE[err] then return 'gone' end
    if SKIP[err] then return 'skip' end
    return 'unpaid'
end

---Per-key mutex for a cooperative scheduler (one per citizenid). Nothing yields between the check and the set, so
---two coroutines can never both hold a key. opts = { wait = fn (yields), clock = fn -> ms, timeoutMs = n|nil }:
---timeoutMs nil = try once. fn runs in pcall; the key is always released.
---@return boolean ok, any ... fn's results on success; false, 'busy' | false, 'error', msg on failure
function M.withLock(locks, key, opts, fn, ...)
    if locks[key] then
        if not opts.timeoutMs then return false, 'busy' end
        local deadline = opts.clock() + opts.timeoutMs
        while locks[key] do
            if opts.clock() >= deadline then return false, 'busy' end
            opts.wait()
        end
    end
    locks[key] = true
    local res = table.pack(pcall(fn, ...))
    locks[key] = nil
    if not res[1] then return false, 'error', tostring(res[2]) end
    return true, table.unpack(res, 2, res.n)
end

---DB rows -> cached owner entry. Unknown kinds are left alone in the DB (config may bring them back); rows left in
---'quit' (a delete that failed) are skipped and returned so the caller can delete them.
---@return table entry { citizenid, src, list = { [kind] = { last_tick, unpaid, status } } }, string[] quitKinds
function M.entryFromRows(citizenid, src, rows, cfg)
    local e, quitKinds = { citizenid = citizenid, src = src, list = {} }, {}
    for _, r in ipairs(rows or {}) do
        if type(r) == 'table' and cfg.hands[r.hand_kind] then
            if r.status == 'quit' then
                quitKinds[#quitKinds + 1] = r.hand_kind
            else
                e.list[r.hand_kind] = { last_tick = tonumber(r.last_tick), unpaid = tonumber(r.unpaid) or 0,
                    status = r.status == 'idle' and 'idle' or 'working' }
            end
        end
    end
    return e, quitKinds
end

-- One hand's due ticks. Order per tick, chosen so a crash or failed write anywhere can skip a wage but never
-- charge the same tick twice:
--   1. claim: CAS last_tick from -> target in the DB (the row, not memory, says the tick is taken)
--   2. charge, right after a synchronous online() check (charge reads the citizenid on src before its first yield)
--   3. retry/gone: nothing was debited, CAS the tick back (target -> from) so it is charged later, no strike
--      skip (charge outcome unknown): keep the claim, no strike, no task, stop this hand's ticks for this run
--      (returns 'ok': the owner's other hands still run)
--   4. paid/unpaid: step the state machine, persist unpaid/status (CAS on last_tick = target), run the task
-- Returns 'ok' or 'gone' (owner no longer loaded: the caller stops this owner).
local function runHand(e, kind, h, def, cfg, now, io)
    local plan, newLast = M.tickPlan(h.last_tick, now, cfg.tickSeconds, cfg.maxCatchupTicks)
    if #plan == 0 then
        if newLast ~= h.last_tick then -- re-base (clock went backwards / bad value) is persisted, not memory-only
            if io.setLast(kind, h.last_tick, newLast) then
                h.last_tick = newLast
            else
                io.log(('re-base of %s/%s failed'):format(e.citizenid, kind))
            end
        end
        return 'ok'
    end
    for _, target in ipairs(plan) do
        if e.list[kind] ~= h then return 'ok' end -- fired / reloaded meanwhile: this h is stale
        if not io.online() then return 'gone' end
        local from = h.last_tick
        if not io.setLast(kind, from, target) then
            -- row changed or vanished under us (or DB error): the DB is the truth, the next load picks it up
            io.log(('claim %s/%s %s->%s failed'):format(e.citizenid, kind, tostring(from), tostring(target)))
            return 'ok'
        end
        h.last_tick = target
        local ok, err
        if e.list[kind] == h and io.online() then
            ok, err = io.charge(def.wage, 'wage:' .. kind)
        else
            ok, err = false, 'no_player'
        end
        local outcome = M.chargeOutcome(ok, err)
        if outcome == 'retry' or outcome == 'gone' then
            if io.setLast(kind, target, from) then
                h.last_tick = from
            else
                -- DB keeps `target`: one wage is skipped (in the owner's favour), never charged twice
                io.log(('release %s/%s %s->%s failed (%s)'):format(e.citizenid, kind, tostring(target),
                    tostring(from), tostring(err)))
            end
            return outcome == 'gone' and 'gone' or 'ok'
        end
        if outcome == 'skip' then
            io.log(('charge %s/%s tick %s: %s, wage skipped (claim kept, no strike)'):format(e.citizenid, kind,
                tostring(target), tostring(err)))
            return 'ok'
        end
        if outcome == 'unpaid' then
            io.log(('unpaid %s/%s: %s'):format(e.citizenid, kind, tostring(err))) -- the line OWNER-TESTS checks
            io.emit('fh:hands:unpaid', { hand_kind = kind, reason = err })
        end
        local nextState, run = M.step(h, outcome == 'paid', cfg.quitAfterUnpaid)
        h.unpaid, h.status = nextState.unpaid, nextState.status
        if h.status == 'quit' then
            if e.list[kind] == h then e.list[kind] = nil end
            if not io.remove(kind) then
                io.log(('delete of quit hand %s/%s failed; marking quit'):format(e.citizenid, kind))
                io.saveState(kind, target, h.unpaid, 'quit') -- loader skips and deletes 'quit' rows
            end
            io.emit('fh:hands:quit', { hand_kind = kind })
            return 'ok'
        end
        if not io.saveState(kind, target, h.unpaid, h.status) then
            io.log(('state save %s/%s failed'):format(e.citizenid, kind))
        end
        if run then
            local tok, info = io.runTask(def.task, kind)
            if tok ~= true then
                io.log(('task %s for %s/%s failed: %s'):format(def.task, e.citizenid, kind, tostring(info)))
                io.emit('fh:hands:task_failed', { hand_kind = kind, task = def.task, reason = info })
            end
        end
    end
    return 'ok'
end

---Process every due tick for one owner. The caller holds the owner's lock. Kinds are snapshotted first, so nothing
---iterates a table that can change while a DB call yields.
---io (DB calls may yield; online/emit/log never yield):
---  online() -> bool                       entry still cached AND src still has this citizenid loaded
---  setLast(kind, expect, set) -> bool     UPDATE last_tick = set WHERE last_tick = expect (exactly one row)
---  saveState(kind, last_tick, unpaid, status) -> bool   CAS on last_tick
---  remove(kind) -> bool                   DELETE, true when a row went
---  charge(amount, reason) -> ok, err      fh_economy charge on the owner's src
---  runTask(task, kind) -> ok, info
---  emit(name, payload), log(msg)
---@return string 'done' | 'gone'
function M.runOwner(e, cfg, now, io)
    local kinds = {}
    for kind in pairs(e.list) do kinds[#kinds + 1] = kind end
    table.sort(kinds)
    for _, kind in ipairs(kinds) do
        local h, def = e.list[kind], cfg.hands[kind]
        if h and def and runHand(e, kind, h, def, cfg, now, io) == 'gone' then return 'gone' end
    end
    return 'done'
end

---How many to add: up to perTick, never past cap, never negative.
function M.topupAmount(have, cap, perTick)
    if not (isNum(have) and isNum(cap) and isNum(perTick)) then return 0 end
    local room = cap - have
    if room <= 0 or perTick <= 0 then return 0 end
    return math.floor(math.min(room, perTick))
end

---Count of one item in a container snapshot (slot -> { name, amount }).
function M.countItem(items, name)
    local total = 0
    for _, it in pairs(items or {}) do
        if type(it) == 'table' and it.name == name and isNum(it.amount) then total = total + it.amount end
    end
    return total
end

---One chest top-up step (the lumber_topup task). spec = { item, cap, perTick } (cfg.lumber).
---io = { snapshot(ref) -> items|nil, why ; addItem(ref, item, amount) -> ok, err } (fh_core exports; may yield).
---@return boolean ok, number|string amountAddedOrErr
function M.chestTopup(ref, spec, io)
    if not ref then return false, 'no_homestead' end
    local items, why = io.snapshot(ref)
    if not items then return false, why or 'no_chest' end
    local amount = M.topupAmount(M.countItem(items, spec.item), spec.cap, spec.perTick)
    if amount == 0 then return true, 0 end
    local added, err = io.addItem(ref, spec.item, amount)
    if not added then return false, err end
    return true, amount
end

---One trough top-up step (the feed_topup task). spec = { perTick, cap? } (cfg.feed).
---io = { getTrough(citizenid) -> { plotId, count, capacity }|nil, why ; feedTrough(citizenid, n) -> added|nil, why }.
---Items are implicit (fh_homestead:feedTrough adds feedbags). Full trough is an ok no-op (true, 0); missing/unready/
---busy trough or throwing export is a soft task failure (false, reason).
---@return boolean ok, number|string amountAddedOrErr
function M.troughTopup(citizenid, spec, io)
    if not isStr(citizenid) then return false, 'fh_no_trough' end
    local okGet, info, why = pcall(io.getTrough, citizenid)
    if not okGet then return false, 'trough_unavailable' end
    if type(info) ~= 'table' then return false, type(why) == 'string' and why or 'fh_no_trough' end
    if not (isNum(info.count) and isNum(info.capacity)) then return false, 'fh_trough_check_failed' end
    local cap = spec.cap and math.min(spec.cap, info.capacity) or info.capacity
    local amount = M.topupAmount(info.count, cap, spec.perTick)
    if amount == 0 then return true, 0 end
    local okFeed, added, fwhy = pcall(io.feedTrough, citizenid, amount)
    if not okFeed then return false, 'trough_unavailable' end
    if isNum(added) and added > 0 then return true, added end
    if fwhy == 'fh_trough_full' then return true, 0 end
    return false, type(fwhy) == 'string' and fwhy or 'fh_trough_failed'
end

---Unlock ids a new hire needs, given the hands already employed (list = entry.list, known kinds only): always
---cfg.unlockId; with N hands already, also cfg.extraHandUnlocks[N + 1]. Past the last configured slot: nil, 'max_hands'.
---@return string[]|nil ids, string? err
function M.hireUnlocks(list, cfg)
    local n = 0
    for _ in pairs(list or {}) do n = n + 1 end
    local ids = { cfg.unlockId }
    if n == 0 then return ids end
    local extra = type(cfg.extraHandUnlocks) == 'table' and cfg.extraHandUnlocks[n + 1] or nil
    if not isStr(extra) then return nil, 'max_hands' end
    ids[2] = extra
    return ids
end

---Hire gate. canUnlock(unlock_id) -> allowed (fh_progression canUnlock; may yield or throw). Fail closed: every
---required unlock must answer exactly true; a throw, unknown_unlock or any other refusal is 'locked'.
---@return boolean ok, string? err  max_hands | locked
function M.hireGate(list, cfg, canUnlock)
    local ids, err = M.hireUnlocks(list, cfg)
    if not ids then return false, err end
    for _, id in ipairs(ids) do
        local called, allowed = pcall(canUnlock, id)
        if not called or allowed ~= true then return false, 'locked' end
    end
    return true
end

---`fh_hand_tick <serverId>` arg parsing. @return table|nil { target }, string? err
function M.parseTickArgs(args)
    local t = type(args) == 'table' and tonumber(args[1]) or nil
    if not (isInt(t) and t > 0) then return nil, 'fh_bad_target' end
    return { target = t }
end

---The `now` that makes exactly the oldest hand's next tick due (never earlier than the real now). nil when no hands.
function M.forcedNow(list, cfg, now)
    local oldest
    for _, h in pairs(list or {}) do
        if isNum(h.last_tick) and (not oldest or h.last_tick < oldest) then oldest = h.last_tick end
    end
    if not oldest then return nil end
    return math.max(now, oldest + cfg.tickSeconds)
end

---Validate a hands config. @return boolean ok, string|nil err
function M.validateConfig(cfg)
    if type(cfg) ~= 'table' then return false, 'bad_config' end
    if not isStr(cfg.regionId) then return false, 'bad_regionId' end
    if not isStr(cfg.unlockId) then return false, 'bad_unlockId' end
    if not (isNum(cfg.tickSeconds) and cfg.tickSeconds > 0) then return false, 'bad_tickSeconds' end
    if not (isNum(cfg.pollSeconds) and cfg.pollSeconds >= 1) then return false, 'bad_pollSeconds' end
    if not (isInt(cfg.maxCatchupTicks) and cfg.maxCatchupTicks >= 1) then return false, 'bad_maxCatchupTicks' end
    if not (isInt(cfg.quitAfterUnpaid) and cfg.quitAfterUnpaid >= 1) then return false, 'bad_quitAfterUnpaid' end
    if type(cfg.hands) ~= 'table' then return false, 'bad_hands' end
    for kind, h in pairs(cfg.hands) do
        if type(kind) ~= 'string' or type(h) ~= 'table' or not isNum(h.wage) or h.wage <= 0
            or not isStr(h.task) then return false, 'bad_hand_' .. tostring(kind) end
    end
    if cfg.extraHandUnlocks ~= nil then
        if type(cfg.extraHandUnlocks) ~= 'table' then return false, 'bad_extraHandUnlocks' end
        local top = 1
        for slot, id in pairs(cfg.extraHandUnlocks) do
            if not (isInt(slot) and slot >= 2) or not isStr(id) then return false, 'bad_extraHandUnlocks' end
            if slot > top then top = slot end
        end
        for slot = 2, top do -- contiguous from 2: a hole would silently cap hires early
            if not isStr(cfg.extraHandUnlocks[slot]) then return false, 'bad_extraHandUnlocks' end
        end
    end
    local f = cfg.feed
    if type(f) ~= 'table' or not (isInt(f.perTick) and f.perTick >= 1)
        or (f.cap ~= nil and not (isInt(f.cap) and f.cap >= 0)) then return false, 'bad_feed' end
    local l = cfg.lumber
    if type(l) ~= 'table' or not isStr(l.item) or not (isInt(l.cap) and l.cap >= 0)
        or not (isInt(l.perTick) and l.perTick >= 1) then return false, 'bad_lumber' end
    return true
end

if GetCurrentResourceName then FhHandsLogic = M else return M end
