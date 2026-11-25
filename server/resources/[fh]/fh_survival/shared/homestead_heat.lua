-- Owned homestead campfire heat (plan survival-02, F2). Pure Lua: no FiveM/RedM globals.
-- Decides which heat sources a player's own homestead campfire stations turn into, so the warm tick
-- (server/actions.lua) needs no change. `owned` is the set of heat-source ids this module's server glue has
-- already registered for one citizenid (ids `hs:<plot_id>:<slot_id>`); `stations` is the raw result of
-- exports.fh_homestead:getStations(citizenid) (each { plot_id, slot_id, station_type, coords }).
-- The seeded Campfires in config.Campfires are NOT part of `owned` and never flow through here: this module
-- only adds/removes `hs:*` ids it has itself registered, so a stopped homestead clears ours and leaves the
-- seeded fires untouched.
local H = {}

H.CAMPFIRE = 'campfire'
H.ID_PREFIX = 'hs:'

local function isNum(v) return type(v) == 'number' and v == v and v ~= math.huge and v ~= -math.huge end

---Heat-source id for a station: 'hs:<plot_id>:<slot_id>'. nil when the ids are missing.
function H.sourceId(station)
    if type(station) ~= 'table' or station.plot_id == nil or station.slot_id == nil then return nil end
    return H.ID_PREFIX .. tostring(station.plot_id) .. ':' .. tostring(station.slot_id)
end

---Only campfire stations with usable coords. Malformed entries are skipped.
function H.campfires(stations)
    local out = {}
    for _, s in ipairs(type(stations) == 'table' and stations or {}) do
        if type(s) == 'table' and s.station_type == H.CAMPFIRE then
            local c = s.coords
            if type(c) == 'table' and isNum(c.x) and isNum(c.y) then out[#out + 1] = s end
        end
    end
    return out
end

---Reconcile the heat sources one citizenid should own against their current station list.
---@param started boolean GetResourceState('fh_homestead') == 'started'
---@param owned table|nil map of source id -> true currently registered for this citizenid
---@param stations table[] getStations(citizenid) result
---@param radius number? heat radius for owned fires (passed through; nil = config HeatRadius)
---@return table[] adds { id, coords, radius }
---@return string[] removes source ids to drop
function H.reconcile(started, owned, stations, radius)
    owned = type(owned) == 'table' and owned or {}
    local adds, removes, wanted = {}, {}, {}
    if started then
        for _, s in ipairs(H.campfires(stations)) do
            local id = H.sourceId(s)
            if id then
                if not (owned[id] or wanted[id]) then
                    adds[#adds + 1] = {
                        id = id,
                        coords = { x = s.coords.x, y = s.coords.y, z = s.coords.z },
                        radius = radius,
                    }
                end
                wanted[id] = true
            end
        end
    end
    for id in pairs(owned) do
        if not wanted[id] then removes[#removes + 1] = id end
    end
    return adds, removes
end

if _G.GetCurrentResourceName then _G.FhSurvivalHomesteadHeat = H end
return H
