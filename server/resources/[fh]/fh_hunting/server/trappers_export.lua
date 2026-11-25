-- Read-only trapper export for cross-resource consumers (e.g. fh_ui map blips and /where).
-- Kept in its own file to avoid merge conflicts with server/main.lua.
-- Returns a fresh array of { region_id, label, coords = { x, y, z } } for every enabled region
-- (data/legendaries/<region>.lua `trapper`, with heartlands falling back to FhHuntingConfig.Trapper).
local function getTrappers()
    local out = {}
    local all = FhHuntingSell.trappers(FhHuntingConfig, FhHuntingLegendaries)
    for _, t in ipairs(all) do
        if FhRegions.isEnabled(t.region_id) then
            local c = t.coords
            if type(c) == 'table' then
                out[#out + 1] = {
                    region_id = t.region_id,
                    label = t.label,
                    coords = { x = c.x, y = c.y, z = c.z },
                }
            end
        end
    end
    return out
end

if exports then
    exports('getTrappers', getTrappers)
else
    return getTrappers
end
