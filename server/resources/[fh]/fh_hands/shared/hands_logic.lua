-- fh_hands pure logic: tick math, wage state machine, top-up amount. No FiveM globals (unit-tested with lupa).
local M = {}

local function isNum(v) return type(v) == 'number' and v == v and v ~= math.huge and v ~= -math.huge end
local function isInt(v) return isNum(v) and v == math.floor(v) end

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

---Validate a hands config. @return boolean ok, string|nil err
function M.validateConfig(cfg)
    if type(cfg) ~= 'table' then return false, 'bad_config' end
    if not (isNum(cfg.tickSeconds) and cfg.tickSeconds > 0) then return false, 'bad_tickSeconds' end
    if not (isInt(cfg.maxCatchupTicks) and cfg.maxCatchupTicks >= 1) then return false, 'bad_maxCatchupTicks' end
    if not (isInt(cfg.quitAfterUnpaid) and cfg.quitAfterUnpaid >= 1) then return false, 'bad_quitAfterUnpaid' end
    if type(cfg.hands) ~= 'table' then return false, 'bad_hands' end
    for kind, h in pairs(cfg.hands) do
        if type(kind) ~= 'string' or type(h) ~= 'table' or not isNum(h.wage) or h.wage <= 0
            or type(h.task) ~= 'string' then return false, 'bad_hand_' .. tostring(kind) end
    end
    return true
end

if GetCurrentResourceName then FhHandsLogic = M else return M end
