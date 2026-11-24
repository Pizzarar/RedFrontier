-- fh_trade post selection (world-02 G2): nearestPost is a pure scan over the resolved posts with a region gate, so a
-- post in a disabled region is never returned (isEnabled fails closed) while an enabled one is. A nil/empty region is
-- never gated (kept), matching fh_homestead plot_rules G1b. Run: `~/.venvs/rf/bin/python tools/run-specs.py spec/trade_posts_spec.lua`.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local it, eq = T.it, T.eq
local fh = here .. '../server/resources/[fh]/'

local P = dofile(fh .. 'fh_trade/shared/posts.lua')

local function post(id, region, x, y, z, radius)
    return { id = id, region = region, x = x, y = y, z = z, radius = radius }
end

it('an enabled-region post is returned when the player stands inside it', function()
    local posts = { post('valentine_post', 'heartlands', -176, 630, 114, 6) }
    local found = P.nearestPost(posts, { x = -176, y = 630, z = 114 }, function(region) return region == 'heartlands' end)
    eq('valentine_post', found and found.id)
end)

it('a disabled-region post is never returned, even when the player stands inside it', function()
    local posts = { post('annesburg_post', 'roanoke_ridge', 2925, 1295, 96, 6) }
    local found = P.nearestPost(posts, { x = 2925, y = 1295, z = 96 }, function() return false end)
    eq(nil, found)
end)

it('a disabled-region post is skipped while a later enabled post is still reachable', function()
    local posts = {
        post('annesburg_post', 'roanoke_ridge', 2925, 1295, 96, 6),   -- disabled: must be skipped
        post('valentine_post', 'heartlands', -176, 630, 114, 6),       -- enabled
    }
    local found = P.nearestPost(posts, { x = 2925, y = 1295, z = 96 }, function(region) return region == 'heartlands' end)
    eq(nil, found, 'disabled post was returned')
    local found2 = P.nearestPost(posts, { x = -176, y = 630, z = 114 }, function(region) return region == 'heartlands' end)
    eq('valentine_post', found2 and found2.id)
end)

it('a nil region is never gated (kept), matching G1b', function()
    local posts = { { id = 'legacy', x = 0, y = 0, z = 0, radius = 10 } }
    local found = P.nearestPost(posts, { x = 0, y = 0, z = 0 }, function() return false end)
    eq('legacy', found and found.id)
end)

it('falls back to the FhRegions.isEnabled global when no gate is passed', function()
    dofile(here .. 'support/world_config.lua') -- sets _G.FhRegions (heartlands enabled, roanoke_ridge disabled)
    local posts = {
        post('valentine_post', 'heartlands', -176, 630, 114, 6),
        post('annesburg_post', 'roanoke_ridge', 2925, 1295, 96, 6),
    }
    local found = P.nearestPost(posts, { x = 2925, y = 1295, z = 96 })
    eq(nil, found, 'disabled roanoke_ridge post must be skipped via the FhRegions global')
    local found2 = P.nearestPost(posts, { x = -176, y = 630, z = 114 })
    eq('valentine_post', found2 and found2.id)
end)

T.finish()
