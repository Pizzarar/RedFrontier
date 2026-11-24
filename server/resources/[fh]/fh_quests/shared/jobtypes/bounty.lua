-- bounty offers (Q3): bring down a wanted NPC (spawned on accept by server/jobtypes.lua). Pure Lua.
-- Data: data/regions/<region_id>.lua `bounties = { { key, name, model, coords, heading, money, rep }, ... }`.
local JT = (type((...)) == 'table' and (...)) or FhQuestsJobTypes -- chunk arg in specs (table), the global in FXServer (where ... is a number)

JT.registerBuilder('bounty', function(region_id, d)
    local out = {}
    for _, b in ipairs(d.bounties or {}) do
        out[#out + 1] = {
            key = 'bounty_' .. b.key, title = 'Wanted: ' .. b.name,
            text = b.name .. ' is holed up near here. Bring them down.',
            on = JT.BOUNTY_EVENT, rewards = JT.rewards(region_id, b.money, b.rep), region_id = region_id,
            -- the rest rides along to accept only (spawn setup)
            name = b.name, model = b.model, coords = b.coords, heading = b.heading,
        }
    end
    return out
end)
