-- WORKAROUND (plan quests-01 Q3): server side of the ox_lib fallback jobs menu (client/jobs_menu.lua). Thin
-- callbacks over the public exports, so the menu has no rules of its own. Replaced, with the client file, by the
-- @ui jobs-board screen (fh:quests:sync schema in the README) once it lands.
local function region(v)
    return type(v) == 'string' and #v <= 48 and FhRegions.regions[v] ~= nil and v or nil
end

lib.callback.register('fh:quests:menu:board', function(src, region_id)
    region_id = region(region_id)
    if not region_id then return nil, 'fh_bad_region' end
    return exports.fh_quests:getBoard(src, region_id)
end)

lib.callback.register('fh:quests:menu:active', function(src)
    local out = {}
    for _, e in ipairs(exports.fh_quests:getActive(src) or {}) do
        if e.kind == 'job' and e.status == 'active' then out[#out + 1] = e end
    end
    return out
end)

lib.callback.register('fh:quests:menu:accept', function(src, offer_id)
    if type(offer_id) ~= 'string' or #offer_id > 128 then return false, 'fh_offer_gone' end
    local ok, err = exports.fh_quests:acceptOffer(src, offer_id)
    return ok == true, err
end)

lib.callback.register('fh:quests:menu:abandon', function(src, quest_id)
    if type(quest_id) ~= 'string' or #quest_id > 128 then return false, 'fh_not_active' end
    if quest_id:sub(1, 4) ~= 'job:' then return false, 'fh_not_active' end -- the menu only handles jobs
    local ok, err = exports.fh_quests:abandon(src, quest_id)
    return ok == true, err
end)
