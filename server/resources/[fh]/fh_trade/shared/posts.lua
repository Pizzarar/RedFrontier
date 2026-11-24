-- Pure trade-post selection (no natives, no DB): given the resolved posts list (post.x/y/z/radius/region filled from
-- FhRegions at load) and a position, return the first post whose radius contains the position, skipping any post whose
-- region is disabled. Specced in spec/trade_posts_spec.lua.
--
-- The region gate matches fh_homestead plot_rules G1b: a post is gated only when it carries a non-empty string
-- `region`, the gate is isEnabled if a function (else the FhRegions global), and gate(region) == false. A nil/empty
-- region (legacy post) or no gate at all keeps today's behaviour: the post is allowed.
local M = {}

local function finite(n) return type(n) == 'number' and n == n and n > -math.huge and n < math.huge end

---Read x, y, z from a vector3 (CfxLua userdata) or a plain {x,y,z} table; nil on unusable input.
local function readCoords(c)
    if c == nil then return nil end
    local ok, x, y, z = pcall(function() return c.x, c.y, c.z end)
    if ok and finite(x) and finite(y) and finite(z) then return x, y, z end
    return nil
end

---The enabled gate: the passed function wins, else the FhRegions global (loaded by the fxmanifest), else nil.
local function enabledGate(isEnabled)
    if type(isEnabled) == 'function' then return isEnabled end
    if type(FhRegions) == 'table' and type(FhRegions.isEnabled) == 'function' then return FhRegions.isEnabled end
    return nil
end

---True when a post should be skipped because its region is disabled (isEnabled fails closed). A nil/empty region is
---never gated (kept), matching fh_homestead plot_rules.lua G1b.
function M.regionDisabled(post, isEnabled)
    local region = type(post) == 'table' and post.region or nil
    if type(region) ~= 'string' or region == '' then return false end
    local gate = enabledGate(isEnabled)
    return gate ~= nil and gate(region) == false
end

---First post (in list order) whose radius contains `coords`, skipping disabled-region posts. Returns nil when none.
function M.nearestPost(posts, coords, isEnabled)
    local x, y, z = readCoords(coords)
    if not x then return nil end
    for _, p in ipairs(posts or {}) do
        if type(p) == 'table' and not M.regionDisabled(p, isEnabled)
            and finite(p.x) and finite(p.y) and finite(p.radius) then
            local pz = finite(p.z) and p.z or z
            local dx, dy, dz = x - p.x, y - p.y, z - pz
            if dx * dx + dy * dy + dz * dz <= p.radius * p.radius then return p end
        end
    end
    return nil
end

if GetCurrentResourceName then
    FhTradePosts = M
else
    return M
end
