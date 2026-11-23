-- Pure homestead build rules (H1): slot tiers, prerequisites, costs, comfort. No natives, specced under busted/lupa.
-- currentTiers = { [slotId] = tier }, missing = 0. No money/item debit here (H2).
local M = {}

local function slotOf(plot, slotId)
    if type(plot) ~= 'table' or type(plot.slots) ~= 'table' or type(slotId) ~= 'string' then return nil end
    return plot.slots[slotId]
end

local function tierOf(currentTiers, slotId)
    local t = type(currentTiers) == 'table' and currentTiers[slotId] or 0
    return type(t) == 'number' and t or 0
end

local function tierDef(slot, tier)
    return type(slot) == 'table' and type(slot.tiers) == 'table' and slot.tiers[tier] or nil
end

---Next tier to build for a slot, or nil when maxed / unknown.
function M.nextTier(slot, currentTier)
    if type(slot) ~= 'table' then return nil end
    local nxt = (currentTier or 0) + 1
    if nxt > (slot.maxTier or 0) then return nil end
    return nxt
end

---@return table|nil cost { money=, items={} } for building `tier` of the slot.
function M.costFor(slot, tier)
    local t = tierDef(slot, tier)
    return t and t.cost or nil
end

---Comfort points one tier adds (0 for unknown).
function M.comfortFor(slot, tier)
    local t = tierDef(slot, tier)
    return t and t.comfort or 0
end

---Sum of comfort across every built slot tier (a slot at tier 2 counts tiers 1 and 2).
function M.totalComfort(plot, currentTiers)
    local sum = 0
    for id, slot in pairs(type(plot) == 'table' and plot.slots or {}) do
        for tier = 1, tierOf(currentTiers, id) do sum = sum + M.comfortFor(slot, tier) end
    end
    return sum
end

---What a built tier unlocks (table, possibly empty), or nil for an unknown slot/tier.
function M.unlocks(slot, tier)
    local t = tierDef(slot, tier)
    return t and (t.unlocks or {}) or nil
end

