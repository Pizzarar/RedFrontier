-- survey offers (quests-02 C2): ride out and reach a list of points. Pure Lua.
-- Data: data/regions/<region_id>.lua
--   surveys = { { key, name, points = { {x,y,z}, ... }, ordered = true|false (default true), money, rep }, ... }
-- Points are TODO-verify-in-game guesses. The server reach-watcher (server/watch.lua) emits one
-- fh:quests:point_reached per reached point; each valid one counts one toward count = #points.
local JT = FhQuestsJobTypes -- the global (in-game: set by shared/jobtypes.lua; specs: set by its spec loader)
local WR = FhQuestsWatchRules or require('watch_rules')

local function copyPoints(points)
    local out = {}
    for i, p in ipairs(points or {}) do out[i] = { x = p.x, y = p.y, z = p.z } end
    return out
end

JT.registerBuilder('survey', function(region_id, d)
    local out = {}
    for _, s in ipairs(d.surveys or {}) do
        local points = copyPoints(s.points)
        if #points > 0 then
            local ordered = s.ordered ~= false
            out[#out + 1] = {
                key = 'survey_' .. s.key, title = 'Survey: ' .. s.name,
                text = ('Ride out and mark %d spots%s.'):format(#points, ordered and ', in order' or ''),
                on = WR.POINT_EVENT, count = #points, rewards = JT.rewards(region_id, s.money, s.rep),
                region_id = region_id,
                -- the rest rides along to accept only (the watcher's targets); rebuilt from the template on re-arm
                points = points, ordered = ordered,
            }
        end
    end
    return out
end)

-- The watcher's targets of an accepted survey offer.
WR.registerKind('survey', {
    points = function(offer) return copyPoints(offer and offer.points) end,
    -- `ordered` is per template, so it is read off the offer in entry(); the kind default is ordered.
})

---Verdict: only the watcher's point event, for this holder + offer + region, and only a valid next point given the
---persisted progress count (ordered: exactly count + 1). `ordered` comes from the template; a template that is gone
---(region data changed) falls back to ordered, the strict rule.
JT.registerVerdict('survey', function(eventName, payload, state, snap)
    if eventName ~= WR.POINT_EVENT then return nil end
    if payload.citizenid ~= state.citizenid or payload.offer_key ~= snap.key then return nil end
    if payload.region_id ~= snap.region_id then return nil end
    local tmpl = JT.offerByKey('survey', snap.region_id, snap.key)
    local ordered = not tmpl or tmpl.ordered ~= false
    local count = type(state.progress) == 'table' and state.progress.count or 0
    if not WR.acceptsPoint(ordered, snap.count, count, payload.point) then return nil end
    return 'progress'
end)
