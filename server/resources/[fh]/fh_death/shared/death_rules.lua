-- Pure soft-death rules (spec L4, L16 "soft consequences"): no natives, specced under busted
-- (spec/death_rules_spec.lua). The server owns all state; this file only decides.
--
-- Life state per character: state.byCid[citizenid] = { dead = bool, life = n, diedAt = seconds|nil }.
-- One death = one drop: only an alive -> dead transition returns ok, and the transition is made synchronously, so a
-- repeated / duplicated / concurrent death event for the same life is refused (fh_already_dead). The character is
-- alive again only once the server reads health > 0 and at least minDeadSeconds have passed since the death.
local M = {}

local function finite(n) return type(n) == 'number' and n == n and n > -math.huge and n < math.huge end

function M.newState() return { byCid = {} } end

local function entry(state, cid)
    local e = state.byCid[cid]
    if not e then
        e = { dead = false, life = 1 }
        state.byCid[cid] = e
    end
    return e
end

---Death report for `cid`. health = the SERVER-read ped health (nil when unreadable).
---@return boolean ok, string|number reasonOrLife (life number of the life that just ended)
function M.onDeath(state, cid, health, now)
    if type(cid) ~= 'string' or cid == '' then return false, 'fh_no_character' end
    if not finite(health) or health > 0 then return false, 'fh_not_dead' end
    local e = entry(state, cid)
    if e.dead then return false, 'fh_already_dead' end
    e.dead, e.diedAt = true, finite(now) and now or 0
    return true, e.life
end

---Alive check for a character marked dead. Returns true when it flipped back to alive (a new life starts).
function M.onAlive(state, cid, health, now, minDeadSeconds)
    local e = type(cid) == 'string' and state.byCid[cid]
    if not e or not e.dead then return false end
    if not finite(health) or health <= 0 then return false end
    if finite(now) and finite(minDeadSeconds) and now - (e.diedAt or 0) < minDeadSeconds then return false end
    e.dead, e.diedAt, e.life = false, nil, e.life + 1
    return true
end

function M.isDead(state, cid)
    local e = type(cid) == 'string' and state.byCid[cid]
    return e and e.dead or false
end

---Forget a character (player dropped / unloaded).
function M.forget(state, cid) if type(cid) == 'string' then state.byCid[cid] = nil end end

---Which containers empty into the bag. `equipped` never moves. saddlebagId = the stash id of the saddlebag the
---character currently has (nil when no horse system / no horse: nothing to move).
---@return table refs array of fh_core container refs, in move order
function M.sources(src, saddlebagId)
    local out = {}
    if type(src) == 'number' then out[#out + 1] = { type = 'backpack', id = src } end
    if type(saddlebagId) == 'string' and saddlebagId ~= '' then out[#out + 1] = { type = 'saddlebag', id = saddlebagId } end
    return out
end

---Occupied slots and total grams over the snapshots (slot -> item maps). Unknown weights count as 0.
function M.contentsOf(snapshots)
    local slots, grams = 0, 0
    for _, items in ipairs(snapshots or {}) do
        for _, it in pairs(type(items) == 'table' and items or {}) do
            if type(it) == 'table' and (tonumber(it.amount) or 0) > 0 then
                slots = slots + 1
                grams = grams + (tonumber(it.weight) or 0) * (tonumber(it.amount) or 0)
            end
        end
    end
    return slots, grams
end

---No bag when every source is empty.
function M.isEmpty(snapshots) return (M.contentsOf(snapshots)) == 0 end

---Bag shape big enough for everything: at least the drop_bag defaults, grown to the contents.
function M.bagSize(defaults, snapshots)
    local slots, grams = M.contentsOf(snapshots)
    defaults = defaults or {}
    return {
        slots = math.max(tonumber(defaults.slots) or 1, slots),
        maxWeight = math.max(tonumber(defaults.maxWeight) or 1, math.ceil(grams)),
    }
end

---Stash id of a death bag (sent to every client, so no citizenid in it). now = os.time(), seq = per-boot counter:
---unique across restarts unless the clock goes back AND the counter repeats; the fh_death_drops primary key is the
---backstop (a clashing insert aborts the drop and the items stay on the player).
function M.bagId(now, seq)
    return ('fh:dropbag:%d-%d'):format(math.floor(tonumber(now) or 0), math.floor(tonumber(seq) or 0))
end

function M.expiresAt(now, minutes) return math.floor((tonumber(now) or 0) + (tonumber(minutes) or 0) * 60) end

function M.isExpired(bag, now)
    return type(bag) == 'table' and finite(bag.expiresAt) and finite(now) and now >= bag.expiresAt or false
end

---A bag players may see (prop, prompt) and open: not mid-drop / mid-delete (busy) and not past its expiry.
---Expired bags are only ever deleted by the sweep (review rn-eb74b5c695bb: no open window after expiry).
function M.isLive(bag, now)
    return type(bag) == 'table' and not bag.busy and not M.isExpired(bag, now)
end

local function dist(a, b)
    local ok, ax, ay, az, bx, by, bz = pcall(function() return a.x, a.y, a.z, b.x, b.y, b.z end)
    if not ok then return nil end
    for _, v in ipairs({ ax, ay, az, bx, by, bz }) do if not finite(v) then return nil end end
    local dx, dy, dz = ax - bx, ay - by, az - bz
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

---Only the owner, within reach, of a live bag. fh_core.open re-checks reach from the server ped, and fh_inventory
---once more. now = os.time() (nil skips the expiry check).
---@return boolean ok, string|nil reason
function M.canOpen(bag, citizenid, playerCoords, reach, now)
    if type(bag) ~= 'table' then return false, 'fh_no_bag' end
    if bag.busy then return false, 'fh_bag_busy' end
    if now ~= nil and M.isExpired(bag, now) then return false, 'fh_bag_expired' end
    if type(citizenid) ~= 'string' or citizenid == '' then return false, 'fh_no_character' end
    if bag.owner ~= citizenid then return false, 'fh_not_owner' end
    local d = dist(bag.coords, playerCoords)
    if not d then return false, 'fh_no_player_coords' end
    if d > (tonumber(reach) or 3.5) then return false, 'fh_out_of_reach' end
    return true
end

if GetCurrentResourceName then
    FhDeathRules = M
else
    return M
end
