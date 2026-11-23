-- fh_quests reward payout protocol (Q2). Pure Lua: no natives, no I/O. The server supplies the I/O (save a row,
-- call fh_economy / the inventory, look up fh_ledger) through `io` and this module decides the order.
--
-- A reward is split into parts, paid in this order: 'money' (fh_economy.pay), 'rep' (fh_economy.rep), then
-- 'item:<i>' per item (player inventory AddItem). Progress keys (in fh_quest_state.progress JSON):
--   reward_pending  = true while any part is still owed (set by the engine on active -> done)
--   reward_paid     = { [part key] = true }   parts already delivered
--   reward_inflight = { key, at }             a part being paid right now (at = unix seconds)
--
-- Exactly once, per part:
--   1. persist reward_inflight = part BEFORE calling the payer (if that write fails, nothing is paid);
--   2. call the payer; 3. persist reward_paid[part] (or clear inflight on a refusal).
-- A crash between 1 and 3 leaves reward_inflight in the row. The next run settles it first:
--   money/rep: fh_ledger is the truth (fh_economy writes a row for every pay/rep): a matching row since `at`
--              means paid, none means not paid (retried); a failed lookup leaves the marker and stops.
--   items:     no ledger, so the part is assumed delivered (at most once; the server logs it).
-- The engine only emits a reward on active -> done, and canStart refuses while reward_pending, so a re-fired
-- event or a second 'complete' never reaches this module twice for one completion.
local M = {}

local function engine() return FhQuestsEngine or require('engine') end

-- fh_ledger.created_at vs os.time(): rows at most this many seconds before reward_inflight.at still count.
M.LEDGER_SLACK_S = 5

M.LEDGER_SQL = 'SELECT id FROM fh_ledger WHERE citizenid = ? AND kind = ? AND reason = ? AND amount = ? '
    .. 'AND region_id = ? AND created_at >= FROM_UNIXTIME(?) LIMIT 1'

function M.reason(def) return 'quest:' .. def.id end

