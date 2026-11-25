-- hunt_request offers (Q3): deliver an N-star pelt of an animal (sold at the fh_hunting buyer). Pure Lua.
-- Data: data/regions/<region_id>.lua `hunt = { { animal, stars, money }, ... }`. Verdicts: shared/jobtypes.lua.
-- Offer key (idea-902): 'hunt_<region_id>_<animal>_<N>star', region-scoped like camp_<camp id> so two regions
-- can offer the same animal/stars without sharing a quest id. Rows saved under the old unscoped key
-- '<animal>_<N>star' are re-keyed on load (shared/jobs.lua migrateLegacy, server/main.lua Q.load).
local JT = FhQuestsJobTypes -- the global (in-game: set by shared/jobtypes.lua; specs: set by its spec loader)

---The region-scoped offer key of a hunt request.
function JT.huntKey(region_id, animal, stars) return ('hunt_%s_%s_%dstar'):format(region_id, animal, stars) end

---Pre-idea-902 key -> region index from the current data: { [legacy key] = region_id | false } (false = the
---legacy key is built by more than one region, so it cannot name a region). Fallback only: a row's own
---progress.job.region_id snapshot is the primary source (jobs.migrateLegacy).
function JT.legacyHuntRegions()
    local out = {}
    for region_id, d in pairs(JT.DATA) do
        for _, h in ipairs(d.hunt or {}) do
            local k = ('%s_%dstar'):format(h[1], h[2])
            if out[k] == nil then out[k] = region_id elseif out[k] ~= region_id then out[k] = false end
        end
    end
    return out
end

JT.registerBuilder('hunt_request', function(region_id, d)
    local out = {}
    for _, h in ipairs(d.hunt or {}) do
        local animal, stars, money = h[1], h[2], h[3]
        out[#out + 1] = {
            key = JT.huntKey(region_id, animal, stars),
            title = ('Pelt wanted: %d-star %s'):format(stars, animal),
            text = ('Sell a %d-star or better %s pelt.'):format(stars, animal),
            on = 'fh:hunting:pelt_sold',
            -- pelt_sold always carries `animal` (fh_hunting sell.lua, Q0b) and the region of the trapper it was sold
            -- at (hunting-03 C1, sell.lua:218-221): quality, animal and region must all match (idea-902b), so a sale
            -- completes only the job of the region it was made in. A payload without region_id never credits.
            -- Jobs accepted before idea-902b keep their snapshotted (unscoped) where until accepted again.
            where = { quality = { min = stars }, animal = { eq = animal }, region_id = { eq = region_id } },
            rewards = JT.rewards(region_id, money, 1), region_id = region_id, animal = animal, stars = stars,
            min_tier = JT.minTier(h.min_tier ~= nil and h.min_tier or h[4]),
        }
    end
    return out
end)
