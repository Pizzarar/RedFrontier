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

-- Read-only chain progress for @quests: exports.fh_hunting:chainState(citizenid, chain_id) -> nil | step | 'complete'.
if exports then exports('chainState', function(citizenid, chainId)
    return FhHuntingChain.readState({
        byId = FhHuntingLegendaries.byId,
        query = function(cid, id)
            return MySQL.query.await(
                'SELECT step, completed FROM fh_hunting_chains WHERE citizenid = ? AND chain_id = ? LIMIT 1', { cid, id })
        end,
        log = function(m) print('^3[fh_hunting] ' .. m .. '^7') end,
    }, citizenid, chainId)
end) end
