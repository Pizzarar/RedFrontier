-- Single-source coordinate resolver (world-02 block F, idea-809). Pure Lua, no natives.
-- fh_zones camps and fh_trade posts keep only gameplay fields in their configs; this fills the coordinate/region
-- fields they share with FhRegions at load, so no camp/post coordinate is defined in two places.
-- After resolution consumers see EXACTLY the same fields as before (camp.center vector3, post.x/y/z numbers).
local M = {}

local function vec3(c)
    if type(c) ~= 'table' or type(c.x) ~= 'number' or type(c.y) ~= 'number' or type(c.z) ~= 'number' then return nil end
    if vector3 then return vector3(c.x, c.y, c.z) end -- CfxLua
    return { x = c.x, y = c.y, z = c.z }              -- busted/spec table stand-in
end

---Fill `center` (vector3) and `region` (string) on each camp from FhRegions.territories[camp.territory].
---Camps keep `territory` (the id); a camp whose territory is missing/unknown is left untouched
---(world_spacing_spec asserts every camp resolves, so a bogus territory is caught there).
function M.resolveCamps(camps, regions)
    for _, camp in pairs(camps or {}) do
        local terr = regions and regions.territories and regions.territories[camp.territory]
        if terr then
            camp.region = terr.region
            camp.center = vec3(terr.center)
        end
    end
end

---Fill `region`, `x`, `y`, `z` on each post from FhRegions.posts[post.id].
function M.resolvePosts(posts, regions)
    for _, post in ipairs(posts or {}) do
        local p = regions and regions.posts and regions.posts[post.id]
        if p then
            post.region = p.region
            post.x, post.y, post.z = p.x, p.y, p.z
        end
    end
end

if GetCurrentResourceName then
    FhPlaceResolver = M
else
    return M
end
