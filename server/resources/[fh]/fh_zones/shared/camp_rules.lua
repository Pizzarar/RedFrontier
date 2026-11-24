-- fh_zones pure camp rules: state machine, activation check, ped-death roll-up, loot roll. No natives (busted/lupa can load it).
-- Spec: spec/camp_rules_spec.lua
local M = {}

M.STATES = { 'idle', 'active', 'cleared', 'respawn_wait' }

-- state -> event -> next state. 'cleared' is the instant loot is rolled; the server moves on to respawn_wait at once.
M.TRANSITIONS = {
    idle         = { activate = 'active' },
    active       = { clear = 'cleared', abort = 'idle' }, -- abort: every ped failed to spawn
    cleared      = { wait = 'respawn_wait' },
    respawn_wait = { respawn = 'idle' },
}

---@return string|nil next, string|nil err
function M.transition(state, event)
    local row = M.TRANSITIONS[state]
    if not row then return nil, 'fh_camp_bad_state' end
    local nxt = row[event]
    if not nxt then return nil, 'fh_camp_bad_transition' end
    return nxt
end

local function xyz(v)
    if type(v) ~= 'table' and type(v) ~= 'userdata' then return nil end
    local ok, x, y, z = pcall(function() return v.x, v.y, v.z end)
    if not ok or type(x) ~= 'number' or type(y) ~= 'number' or type(z) ~= 'number' then return nil end
    if x ~= x or y ~= y or z ~= z then return nil end
    return x, y, z
end

---3D distance check, edge inclusive. Bad coords are never inside.
function M.inRadius(center, radius, pos)
    local cx, cy, cz = xyz(center)
    local px, py, pz = xyz(pos)
    if not cx or not px or type(radius) ~= 'number' then return false end
    local dx, dy, dz = cx - px, cy - py, cz - pz
    return dx * dx + dy * dy + dz * dz <= radius * radius
end

---Does any player position wake the camp? Only an idle camp activates.
function M.shouldActivate(state, camp, positions)
    if state ~= 'idle' then return false end
    for _, pos in ipairs(positions or {}) do
        if M.inRadius(camp.center, camp.activationRadius, pos) then return true end
    end
    return false
end

---Should the camp wake right now? The activation check plus the A-life law-held skip: a law-held camp never
---activates even with a player inside. lawHeld is the boolean from fh_alife:isLawHeld(campId); nil (fh_alife absent
---or the export failed) is treated as not held, so the camp behaves exactly as before this feature existed.
function M.shouldWake(state, camp, positions, lawHeld)
    if lawHeld == true then return false end
    return M.shouldActivate(state, camp, positions)
end

---Citizenids of the players inside the radius. entries = array of { citizenid = string|nil, pos = vec3 }; entries with no
---citizenid or bad coords are skipped. Always returns a table (empty when nobody is in range), never nil.
function M.participants(center, radius, entries)
    local out = {}
    for _, e in ipairs(entries or {}) do
        if e.citizenid and M.inRadius(center, radius, e.pos) then out[#out + 1] = e.citizenid end
    end
    return out
end

---Like participants, but entries come from gather() (the impure native/rsg-core lookup). If gather or the filter throws,
---returns {} plus the error so a lookup failure can never break the clear -> wait step.
---@return table participants, string|nil err
function M.safeParticipants(center, radius, gather)
    local ok, res = pcall(function() return M.participants(center, radius, gather()) end)
    if ok and type(res) == 'table' then return res end
    return {}, tostring(res)
end

---peds = array of { dead = bool, failed = bool }. Cleared when none is still alive and at least one died
---(a camp whose spawns all failed is not "cleared": nobody killed anything).
function M.allDead(peds)
    if type(peds) ~= 'table' or #peds == 0 then return false end
    local anyDead = false
    for _, p in ipairs(peds) do
        if p.dead then anyDead = true
        elseif not p.failed then return false end
    end
    return anyDead
end

---True when every ped's spawn failed (none ever came up): the camp can never be cleared, so it must abort.
function M.allFailed(peds)
    if type(peds) ~= 'table' or #peds == 0 then return false end
    for _, p in ipairs(peds) do
        if not p.failed then return false end
    end
    return true
end

---After an abort the camp waits for retryAt (ms game time) before a player can wake it again. nil = no cooldown.
function M.cooldownOver(now, retryAt)
    return retryAt == nil or (type(now) == 'number' and now >= retryAt)
end

---Is a reporter close enough to a camp to be believed about its peds? (Client death reports are only hints.)
function M.canReport(camp, reporterPos, margin)
    return M.inRadius(camp.center, camp.activationRadius + (margin or 25.0), reporterPos)
end

function M.respawnDue(now, respawnAt)
    return type(now) == 'number' and type(respawnAt) == 'number' and now >= respawnAt
end

---Pick the loot table for a camp's current owner: lootByFaction[owner] when the owner has an entry, else the camp's
---own table (camp.loot.table). owner is a faction id (e.g. 'outlaws') or nil (fh_alife absent / export failed) -> fall back.
function M.pickLootTable(lootByFaction, owner, campTable)
    if type(lootByFaction) == 'table' and type(owner) == 'string' then
        local t = lootByFaction[owner]
        if type(t) == 'table' then return t end
    end
    return campTable
end

---Roll a loot table. rng(a, b) -> integer in [a, b] (default math.random); chance is compared on a 0..1000000 scale.
---entry: { name, chance (0..1), amount? (integer, or { min, max } rolled inclusive), condition = { min, max }? }. Returns array of { name, amount, info? }.
function M.rollLoot(tbl, rng)
    rng = rng or math.random
    local out = {}
    for _, e in ipairs(tbl or {}) do
        if type(e.name) == 'string' and type(e.chance) == 'number' then
            local roll = rng(0, 999999)
            if roll < e.chance * 1000000 then
                local item = { name = e.name, amount = math.tointeger(e.amount) or 1 }
                if type(e.amount) == 'table' then
                    local lo, hi = math.tointeger(e.amount[1]), math.tointeger(e.amount[2])
                    if lo and hi and lo >= 1 and hi >= lo then item.amount = rng(lo, hi) end
                end
                if type(e.condition) == 'table' then
                    local lo, hi = e.condition[1], e.condition[2]
                    if type(lo) == 'number' and type(hi) == 'number' and hi >= lo then
                        item.info = { condition = math.max(0, math.min(100, rng(math.floor(lo), math.floor(hi)))) }
                    end
                end
                out[#out + 1] = item
            end
        end
    end
    return out
end

---Ped tag convention: '<camp id>:outlaw:<index>'.
function M.tagFor(campId, idx) return ('%s:outlaw:%d'):format(campId, idx) end
---@return string|nil campId, integer|nil idx
function M.parseTag(tag)
    if type(tag) ~= 'string' then return nil end
    local id, idx = tag:match('^(.+):outlaw:(%d+)$')
    if not id then return nil end
    return id, tonumber(idx)
end

function M.stashId(campId) return 'fh:camp:' .. tostring(campId) end

if GetCurrentResourceName then
    FhCampRules = M
else
    return M
end
