-- Treasure lead rules (progression-02 G2): loot roll, which held lead a dig spends, map area. Pure Lua, no FiveM
-- globals; unit-tested (spec/fence_leads_spec.lua). The dig itself (lock, order of side effects) is server/leads.lua.
local M = {}

local function isInt(n) return type(n) == 'number' and n == n and n == math.floor(n) end
local function isNum(n) return type(n) == 'number' and n == n and n ~= math.huge and n ~= -math.huge end

---Player server id: a positive whole number (same rule as fh_economy FhLedgerLogic.validSrc; NaN, inf, floats,
---0 and -1 = every client are refused).
function M.validSrc(src)
    return type(src) == 'number' and src == src and src > 0 and src % 1 == 0
end

local function point(t)
    if type(t) ~= 'table' or not isNum(t.x) or not isNum(t.y) or not isNum(t.z) then return nil end
    return { x = t.x, y = t.y, z = t.z }
end

---Spot id -> { x, y, z } from the server-only spot table (FhFenceLeadSpots, server/config_leads.lua), or nil.
function M.spotOf(spots, id)
    local s = type(spots) == 'table' and type(id) == 'string' and spots[id]
    return type(s) == 'table' and point(s.coords) or nil
end

---The spot id whose coords are exactly `target`, or nil (maps a pre-G2b lead's stored target back to its spot).
function M.spotAt(spots, target)
    if type(spots) ~= 'table' or type(target) ~= 'table' then return nil end
    local ids = {}
    for id in pairs(spots) do if type(id) == 'string' then ids[#ids + 1] = id end end
    table.sort(ids) -- deterministic if two ids share coords
    for _, id in ipairs(ids) do
        local c = M.spotOf(spots, id)
        if c and c.x == target.x and c.y == target.y and c.z == target.z then return id end
    end
    return nil
end

---Lead item info -> target {x,y,z}, spot id (or nil). SERVER side: `spots` is the server-only spot table.
---Current leads (trade.lua, FhFenceLogic.leadInfo): info = { lead = '<id>' } -> that spot; an unknown id is nil (no
---fallback to anything else in the info). Pre-G2b leads: info = { target = {x,y,z}, hint } written by the server at
---purchase -> that target as before (id = the spot with those exact coords, else nil).
function M.targetOf(info, spots)
    if type(info) ~= 'table' then return nil end
    if info.lead ~= nil then
        local t = M.spotOf(spots, info.lead)
        if not t then return nil end
        return t, info.lead
    end
    local t = point(info.target)
    if not t then return nil end
    return t, M.spotAt(spots, t)
end

---Hint text for a lead: the spot's hint (server-only), else a pre-G2b lead's stored hint, else ''.
function M.hintOf(info, spots, id)
    local s = id and type(spots) == 'table' and spots[id]
    if type(s) == 'table' and type(s.hint) == 'string' then return s.hint end
    return type(info) == 'table' and info.hint ~= nil and tostring(info.hint) or ''
end

---3D distance check. pos/target = {x,y,z}.
function M.within(pos, target, radius)
    if type(pos) ~= 'table' or type(target) ~= 'table' or not isNum(radius) then return false end
    if not isNum(pos.x) or not isNum(pos.y) or not isNum(pos.z) then return false end
    local dx, dy, dz = pos.x - target.x, pos.y - target.y, pos.z - target.z
    return dx * dx + dy * dy + dz * dz <= radius * radius
end

---Loot table check. Every entry: whole weight >= 1; money = { min, max } whole, 0 <= min <= max (optional);
---item = non-empty string with whole qty >= 1 (optional); an entry must pay something. maxPay caps money.max.
---@return boolean ok, string|nil reason
function M.validLoot(loot, maxPay)
    if type(loot) ~= 'table' or #loot == 0 then return false, 'empty' end
    for i, e in ipairs(loot) do
        if type(e) ~= 'table' or not isInt(e.weight) or e.weight < 1 then return false, 'weight@' .. i end
        local pays = false
        if e.money ~= nil then
            local m = e.money
            if type(m) ~= 'table' or not isInt(m[1]) or not isInt(m[2]) or m[1] < 0 or m[1] > m[2] then
                return false, 'money@' .. i
            end
            if maxPay and m[2] > maxPay then return false, 'money_cap@' .. i end
            pays = m[2] > 0
        end
        if e.item ~= nil then
            if type(e.item) ~= 'string' or e.item == '' or not isInt(e.qty) or e.qty < 1 then return false, 'item@' .. i end
            pays = true
        end
        if not pays then return false, 'pays_nothing@' .. i end
    end
    return true
end

---One weighted loot roll. rng(m, n) -> whole number in [m, n] (math.random's contract). Calls rng exactly once to
---pick the entry, then once for the money when the entry has a range with min < max: same rng state = same result.
---@return table|nil { index, money (whole, >= 0), item|nil, qty (0 without item) }, string|nil reason
function M.roll(loot, rng)
    local ok, why = M.validLoot(loot)
    if not ok then return nil, 'bad_loot:' .. why end
    local total = 0
    for _, e in ipairs(loot) do total = total + e.weight end
    local r = rng(1, total)
    if not isInt(r) or r < 1 or r > total then return nil, 'bad_rng' end
    local idx
    for i, e in ipairs(loot) do
        r = r - e.weight
        if r <= 0 then idx = i; break end
    end
    local e = loot[idx]
    local money = 0
    if e.money then
        local lo, hi = e.money[1], e.money[2]
        money = lo == hi and lo or rng(lo, hi)
        if not isInt(money) or money < lo or money > hi then return nil, 'bad_rng' end
    end
    return { index = idx, money = money, item = e.item, qty = e.item and e.qty or 0 }
end

---Which held lead a dig at `pos` spends. sections = array of { ref, items = snapshot (slot -> item) } in priority
---order; spots = the server-only spot table (targetOf). A lead "matches" when its target is within digRadius of pos. The chosen section must hold a matching lead
---and ONLY matching leads: fh_core removeItem takes "one of that name" from a section, not a given slot, so a section
---that also holds a lead for another spot could lose the wrong one ('lead_mixed', nothing is taken).
---@return table|nil { ref, target, id }, string|nil reason  no_lead | lead_too_far | lead_mixed
function M.pick(sections, pos, digRadius, leadItem, spots)
    local any, near = false, false
    for _, sec in ipairs(sections or {}) do
        local mine, other, target, tid = 0, 0, nil, nil
        for _, it in pairs(sec.items or {}) do
            if type(it) == 'table' and it.name == leadItem then
                any = true
                local t, id = M.targetOf(it.info, spots)
                if t and M.within(pos, t, digRadius) then
                    mine = mine + (tonumber(it.amount) or 1)
                    if not target then target, tid = t, id end
                else
                    other = other + 1
                end
            end
        end
        if mine > 0 then
            near = true
            if other == 0 then return { ref = sec.ref, target = target, id = tid } end
        end
    end
    if not any then return nil, 'no_lead' end
    if not near then return nil, 'lead_too_far' end
    return nil, 'lead_mixed'
end

M.AREA_GRID = 5   -- metres: the area centre (x, y) is rounded to this grid
M.AREA_ZGRID = 10 -- metres: and its height to this one

---Map area for a lead: a circle of areaRadius whose centre is offset from the target by 25-65 % of the radius, in a
---direction fixed by the target coords (stable across polls, so the blip does not jump), then rounded to a 5 m grid
---(10 m in z, offset by half a cell) so the client cannot invert the offset back to the exact spot (this file is a
---shared script: clients have the code, but never a target: those are in the server-only server/config_leads.lua). The target stays inside the circle (rounding moves the centre <= 3.6 m).
---@return table { x, y, z } whole numbers
function M.area(target, areaRadius)
    local ix = math.floor(target.x * 10)
    local iy = math.floor(target.y * 10)
    local h = ((ix * 73856093) ~ (iy * 19349663)) & 0x7fffffff
    local angle = math.rad(h % 360)
    local dist = areaRadius * (0.25 + 0.4 * ((h // 360) % 101) / 100)
    local g, zg = M.AREA_GRID, M.AREA_ZGRID
    local function snap(v, step) return math.floor(v / step + 0.5) * step end
    return { x = snap(target.x + math.cos(angle) * dist, g), y = snap(target.y + math.sin(angle) * dist, g),
        z = math.floor(target.z / zg) * zg + zg // 2 }
end

---Pay region for a lead: the region of the stop whose stock sells this spot id, else cfg.leads.regionId (also for a
---pre-G2b lead whose target matches no spot: id = nil). Stops are scanned in sorted order (deterministic).
function M.regionFor(cfg, id)
    if type(id) == 'string' then
        local stopIds = {}
        for stopId in pairs(cfg.stock or {}) do stopIds[#stopIds + 1] = stopId end
        table.sort(stopIds)
        for _, stopId in ipairs(stopIds) do
            for _, e in ipairs(cfg.stock[stopId].leads or {}) do
                if e.lead == id then
                    local stop = cfg.stops and cfg.stops[stopId]
                    if stop and stop.region_id then return stop.region_id end
                end
            end
        end
    end
    return cfg.leads and cfg.leads.regionId
end

---Startup check (server): every stock lead id resolves to a spot. @return string[] ids that do not (never sold)
function M.missingSpots(cfg, spots)
    local bad = {}
    for stopId, s in pairs(cfg.stock or {}) do
        for i, e in ipairs(s.leads or {}) do
            if not M.spotOf(spots, e.lead) then bad[#bad + 1] = ('%s#%d=%s'):format(stopId, i, tostring(e.lead)) end
        end
    end
    table.sort(bad)
    return bad
end

---Player-facing text for a dig result. ok/res = what the server's dig returned.
M.messages = {
    no_lead = "You don't have a treasure lead.",
    lead_too_far = 'Nothing buried here. Read the hint again.',
    lead_mixed = 'You carry leads for other spots in the same place. Stow them elsewhere first.',
    no_room = "No room for what's buried here. Make space and dig again.",
    dig_busy = 'You are already digging.',
    dig_cooldown = 'Catch your breath before you dig again.',
    no_player = 'Your character is not loaded.',
    player_changed = 'Your character changed during the dig. Nothing was taken.',
    dig_player_changed = 'Your character changed during the dig. An admin has been told.',
    fh_player_offline = 'Your character is not loaded.',
    lead_bad_config = 'This lead cannot be dug right now. Your lead was not used.',
    dig_error = 'The dig went wrong. Your lead was not used.',
    dig_error_taken = 'The dig went wrong after your lead was used. An admin has been told.',
}

function M.why(code) return M.messages[code] or ('Could not dig: ' .. tostring(code)) end

function M.notice(ok, res)
    if not ok then return M.why(res) end
    res = res or {}
    local parts = {}
    if (res.money or 0) > 0 then parts[#parts + 1] = ('$%d'):format(res.money) end
    if res.item then parts[#parts + 1] = ('%d x %s'):format(res.qty or 1, res.label or res.item) end
    if #parts == 0 then
        if res.owed then return 'You found the cache, but it could not be handed over: an admin has been told.' end
        return 'You dug up the cache.'
    end
    local found = 'You dug up ' .. table.concat(parts, ' and ') .. '.'
    if res.owed then found = found .. ' The rest could not be handed over: an admin has been told.' end
    return found
end

if _G.GetCurrentResourceName then _G.FhFenceLeadsLogic = M end
return M