---Ordered reward parts of a def.
---@return table parts  { { key, kind = 'pay'|'rep'|'item', amount?, delta?, region_id?, name?, info? }... }
function M.parts(def)
    local r, out = def.rewards or {}, {}
    if (r.money or 0) > 0 then
        out[#out + 1] = { key = 'money', kind = 'pay', amount = r.money, region_id = def.region_id }
    end
    if r.rep ~= nil then
        out[#out + 1] = { key = 'rep', kind = 'rep', region_id = r.rep.region_id, delta = r.rep.delta }
    end
    for i, it in ipairs(r.items or {}) do
        out[#out + 1] = { key = 'item:' .. i, kind = 'item', name = it.name, amount = it.amount, info = it.info }
    end
    return out
end

function M.part(def, key)
    for _, p in ipairs(M.parts(def)) do
        if p.key == key then return p end
    end
    return nil
end

function M.pending(state)
    return type(state) == 'table' and state.status == 'done' and (state.progress or {}).reward_pending == true
end

function M.inflight(state)
    local f = type(state) == 'table' and (state.progress or {}).reward_inflight
    if type(f) == 'table' and type(f.key) == 'string' then return f end
    return nil
end

---Parts still owed (empty unless the state is done with reward_pending).
function M.owed(def, state)
    if not M.pending(state) then return {} end
    local paid, out = state.progress.reward_paid or {}, {}
    for _, p in ipairs(M.parts(def)) do
        if not paid[p.key] then out[#out + 1] = p end
    end
    return out
end

local function copy(state)
    local s = {}
    for k, v in pairs(state) do s[k] = v end
    local p = {}
    for k, v in pairs(state.progress or {}) do p[k] = v end
    local paid = {}
    for k, v in pairs(p.reward_paid or {}) do paid[k] = v end
    p.reward_paid = paid
    s.progress = p
    return s
end

---Mark `key` in flight. Refused when nothing is pending, another part is in flight, or `key` is not owed.
---@return table|nil state, string|nil err
function M.begin(def, state, key, now)
    if not M.pending(state) then return nil, 'fh_no_reward' end
    if M.inflight(state) then return nil, 'fh_reward_inflight' end
    local owed = false
    for _, p in ipairs(M.owed(def, state)) do
        if p.key == key then owed = true end
    end
    if not owed then return nil, 'fh_reward_not_owed' end
    local s = copy(state)
    s.progress.reward_inflight = { key = key, at = now }
    s.updated_at = now
    return s
end

---Clear every reward marker once nothing is owed (engine.rewardPaid + drop reward_paid / reward_inflight).
function M.finish(state, now)
    local s = copy(engine().rewardPaid(state, now))
    s.progress.reward_paid = nil
    s.progress.reward_inflight = nil
    return s
end

---Settle the in-flight part. outcome: 'paid' | 'assumed' (delivered, outcome unknown: items) | 'refused' (not paid,
---owed again). When the last owed part is paid the reward is finished (reward_pending cleared).
---@return table|nil state, string|nil err
function M.settle(def, state, key, outcome, now)
    local f = M.inflight(state)
    if not f or f.key ~= key then return nil, 'fh_reward_not_inflight' end
    local s = copy(state)
    s.progress.reward_inflight = nil
    s.updated_at = now
    if outcome == 'paid' or outcome == 'assumed' then
        s.progress.reward_paid[key] = true
    elseif outcome ~= 'refused' then
        return nil, 'fh_bad_outcome'
    end
    if #M.owed(def, s) == 0 then s = M.finish(s, now) end
    return s
end

---fh_ledger lookup for a money/rep part paid since `inflight.at` (see LEDGER_SQL). nil for item parts.
---@return string|nil sql, table|nil params
function M.ledgerQuery(def, part, citizenid, inflight)
    if part.kind ~= 'pay' and part.kind ~= 'rep' then return nil end
    return M.LEDGER_SQL, { citizenid, part.kind, M.reason(def), part.kind == 'pay' and part.amount or part.delta,
        part.region_id, (inflight.at or 0) - M.LEDGER_SLACK_S }
end

---What an unknown outcome (payer threw, or a crash left the marker) settles to. ledgerHit: true/false/nil (lookup
---failed). Returns nil when it cannot be decided yet (keep the marker, try again later).
function M.resolveUnknown(part, ledgerHit)
    if not part then return 'refused' end -- the def no longer has this part: drop the marker
    if part.kind == 'item' then return 'assumed' end
    if ledgerHit == nil then return nil end
    return ledgerHit and 'paid' or 'refused'
end

---Drive the payout for one done state. io = {
---  now    = unix seconds,
---  save   = function(state) -> boolean   (persist the row; false = not written),
---  pay    = function(part)  -> called, ok, err   (called = false when the payer threw: outcome unknown),
---  ledger = function(part, inflight) -> true|false|nil   (money/rep only; nil = lookup failed),
--- }
---Stops at the first refusal or failed write. Returns the last state known to be persisted (the caller caches it)
---and a log { { key, outcome|'save_failed'|'ledger_unavailable', err? }... }.
function M.run(def, state, io)
    local log, t = {}, io.now
    if not M.pending(state) then return state, log end

    local f = M.inflight(state)
    if f then
        local part = M.part(def, f.key)
        local hit = nil
        if part and part.kind ~= 'item' then hit = io.ledger(part, f) end
        local outcome = M.resolveUnknown(part, hit)
        if not outcome then
            log[#log + 1] = { key = f.key, outcome = 'ledger_unavailable' }
            return state, log
        end
        log[#log + 1] = { key = f.key, outcome = outcome, recovered = true }
        local s = M.settle(def, state, f.key, outcome, t)
        if not io.save(s) then
            log[#log + 1] = { key = f.key, outcome = 'save_failed' }
            return state, log
        end
        state = s -- 'refused' here means "not paid before the crash": the loop below pays it now
    end

    while M.pending(state) do
        local part = M.owed(def, state)[1]
        if not part then
            local s = M.finish(state, t) -- nothing owed any more (def changed): clear the markers
            if io.save(s) then state = s end
            break
        end
        local s = assert(M.begin(def, state, part.key, t))
        if not io.save(s) then
            log[#log + 1] = { key = part.key, outcome = 'save_failed' } -- marker not persisted: nothing paid
            break
        end
        state = s
        local called, ok, err = io.pay(part)
        local outcome
        if called then
            outcome = ok and 'paid' or 'refused'
        else
            local hit = nil
            if part.kind ~= 'item' then hit = io.ledger(part, M.inflight(state)) end
            outcome = M.resolveUnknown(part, hit)
            if not outcome then
                log[#log + 1] = { key = part.key, outcome = 'ledger_unavailable', err = err }
                break -- the marker stays; the next run looks the ledger up again
            end
        end
        log[#log + 1] = { key = part.key, outcome = outcome, err = err }
        local s2 = assert(M.settle(def, state, part.key, outcome, t))
        if not io.save(s2) then
            log[#log + 1] = { key = part.key, outcome = 'save_failed' } -- the row keeps the marker: next run reconciles
            break
        end
        state = s2
        if outcome == 'refused' then break end
    end
    return state, log
end

if GetCurrentResourceName then
    FhQuestsRewards = M
else
    return M
end
