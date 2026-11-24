-- camp_clear offers (Q3): wipe out an fh_zones outlaw camp. Pure Lua.
-- Data: data/regions/<region_id>.lua `camps = { { id, label, money, rep }, ... }` (id = fh_zones/config.lua camp id).
local JT = ... or FhQuestsJobTypes -- chunk argument outside FXServer (specs), the global in-game

JT.registerBuilder('camp_clear', function(region_id, d)
    local out = {}
    for _, c in ipairs(d.camps or {}) do
        out[#out + 1] = {
            key = 'camp_' .. c.id, title = 'Clear out: ' .. c.label,
            text = 'Wipe out the outlaws at the ' .. c.label .. '.',
            on = 'fh:zones:camp_cleared', where = { camp_id = c.id },
            rewards = JT.rewards(region_id, c.money, c.rep), region_id = region_id, camp_id = c.id,
        }
    end
    return out
end)
