-- Static region / faction / territory registry (spec 4.4). Pure Lua, no natives.
-- Every other lane references these IDs and never defines its own.
--
-- NOTE: all coordinates are APPROXIMATE (Heartlands / Valentine area) and must be
-- verified in game (stand at the spot, read coords, adjust center/radius).
local regions = {}

regions.TIERS = { 'T1', 'T2', 'T3' }

regions.factions = {
    outlaws = { id = 'outlaws', label = 'Heartland Outlaws' },
    lawmen  = { id = 'lawmen',  label = 'Valentine Law' },
}

regions.regions = {
    heartlands = {
        id = 'heartlands',
        label = 'Heartlands (Valentine)',
        kind = 'region',
        -- Starter homestead plot, approximate.
        homestead = { x = -300.0, y = 790.0, z = 118.0 },
        factions = { 'lawmen', 'outlaws' },
        territories = { 'heartlands_t1_camp' },
    },
}

regions.territories = {
    heartlands_t1_camp = {
        id = 'heartlands_t1_camp',
        label = 'Heartlands Outlaw Camp',
        region = 'heartlands',
        faction = 'outlaws',
        tier = 'T1',
        center = { x = -145.0, y = 845.0, z = 117.0 }, -- approximate
        radius = 60.0,
    },
}

function regions.getRegion(id) return regions.regions[id] end
function regions.getFaction(id) return regions.factions[id] end
function regions.getTerritory(id) return regions.territories[id] end

---@return boolean
function regions.isKnownRegion(id)
    return type(id) == 'string' and regions.regions[id] ~= nil
end

---Return the territory containing (x, y), or nil. 2D distance; the nearest center wins on overlap.
function regions.territoryAt(x, y)
    if type(x) ~= 'number' or type(y) ~= 'number' then return nil end
    local best, bestD2
    for _, t in pairs(regions.territories) do
        local dx, dy = x - t.center.x, y - t.center.y
        local d2 = dx * dx + dy * dy
        if d2 <= t.radius * t.radius and (not bestD2 or d2 < bestD2) then
            best, bestD2 = t, d2
        end
    end
    return best
end

-- FXServer loads shared scripts as plain chunks; expose a global there, module under busted.
if _G.GetCurrentResourceName then _G.FhRegions = regions end
return regions
