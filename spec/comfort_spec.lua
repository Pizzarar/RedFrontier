local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local case = T.it
local dir = here .. '../server/resources/[fh]/fh_homestead/'
FhBuildRules = dofile(dir .. 'shared/build_rules.lua') -- comfort.lua reads the global (set by the resource in CfxLua)
local C = dofile(dir .. 'shared/comfort.lua')
dofile(dir .. 'config.lua')
local cfg = FhHomesteadConfig
local plot = cfg.plots.heartlands_01
local R = FhBuildRules

local function total(tiers, tro) return (C.compute(plot, tiers, tro, cfg)) end

case('slot sums match build_rules.totalComfort', function()
    assert(total({}, nil) == 0)
    assert(total({ cabin = 2, fence = 1 }, nil) == R.totalComfort(plot, { cabin = 2, fence = 1 }))
    assert(total({ cabin = 2, fence = 1 }, nil) == 10 + 15 + 5)
end)
case('trophies need the trophy wall', function()
    assert(total({ cabin = 1 }, { a = 5 }) == 10)
    assert(total({ trophy_wall = 0 }, { a = 5 }) == 0)
    assert(total({ trophy_wall = 1 }, { a = 5 }) == 5 + 5)
    local t, s, tp = C.compute(plot, { trophy_wall = 1 }, { a = 5, b = 3 }, cfg)
    assert(t == 13 and s == 5 and tp == 8)
end)
case('trophy cap and per-wall-tier count limit', function()
    local c = { trophyComfortCap = 10, trophyMaxByWallTier = { [1] = 3 } }
    assert(C.trophyPoints({ trophy_wall = 1 }, { a = 8, b = 8 }, c) == 10) -- capped
    local big = { trophyComfortCap = 1000, trophyMaxByWallTier = { [1] = 3 } }
    assert(C.trophyPoints({ trophy_wall = 1 }, { a = 9, b = 8, c = 7, d = 2, e = 1 }, big) == 24) -- best 3 only
    assert(C.trophyPoints({ trophy_wall = 1 }, { a = 9, b = 8, c = 7, d = 2, e = 1 }, { trophyComfortCap = 1000 }) == 27) -- no count limit
end)
case('deterministic with tied points', function()
    local c = { trophyMaxByWallTier = { [1] = 1 } }
    for _ = 1, 20 do assert(C.trophyPoints({ trophy_wall = 1 }, { x = 4, y = 4, z = 4 }, c) == 4) end
end)
case('add/remove/duplicate ids (map semantics)', function()
    local tro = { deer = 4 }
    assert(total({ trophy_wall = 1 }, tro) == 9)
    tro.deer = 4 -- same id again: still one trophy
    assert(total({ trophy_wall = 1 }, tro) == 9)
    tro.bear = 6
    assert(total({ trophy_wall = 1 }, tro) == 15)
    tro.deer = nil
    assert(total({ trophy_wall = 1 }, tro) == 11)
end)
case('invalid trophy points are ignored', function()
    assert(C.trophyPoints({ trophy_wall = 1 }, { a = -3, b = 0, c = 'x', d = 0 / 0, e = math.huge, f = 2 }, cfg) == 2)
end)
case('nil safety', function()
    assert(C.compute(nil, nil, nil, nil) == 0)
    assert(C.compute(plot, nil, nil, nil) == 0)
    assert(C.compute(plot, 'bad', 'bad', nil) == 0)
    assert(C.trophyPoints(nil, nil, nil) == 0)
    assert(total({ trophy_wall = 1 }, 5) == 5)
end)
case('change detection: value moves only when an input changes', function()
    local a = total({ cabin = 1 }, nil)
    assert(total({ cabin = 1 }, nil) == a)
    local b = total({ cabin = 1, trophy_wall = 1 }, { a = 3 })
    assert(b ~= a and b == 10 + 5 + 3)
    assert(total({ cabin = 1, trophy_wall = 1 }, { a = 3 }) == b)
end)

