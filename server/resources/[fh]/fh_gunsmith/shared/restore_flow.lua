-- fh_gunsmith restore flow (plan crafting-01 C3; C5a restores from the OPEN world container). Pure and injectable:
-- no natives, no exports. Restore math lives in fh_crafting/shared/craft_rules.lua (FhCraftRules.restore); this only
-- orchestrates.

local M = {}

---Pure plan for one weapon item (slot table, info.condition / info.stars) and the gun_parts the player holds.
---@return table|nil plan { from, to, parts, cap, stars }
---@return string|nil reason 'no_weapon' | 'no_condition' | 'at_cap' | 'no_parts'
function M.plan(item, partsAvailable, rules)
    rules = rules or FhCraftRules
    if type(item) ~= 'table' then return nil, 'no_weapon' end
    local info = type(item.info) == 'table' and item.info or {}
    local to, used, reason = rules.restore(info.condition, info.stars, partsAvailable)
    if reason then return nil, reason end
    return { from = tonumber(info.condition), to = to, parts = used, cap = rules.restoreCap(info.stars), stars = info.stars }
end

M.STATION_REACH = 3.0 -- metres, container to station (same as fh_crafting stationMaxDist)
M.SNAP_ABOVE = 20.0   -- vertical tolerance matching FhConfig.Access.SnapToleranceAbove (workbench prop is ground-snapped)
M.SNAP_BELOW = 20.0   -- vertical tolerance matching FhConfig.Access.SnapToleranceBelow
M.WORKBENCH = 'workbench' -- H3 type crafting maps 'gunsmith' to (FhCraftingConfig.stationTypeMap)

---Is any of the player's own stations a gunsmith bench within reach of `coords`? `stations` is
---exports.fh_crafting:getStations(citizenid) (H3 shape { station_type, coords = {x,y,z} }; dev stations carry
---dev = true and the crafting type 'gunsmith').
---@return boolean ok, string|nil reason 'no_station'
local function xyz(v)
    if v == nil then return nil end
    local ok, x, y, z = pcall(function() return v.x, v.y, v.z end)
    local function fin(n) return type(n) == 'number' and n == n and n ~= math.huge and n ~= -math.huge end
    if not ok or not fin(x) or not fin(y) or not fin(z) then return nil end
    return x, y, z
end

function M.stationInReach(stations, coords, maxDist)
    maxDist = maxDist or M.STATION_REACH
    local px, py, pz = xyz(coords) -- vector3 or { x, y, z }
    if not px then return false, 'no_station' end
    for _, s in ipairs(type(stations) == 'table' and stations or {}) do
        local bench = type(s) == 'table' and (s.station_type == M.WORKBENCH or (s.dev == true and s.station_type == 'gunsmith'))
        local cx, cy, cz
        if bench then cx, cy, cz = xyz(s.coords) end
        if cx then
            local dx, dy = cx - px, cy - py
            local dzTarget = pz - cz
            if dx * dx + dy * dy <= maxDist * maxDist and dzTarget <= M.SNAP_ABOVE and dzTarget >= -M.SNAP_BELOW then
                return true
            end
        end
    end
    return false, 'no_station'
end

---deps (all injectable):
---  open(src) -> ref, view | nil, reason         the container the player has open (fh_core openRef + view)
---  containers                                    fh_core FhContainers (accepts, canReach)
---  playerCoords(src) -> coords | nil             server-side ped coords, for the reach check
---  nearStation(src, coords) -> ok, reason        gunsmith station reach for the container's coords (own plot)
---  count(src, item) -> n                         fh_crafting invCount (gun_parts held)
---  setInfo(ref, slot, info, expectName) -> ok, reason   fh_core setItemInfo write (expectName = the weapon item name)
---  take(src, item, amount) -> ok, reason         part removal (fh_crafting invTake; B7-backed)
---  rules                                         optional, defaults to FhCraftRules
---Order: open container -> bulky type -> player reach -> station reach -> slot -> plan -> write condition -> consume
---parts. If the consume fails the condition write is rolled back, so parts are never consumed without a successful
---write and vice versa.
---@return boolean ok
---@return string|table reason_or_result
---@return table|nil meta { rollbackFailed, slot, wanted, reason } when the rollback write also failed
function M.run(deps, src, slot)
    local ref, view, why = deps.open(src)
    if not ref then return false, why or 'fh_nothing_open' end

    -- The open container's type must accept bulky (a rifle is bulky). Read from fh_core FhContainers, not a list.
    local okBulk, bulkWhy = deps.containers.accepts(ref.type, 'bulky')
    if not okBulk then return false, bulkWhy or 'fh_size_class' end

    -- openRef stays set after the player walks away (fh_inventory FhOpenRef), so reach is re-checked server-side.
    local okReach, reachWhy = deps.containers.canReach(ref.type, view.coords, deps.playerCoords(src))
    if not okReach then return false, reachWhy or 'fh_out_of_reach' end

    local okNear, nearWhy = deps.nearStation(src, view.coords)
    if not okNear then return false, nearWhy or 'no_station' end

    slot = tonumber(slot)
    if not slot or slot ~= slot or slot == math.huge or slot == -math.huge or slot ~= math.floor(slot) or slot < 1 then
        return false, 'bad_slot'
    end

    local item = view.items and view.items[slot]
    local plan, reason = M.plan(item, deps.count(src, 'gun_parts'), deps.rules)
    if not plan then return false, reason end

    local newInfo = {}
    for k, v in pairs(item.info) do newInfo[k] = v end
    newInfo.condition = plan.to
    local okSet, setWhy = deps.setInfo(ref, slot, newInfo, item.name)
    if not okSet then return false, setWhy or 'write_failed' end

    local okTake, takeWhy = deps.take(src, 'gun_parts', plan.parts)
    if not okTake then
        local okRb, rbWhy = deps.setInfo(ref, slot, item.info, item.name) -- rollback
        local meta = (not okRb) and { rollbackFailed = true, slot = slot, wanted = item.info.condition, reason = rbWhy } or nil
        if takeWhy == 'not_implemented' or takeWhy == 'no_remove' then return false, 'no_remove', meta end
        return false, takeWhy or 'take_failed', meta
    end
    return true, plan
end

if GetCurrentResourceName then FhGunsmithFlow = M else return M end
