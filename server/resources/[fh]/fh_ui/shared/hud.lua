-- Pure HUD logic for fh_ui passive widgets (U2): buff list and own drop-bag countdown. No natives, specced under
-- busted (spec/ui_hud_spec.lua). Time is injected (seconds, any monotonic local clock) so specs use a fake clock.
--
-- Clock note: fh_buffs sends `expires_at` on the SERVER's GetGameTimer clock and fh_death sends an os.time epoch;
-- neither is comparable to the client clock and neither payload carries a server "now". Rows therefore need a
-- server-computed `remaining` (seconds). Until the lanes send it, entries without `remaining` have `remaining = nil`
-- (NUI shows "--"). See README "Contract requests".
local M = {}

M.maxBuffs = 8
M.maxBags = 4

local function finite(n) return type(n) == 'number' and n == n and n > -math.huge and n < math.huge end

-- 'well_fed' -> 'Well Fed'
function M.label(id)
    if type(id) ~= 'string' or id == '' then return '?' end
    local s = id:gsub('_', ' '):gsub('(%a)([%w]*)', function(a, b) return a:upper() .. b end)
    return s
end

-- Seconds left on an entry or nil when unknown. `remaining` is the only usable field (see clock note).
local function secondsLeft(e)
    if type(e) == 'table' and finite(e.remaining) then return e.remaining end
    return nil
end

local function byDeadline(a, b)
    local ad, bd = a.deadline or math.huge, b.deadline or math.huge
    if ad ~= bd then return ad < bd end
    return tostring(a.id) < tostring(b.id)
end

-- Snapshot { [buff_id] = { magnitude, expires_at, remaining? } } -> rows with a local `deadline`.
-- Rows already at 0 remaining are dropped; unknown remaining keeps the row (deadline nil).
function M.buffRows(snapshot, now)
    local rows = {}
    if type(snapshot) ~= 'table' then return rows end
    for id, e in pairs(snapshot) do
        if type(id) == 'string' and type(e) == 'table' then
            local left = secondsLeft(e)
            if left == nil or left > 0 then
                rows[#rows + 1] = {
                    id = id, label = M.label(id),
                    magnitude = finite(e.magnitude) and e.magnitude or nil,
                    deadline = left and (now + left) or nil,
                }
            end
        end
    end
    table.sort(rows, byDeadline)
    while #rows > M.maxBuffs do rows[#rows] = nil end
    return rows
end

-- 8-way compass word from (px,py) to (bx,by); x east, y north. nil when either position is unusable.
function M.compass(px, py, bx, by)
    if not (finite(px) and finite(py) and finite(bx) and finite(by)) then return nil end
    local dx, dy = bx - px, by - py
    if dx == 0 and dy == 0 then return 'here' end
    local deg = math.deg(math.atan(dx, dy)) % 360 -- 0 = north, 90 = east
    local names = { 'N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW' }
    return names[math.floor((deg + 22.5) / 45) % 8 + 1]
end

-- Refresh only direction/distance on stored bag rows from the player position. The deadline is never touched, so
-- periodic refreshes cannot reset the countdown (it is fixed when the server list arrives).
function M.retarget(rows, player)
    for _, r in ipairs(rows or {}) do
        r.dir, r.dist = nil, nil
        if type(player) == 'table' and finite(r.x) and finite(r.y) and finite(player.x) and finite(player.y) then
            r.dir = M.compass(player.x, player.y, r.x, r.y)
            r.dist = math.floor(math.sqrt((r.x - player.x) ^ 2 + (r.y - player.y) ^ 2) + 0.5)
        end
    end
    return rows
end

-- Bag list (fh:death:bags) -> own bags only. Ownership is never guessed: only entries the server marked
-- `mine == true` are shown. TODO(contract): publicList currently has no `mine`/`remaining`; request in README.
-- player = { x, y } optional, for direction and distance.
function M.bagRows(list, now, player)
    local rows = {}
    if type(list) ~= 'table' then return rows end
    for _, b in ipairs(list) do
        if type(b) == 'table' and type(b.id) == 'string' and b.mine == true then
            local left = secondsLeft(b)
            if left == nil or left > 0 then
                local row = { id = b.id, deadline = left and (now + left) or nil,
                    x = finite(b.x) and b.x or nil, y = finite(b.y) and b.y or nil }
                M.retarget({ row }, player)
                rows[#rows + 1] = row
            end
        end
    end
    table.sort(rows, byDeadline)
    while #rows > M.maxBags do rows[#rows] = nil end
    return rows
end

-- Rows stored at sync time -> NUI payload at `now`: remaining recomputed from the local deadline, expired dropped.
-- Output rows are plain data (relay-safe): { id, label?, magnitude?, remaining?, dir?, dist? }.
function M.view(rows, now)
    local out = {}
    for _, r in ipairs(rows or {}) do
        local left
        if r.deadline then
            left = math.max(0, math.ceil(r.deadline - now))
            if left <= 0 then goto continue end
        end
        out[#out + 1] = { id = r.id, label = r.label, magnitude = r.magnitude, remaining = left, dir = r.dir, dist = r.dist }
        ::continue::
    end
    return out
end

if GetCurrentResourceName then
    FhUiHud = M
else
    return M
end