---Aggregate unlocks of everything built: chest slot ids, safe radius bonus, station types, trophy comfort flag.
function M.unlockedState(plot, currentTiers)
    local out = { chests = {}, safeRadiusBonus = 0, stations = {}, trophyComfort = false }
    local ids = {}
    for id in pairs(type(plot) == 'table' and plot.slots or {}) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local slot = plot.slots[id]
        for tier = 1, tierOf(currentTiers, id) do
            local u = M.unlocks(slot, tier) or {}
            for _, c in ipairs(u.chests or {}) do out.chests[#out.chests + 1] = c end
            out.safeRadiusBonus = out.safeRadiusBonus + (u.safeRadiusBonus or 0)
            if u.stationType then out.stations[#out.stations + 1] = u.stationType end
            if u.trophyComfort then out.trophyComfort = true end
        end
    end
    return out
end

---Owner-only; next tier only (targetTier, when given, must equal it); prerequisite slots must be built.
---@return boolean ok, string|nil reason
function M.canBuild(plot, slotId, currentTiers, citizenid, ownerCitizenid, targetTier)
    if type(citizenid) ~= 'string' or citizenid == '' then return false, 'fh_no_character' end
    if type(plot) ~= 'table' then return false, 'fh_no_plot' end
    if type(ownerCitizenid) ~= 'string' or ownerCitizenid == '' then return false, 'fh_plot_free' end
    if citizenid ~= ownerCitizenid then return false, 'fh_not_owner' end
    local slot = slotOf(plot, slotId)
    if not slot then return false, 'fh_unknown_slot' end
    local nxt = M.nextTier(slot, tierOf(currentTiers, slotId))
    if not nxt then return false, 'fh_max_tier' end
    if targetTier ~= nil and targetTier ~= nxt then return false, 'fh_tier_order' end
    for reqId, minTier in pairs(slot.requires or {}) do
        if tierOf(currentTiers, reqId) < minTier then return false, 'fh_prereq_missing' end
    end
    return true
end

---Slot prop for placement: fallback (B6a model + offset) unless verifiedProps is true AND the slot has a verified prop.
function M.propFor(slot, verifiedProps)
    if type(slot) ~= 'table' then return nil end
    if verifiedProps and slot.propVerified then return slot.propVerified end
    return slot.prop
end

-- ---- H2 helpers (pure) ----

local function wholeCount(n) return type(n) == 'number' and math.tointeger(n) or nil end

---Normalise a tier cost for the build flow: { money = int >= 0, items = { {item=, amount=}, ... } } with items sorted
---by name (deterministic take/refund order) and every amount a whole number >= 1. nil + reason on a bad cost.
function M.costList(cost)
    if type(cost) ~= 'table' then return nil, 'fh_bad_cost' end
    local money = cost.money == nil and 0 or wholeCount(cost.money)
    if not money or money < 0 then return nil, 'fh_bad_cost' end
    local items = {}
    for name, n in pairs(type(cost.items) == 'table' and cost.items or {}) do
        local amount = wholeCount(n)
        if type(name) ~= 'string' or name == '' or not amount or amount < 1 then return nil, 'fh_bad_cost' end
        items[#items + 1] = { item = name, amount = amount }
    end
    table.sort(items, function(a, b) return a.item < b.item end)
    return { money = money, items = items }
end

---Safe-zone radius of a claimed plot: base (cfg.baseSafeRadius, else the plot radius) plus every built
---safeRadiusBonus (the fence). Unknown/garbage tiers count as nothing built.
function M.safeRadius(plot, currentTiers, baseRadius)
    if type(plot) ~= 'table' then return 0 end
    local base = tonumber(baseRadius) or tonumber(plot.radius) or 0
    return base + M.unlockedState(plot, type(currentTiers) == 'table' and currentTiers or {}).safeRadiusBonus
end

---Chest number of a chest-kind slot ('chest_2' -> 2), or nil. Chest 1 is the claim chest, never a slot.
function M.chestNumber(slotId, slot)
    if type(slot) ~= 'table' or slot.kind ~= 'chest' or type(slotId) ~= 'string' then return nil end
    local n = math.tointeger(tonumber(slotId:match('^chest_(%d+)$')) or 0)
    return (n and n >= 2) and n or nil
end

---World position of a slot prop: plot center + prop offset ({x,y,z} table), heading from the prop (default 0).
function M.slotPlacement(plot, slot, verifiedProps)
    local prop = M.propFor(slot, verifiedProps)
    if type(plot) ~= 'table' or type(prop) ~= 'table' or type(prop.model) ~= 'string' then return nil end
    local okc, cx, cy, cz = pcall(function() return plot.center.x, plot.center.y, plot.center.z end)
    local o = type(prop.offset) == 'table' and prop.offset or {}
    local ox, oy, oz = tonumber(o.x) or 0, tonumber(o.y) or 0, tonumber(o.z) or 0
    if not okc or type(cx) ~= 'number' or type(cy) ~= 'number' or type(cz) ~= 'number' then return nil end
    return { model = prop.model, coords = { x = cx + ox, y = cy + oy, z = cz + oz }, heading = tonumber(prop.heading) or 0.0 }
end

---Props for every built slot of a plot, sorted by slot id: { slot_id, kind, tier, model, coords, heading, chest? }.
---What the client draws (client-local, non-networked). Slots without a usable prop are skipped.
function M.slotProps(plot, currentTiers, verifiedProps)
    local out = {}
    if type(plot) ~= 'table' or type(plot.slots) ~= 'table' then return out end
    local ids = {}
    for id in pairs(plot.slots) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local slot, tier = plot.slots[id], tierOf(currentTiers, id)
        local place = tier >= 1 and M.slotPlacement(plot, slot, verifiedProps) or nil
        if place then
            out[#out + 1] = { slot_id = id, kind = slot.kind, tier = tier, model = place.model, coords = place.coords,
                heading = place.heading, chest = M.chestNumber(id, slot) }
        end
    end
    return out
end

---Config sanity: every slot has a cost and comfort for each tier 1..maxTier. Returns a list of problems (empty = valid).
function M.validatePlot(plot)
    local bad = {}
    if type(plot) ~= 'table' or type(plot.slots) ~= 'table' then return { 'no slots' } end
    for id, slot in pairs(plot.slots) do
        if type(slot.maxTier) ~= 'number' or slot.maxTier < 1 then bad[#bad + 1] = id .. ': maxTier' end
        for tier = 1, type(slot.maxTier) == 'number' and slot.maxTier or 0 do
            local t = tierDef(slot, tier)
            if not t then bad[#bad + 1] = ('%s: tier %d missing'):format(id, tier)
            else
                if type(t.cost) ~= 'table' or type(t.cost.money) ~= 'number' or t.cost.money < 0 then bad[#bad + 1] = ('%s: tier %d cost'):format(id, tier) end
                if type(t.comfort) ~= 'number' then bad[#bad + 1] = ('%s: tier %d comfort'):format(id, tier) end
            end
        end
        if slot.kind == 'station' and not slot.stationType then bad[#bad + 1] = id .. ': stationType' end
        for reqId in pairs(slot.requires or {}) do
            if not plot.slots[reqId] then bad[#bad + 1] = id .. ': requires unknown ' .. tostring(reqId) end
        end
    end
    return bad
end

if GetCurrentResourceName then
    FhBuildRules = M
else
    return M
end