-- ---- placement ----
local function ctx(over)
    local c = {
        citizenid = 'A', ownerCitizenid = 'A', tiers = { trophy_wall = 1 }, trophies = {}, cfg = cfg, itemId = 'trophy_deer',
        lookup = function() return 4 end,
        removeItem = function() return true end,
    }
    for k, v in pairs(over or {}) do c[k] = v end
    return c
end
local function refused(over, want)
    local removed = false
    over = over or {}
    local base = over.removeItem
    over.removeItem = function(...) removed = true if base then return base(...) end return true end
    local ok, err = C.place(ctx(over))
    assert(ok == false and err == want, tostring(err))
    return removed
end

case('place ok: points from lookup, id <item>#1, item removed', function()
    local took
    local ok, pts, id = C.place(ctx({ removeItem = function(i) took = i return true end }))
    assert(ok and pts == 4 and id == 'trophy_deer#1' and took == 'trophy_deer')
    local _, _, id2 = C.place(ctx({ trophies = { ['trophy_deer#1'] = 4 } }))
    assert(id2 == 'trophy_deer#2')
    assert(C.itemOf('trophy_deer#2') == 'trophy_deer' and C.itemOf('x') == 'x')
end)
case('place refused: not owner / no plot owner / no character', function()
    assert(not refused({ citizenid = 'B' }, 'fh_not_owner'))
    assert(not refused({ ownerCitizenid = false }, 'fh_plot_free'))
    assert(not refused({ citizenid = false }, 'fh_no_character'))
end)
case('place refused: no trophy wall', function()
    assert(not refused({ tiers = { trophy_wall = 0 } }, 'fh_no_trophy_wall'))
    assert(not refused({ tiers = {} }, 'fh_no_trophy_wall'))
    assert(not refused({ tiers = 'none' }, 'fh_no_trophy_wall'))
end)
case('place refused: not a trophy (nil lookup) and hunting missing; item never taken', function()
    assert(not refused({ lookup = function() return nil end }, 'fh_not_a_trophy'))
    assert(not refused({ lookup = function() return 0 end }, 'fh_not_a_trophy'))
    assert(not refused({ lookup = function() return nil, 'fh_hunting_unavailable' end }, 'fh_hunting_unavailable'))
end)
case('place refused: removeItem unavailable / item missing', function()
    local _, err = C.place(ctx({ removeItem = function() return false, 'fh_removeitem_unavailable' end }))
    assert(err == 'fh_removeitem_unavailable')
    _, err = C.place(ctx({ removeItem = function() return false end }))
    assert(err == 'fh_removeitem_failed')
end)
case('place refused: wall full and points cap; item never taken', function()
    local full = {}
    for i = 1, 6 do full['t#' .. i] = 1 end
    assert(not refused({ trophies = full }, 'fh_wall_full'))
    assert(not refused({ trophies = { a = 20 } }, 'fh_trophy_cap'))
    assert(not refused({ cfg = { trophyComfortCap = 5, trophyMaxByWallTier = { [1] = 6 } }, trophies = { a = 5 } }, 'fh_trophy_cap'))
end)
case('unplace: owner only, trophy must exist', function()
    local base = { citizenid = 'A', ownerCitizenid = 'A', trophyId = 'a#1', trophies = { ['a#1'] = 3 } }
    assert(C.canUnplace(base))
    local function why(o) local c = {} for k, v in pairs(base) do c[k] = v end for k, v in pairs(o) do c[k] = v end local _, e = C.canUnplace(c) return e end
    assert(why({ citizenid = 'B' }) == 'fh_not_owner')
    assert(why({ trophyId = 'zzz' }) == 'fh_no_trophy')
    assert(why({ trophyId = 5 }) == 'fh_no_trophy')
    assert(why({ ownerCitizenid = false }) == 'fh_plot_free')
    assert(select(2, C.canUnplace(nil)) == 'fh_no_character')
end)
T.finish()
