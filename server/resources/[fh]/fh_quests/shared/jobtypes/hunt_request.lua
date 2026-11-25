-- hunt_request offers (Q3): deliver an N-star pelt of an animal (sold at the fh_hunting buyer). Pure Lua.
-- Data: data/regions/<region_id>.lua `hunt = { { animal, stars, money }, ... }`. Verdicts: shared/jobtypes.lua.
local JT = FhQuestsJobTypes -- the global (in-game: set by shared/jobtypes.lua; specs: set by its spec loader)

JT.registerBuilder('hunt_request', function(region_id, d)
    local out = {}
    for _, h in ipairs(d.hunt or {}) do
        local animal, stars, money = h[1], h[2], h[3]
        out[#out + 1] = {
            key = ('%s_%dstar'):format(animal, stars),
            title = ('Pelt wanted: %d-star %s'):format(stars, animal),
            text = ('Sell a %d-star or better %s pelt.'):format(stars, animal),
            on = 'fh:hunting:pelt_sold',
            -- pelt_sold always carries `animal` (fh_hunting sell.lua, Q0b): both quality and animal must match.
            where = { quality = { min = stars }, animal = { eq = animal } },
            rewards = JT.rewards(region_id, money, 1), region_id = region_id, animal = animal, stars = stars,
            min_tier = JT.minTier(h.min_tier ~= nil and h.min_tier or h[4]),
        }
    end
    return out
end)
