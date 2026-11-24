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
    assert(C.itemOf('#1') == '#1' and C.itemOf('a#b#3') == 'a#b') -- never an empty item id
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

-- ---- placement prechecks: anything the store would refuse is refused before the item leaves the chest ----
case('checkTrophy: id length and whole points within storage limits', function()
    assert(C.checkTrophy('a#1', 3) == true and select(2, C.checkTrophy('a#1', 3.9)) == 3)
    assert(select(2, C.checkTrophy('a#1', 0.5)) == 'fh_bad_points')     -- floors to 0
    assert(select(2, C.checkTrophy('a#1', 0)) == 'fh_bad_points')
    assert(select(2, C.checkTrophy('a#1', 2 ^ 40)) == 'fh_bad_points')  -- over int unsigned
    assert(select(2, C.checkTrophy(string.rep('x', 65), 3)) == 'fh_bad_trophy')
    assert(C.checkTrophy(string.rep('x', 64), 3) == true)
    assert(select(2, C.checkTrophy('', 3)) == 'fh_bad_trophy' and select(2, C.checkTrophy(7, 3)) == 'fh_bad_trophy')
end)
case('place refused: points < 1 after flooring / too big; item never taken', function()
    assert(not refused({ lookup = function() return 0.5 end }, 'fh_bad_points'))
    assert(not refused({ lookup = function() return 2 ^ 40 end }, 'fh_bad_points'))
end)
case('place refused: trophy id over 64 chars; item never taken', function()
    assert(not refused({ itemId = string.rep('x', 65) }, 'fh_bad_trophy'))
    assert(not refused({ itemId = string.rep('x', 63) }, 'fh_bad_trophy')) -- '<63>#1' is 65 chars
    local ok, _, id = C.place(ctx({ itemId = string.rep('x', 62) }))
    assert(ok and #id == 64)
end)

-- ---- server/comfort.lua under a stubbed FXServer: in-memory MySQL, exports, events. Awaits can be held (yield) so
-- ---- a test can run a second call while the first is suspended, as FXServer would between coroutines.
local PLOT = 'heartlands_01'
local function server()
    local S = { plots = { [PLOT] = 'A' }, rows = { [PLOT] = {} }, owners = { A = PLOT }, tiers = { [PLOT] = { trophy_wall = 1 } },
        chest = { trophy_deer = 3 }, points = { trophy_deer = 4 }, hold = {}, events = {}, handlers = {}, X = {}, logs = {},
        ready = true, lots = {}, claimBusy = {}, holds = {},
        order = {}, calls = { addItem = 0, removeItem = 0 } }
    local function await(tag) S.order[#S.order + 1] = tag if S.hold[tag] then S.hold[tag] = nil coroutine.yield(tag) end end
    local players = { [1] = { PlayerData = { citizenid = 'A' } }, [2] = { PlayerData = { citizenid = 'B' } } }
    local MySQL = {
        query = { await = function(sql, p)
            assert(sql:find('^SELECT trophy_id'), sql)
            -- the SELECT reads now; the result arrives after the (possibly held) await, as in oxmysql
            local out = {}
            for id, pts in pairs(S.rows[p[1]] or {}) do out[#out + 1] = { trophy_id = id, points = pts } end
            await('query')
            return out
        end },
        scalar = { await = function(_, p) return S.plots[p[1]] end },
        update = { await = function(sql, p)
            if sql:find('^INSERT INTO fh_plot_trophies .* SELECT .* FROM fh_plots WHERE plot_id = %? AND citizenid = %?') then
                await('insert')
                if S.failInsert then error('db down') end
                local id, pts, plotId, cid = p[1], p[2], p[3], p[4]
                if S.plots[plotId] ~= cid then return 0 end
                S.rows[plotId] = S.rows[plotId] or {}
                if S.rows[plotId][id] then error('Duplicate entry') end
                S.rows[plotId][id] = pts
                await('inserted') -- committed; the caller resumes later
                return 1
            elseif sql:find('^DELETE t FROM fh_plot_trophies t JOIN fh_plots p') then
                await('delete')
                local plotId, id, cid = p[1], p[2], p[3]
                if S.plots[plotId] ~= cid or not (S.rows[plotId] or {})[id] then return 0 end
                S.rows[plotId][id] = nil
                return 1
            elseif sql:find('^DELETE FROM fh_plot_trophies WHERE plot_id = %? AND trophy_id = %? AND points = %?') then
                await('undo')
                local r = S.rows[p[1]] or {}
                if r[p[2]] ~= p[3] then return 0 end
                r[p[2]] = nil
                return 1
            elseif sql:find('^DELETE t FROM fh_plot_trophies t LEFT JOIN fh_plots p') then
                await('cleanup')
                if S.plots[p[1]] then return 0 end
                local n = 0
                for _ in pairs(S.rows[p[1]] or {}) do n = n + 1 end
                S.rows[p[1]] = nil
                return n
            end
            error('unexpected sql ' .. sql)
        end },
    }
    local exportsT = setmetatable({
        fh_core = {
            removeItem = function(_, _, item, n)
                S.calls.removeItem = S.calls.removeItem + 1
                await('removeItem')
                if (S.chest[item] or 0) < n then return false, 'fh_item_not_in_chest' end
                S.chest[item] = S.chest[item] - n
                return true
            end,
            addItem = function(_, _, item, n)
                S.calls.addItem = S.calls.addItem + 1
                await('addItem')
                if S.addThrows then error('export gone') end
                if S.addRefuses ~= nil then return false, S.addRefuses or nil end
                S.chest[item] = (S.chest[item] or 0) + n
                return true
            end,
        },
        fh_hunting = { getTrophyComfort = function(_, item) return S.points[item] end },
        ['rsg-core'] = { GetCoreObject = function() return { Functions = { GetPlayer = function(src) return players[src] end } } end },
    }, { __call = function(_, name, fn) S.X[name] = fn end })
    local env = setmetatable({
        FhHomesteadConfig = cfg, FhComfort = C, FhPlotRules = dofile(dir .. 'shared/plot_rules.lua'),
        -- H13 chest hold, as server/main.lua: refused while an unclaim holds the plot (S.claimBusy[plot]); S.holds counts
        FhHomesteadClaims = {
            beginChestWrite = function(plotId)
                if S.claimBusy[plotId] then return false, 'fh_claim_busy' end
                S.holds[plotId] = (S.holds[plotId] or 0) + 1
                return true
            end,
            endChestWrite = function(plotId)
                local n = (S.holds[plotId] or 0) - 1
                S.holds[plotId] = n > 0 and n or nil
            end,
        },
        FhHomesteadSlots = {
            isReady = function() return S.ready end,
            -- like FhHomesteadClaims.plotOf: class defaults to 'claim'; S.lots = town lots (H9)
            plotOf = function(cid, class)
                if class == 'town_lot' then return S.lots[cid] end
                if class == nil or class == 'claim' then return S.owners[cid] end
            end,
            getTiers = function(plotId)
                if S.tiersThrow then error('tiers boom') end
                if not S.ready then return {}, 'fh_not_ready' end
                local out = {}
                for k, v in pairs(S.tiers[plotId] or {}) do out[k] = v end
                return out
            end,
        },
        MySQL = MySQL, exports = exportsT, GetResourceState = function() return 'started' end,
        AddEventHandler = function(name, fn) S.handlers[name] = fn end,
        TriggerEvent = function(name, ...) S.events[#S.events + 1] = { name = name, args = table.pack(...) } end,
        print = function(m) S.logs[#S.logs + 1] = tostring(m) end,
    }, { __index = _G })
    assert(loadfile(dir .. 'server/comfort.lua', 't', env))()
    -- release the plot the way server/main.lua does: claims cleared, fh_plots row deleted (cascade unless told not to)
    function S.unclaim(plotId, noCascade)
        local cid = S.plots[plotId]
        S.plots[plotId], S.owners[cid] = nil, nil
        if not noCascade then S.rows[plotId] = nil end
        S.handlers['fh:homestead:unclaimed']({ src = 0, citizenid = cid, plot_id = plotId })
    end
    function S.claim(plotId, cid) S.plots[plotId], S.owners[cid] = cid, plotId; S.rows[plotId] = S.rows[plotId] or {} end
    -- start fn in a coroutine; it runs until the first held await. Returns resume(), which finishes it.
    function S.start(fn)
        local co = coroutine.create(fn)
        local first = table.pack(coroutine.resume(co))
        assert(first[1], tostring(first[2]))
        assert(coroutine.status(co) == 'suspended', 'expected the call to suspend on a held await')
        return function()
            local r = table.pack(coroutine.resume(co))
            assert(r[1], tostring(r[2]))
            assert(coroutine.status(co) == 'dead')
            return table.unpack(r, 2, r.n)
        end
    end
    function S.count(name)
        local n = 0
        for _, ev in ipairs(S.events) do if ev.name == name then n = n + 1 end end
        return n
    end
    function S.last(name)
        for i = #S.events, 1, -1 do if S.events[i].name == name then return S.events[i].args end end
    end
    function S.logged(pat) for _, m in ipairs(S.logs) do if m:find(pat) then return true end end return false end
    return S
end
local function nrows(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end

case('server: place moves the item onto the wall, emits trophy_placed + comfort_changed', function()
    local S = server()
    assert(S.X.getComfort('A') == 5) -- trophy_wall tier 1 alone
    local ok, id = S.X.placeTrophy(1, 'trophy_deer')
    assert(ok and id == 'trophy_deer#1', tostring(id))
    assert(S.chest.trophy_deer == 2 and S.rows[PLOT]['trophy_deer#1'] == 4)
    assert(S.X.getComfort('A') == 9)
    assert(S.last('fh:homestead:trophy_placed')[1].trophy_id == 'trophy_deer#1')
    local cc = S.last('fh:homestead:comfort_changed')
    assert(cc[1] == 'A' and cc[2] == 9 and cc[3] == 5)
end)

-- CRITICAL 1: unclaim clears the cache and the trophies, and tells Survival the comfort dropped
case('server: unclaim clears cache + trophies and emits comfort_changed(cid, 0, old)', function()
    local S = server()
    assert(S.X.placeTrophy(1, 'trophy_deer'))
    assert(S.X.getComfort('A') == 9)
    S.unclaim(PLOT)
    local cc = S.last('fh:homestead:comfort_changed')
    assert(cc[1] == 'A' and cc[2] == 0 and cc[3] == 9)
    assert(S.X.getComfort('A') == 0)
    -- next owner of the same plot sees no phantom trophies
    S.claim(PLOT, 'B')
    assert(S.X.getComfort('B') == 5)
    assert(select(2, S.X.unplaceTrophy(2, 'trophy_deer#1')) == 'fh_no_trophy')
end)
case('server: unclaim with no cached comfort emits nothing; backstop deletes rows the cascade left', function()
    local S = server()
    S.rows[PLOT]['trophy_deer#1'] = 4
    S.unclaim(PLOT, true) -- no cascade
    assert(S.count('fh:homestead:comfort_changed') == 0)
    assert(S.rows[PLOT] == nil)
    -- a plot claimed again before the backstop runs keeps its rows
    local S2 = server()
    S2.rows[PLOT]['x#1'] = 2
    S2.handlers['fh:homestead:unclaimed']({ citizenid = 'Z', plot_id = PLOT })
    assert(S2.rows[PLOT]['x#1'] == 2)
end)
case('server: place suspended across unclaim aborts and refunds the item', function()
    local S = server()
    assert(S.X.getComfort('A') == 5)
    S.hold.removeItem = true
    local finish = S.start(function() return S.X.placeTrophy(1, 'trophy_deer') end)
    S.unclaim(PLOT)
    local ok, why = finish()
    assert(ok == false and why == 'fh_no_plot', tostring(why))
    assert(S.chest.trophy_deer == 3 and nrows(S.rows[PLOT]) == 0)
    assert(S.count('fh:homestead:trophy_placed') == 0)
end)
case('server: trophy load suspended across unclaim does not cache the old rows', function()
    local S = server()
    S.rows[PLOT]['trophy_deer#1'] = 4
    S.hold.query = true
    local finish = S.start(function() return S.X.getComfort('A') end)
    S.unclaim(PLOT)
    finish() -- the SELECT result it receives still has trophy_deer#1 (read before the cascade)
    S.claim(PLOT, 'A')
    assert(S.X.getComfort('A') == 5) -- reloaded from the (cascaded) table, not the stale read (that would be 9)
    assert(select(2, S.X.unplaceTrophy(1, 'trophy_deer#1')) == 'fh_no_trophy')
end)

-- CRITICAL 2: unplace deletes first, needs exactly one affected row, and a double-fire refunds once
case('server: unplace deletes the row before the refund', function()
    local S = server()
    assert(S.X.placeTrophy(1, 'trophy_deer'))
    S.order = {}
    assert(S.X.unplaceTrophy(1, 'trophy_deer#1'))
    local d, a
    for i, tag in ipairs(S.order) do if tag == 'delete' then d = i elseif tag == 'addItem' then a = i end end
    assert(d and a and d < a, 'delete must precede addItem')
    assert(S.chest.trophy_deer == 3 and nrows(S.rows[PLOT]) == 0 and S.X.getComfort('A') == 5)
    assert(S.last('fh:homestead:trophy_removed')[1].comfort == 4)
end)
-- H13: place/unplace hold the plot's chests (main.lua beginChestWrite) for their whole run, so no unclaim can slip in
-- and let a refund land in the next owner's chest; while an unclaim holds the plot they are refused, nothing moves.
case('server: place/unplace hold the chests while in flight and are refused while an unclaim holds the plot', function()
    local S = server()
    S.hold.insert = true
    local finish = S.start(function() return S.X.placeTrophy(1, 'trophy_deer') end)
    assert(S.holds[PLOT] == 1, 'hold taken while the place is in flight')
    assert(finish() == true)
    assert(S.holds[PLOT] == nil, 'hold released after the place')
    S.claimBusy[PLOT] = true
    local calls = S.calls.removeItem + S.calls.addItem
    local ok, why = S.X.placeTrophy(1, 'trophy_deer')
    assert(ok == false and why == 'fh_claim_busy', tostring(why))
    ok, why = S.X.unplaceTrophy(1, 'trophy_deer#1')
    assert(ok == false and why == 'fh_claim_busy', tostring(why))
    assert(S.calls.removeItem + S.calls.addItem == calls and S.chest.trophy_deer == 2, 'no item moved')
    assert(S.holds[PLOT] == nil)
    S.claimBusy[PLOT] = nil
    assert(S.X.unplaceTrophy(1, 'trophy_deer#1'))
    assert(S.holds[PLOT] == nil and S.chest.trophy_deer == 3)
end)
case('server: double unplace refunds exactly once', function()
    local S = server()
    assert(S.X.placeTrophy(1, 'trophy_deer'))
    S.calls.addItem = 0
    S.hold.delete = true
    local finish = S.start(function() return S.X.unplaceTrophy(1, 'trophy_deer#1') end)
    local ok2, why2 = S.X.unplaceTrophy(1, 'trophy_deer#1') -- fires while the first is mid-delete
    assert(ok2 == false and why2 == 'fh_busy', tostring(why2))
    assert(finish() == true)
    local ok3, why3 = S.X.unplaceTrophy(1, 'trophy_deer#1')
    assert(ok3 == false and why3 == 'fh_no_trophy')
    assert(S.calls.addItem == 1 and S.chest.trophy_deer == 3)
    assert(S.count('fh:homestead:trophy_removed') == 1)
end)
case('server: unplace of a row already gone (0 affected) refunds nothing', function()
    local S = server()
    assert(S.X.placeTrophy(1, 'trophy_deer'))
    S.calls.addItem = 0
    S.rows[PLOT]['trophy_deer#1'] = nil -- removed outside this cache
    local ok, why = S.X.unplaceTrophy(1, 'trophy_deer#1')
    assert(ok == false and why == 'fh_no_trophy')
    assert(S.calls.addItem == 0 and S.chest.trophy_deer == 2)
    assert(S.X.getComfort('A') == 5) -- stale cache entry dropped
end)

-- MAJOR: refund result is checked; nothing is lost silently
case('server: unplace with the chest refusing keeps the trophy on the wall', function()
    local S = server()
    assert(S.X.placeTrophy(1, 'trophy_deer'))
    S.addRefuses = 'fh_chest_full'
    local ok, why = S.X.unplaceTrophy(1, 'trophy_deer#1')
    assert(ok == false and why == 'fh_chest_full', tostring(why))
    assert(S.rows[PLOT]['trophy_deer#1'] == 4 and S.chest.trophy_deer == 2)
    assert(S.X.getComfort('A') == 9 and S.count('fh:homestead:trophy_removed') == 0)
end)
case('server: unplace refund and restore both failing is reported and logged', function()
    local S = server()
    assert(S.X.placeTrophy(1, 'trophy_deer'))
    S.addRefuses, S.failInsert = 'fh_chest_full', true -- chest refuses, then the re-insert fails too
    local ok, why = S.X.unplaceTrophy(1, 'trophy_deer#1')
    assert(ok == false and why == 'fh_unplace_refund_failed', tostring(why))
    assert(S.logged('ITEM LOST'))
end)
case('server: place whose insert fails refunds the item', function()
    local S = server()
    S.failInsert = true
    local ok, why = S.X.placeTrophy(1, 'trophy_deer')
    assert(ok == false and why == 'fh_trophy_failed', tostring(why))
    assert(S.chest.trophy_deer == 3 and S.calls.addItem == 1)
end)
case('server: place whose insert and refund both fail is reported and logged', function()
    local S = server()
    S.failInsert, S.addRefuses = true, 'fh_chest_full'
    local ok, why = S.X.placeTrophy(1, 'trophy_deer')
    assert(ok == false and why == 'fh_place_refund_failed', tostring(why))
    assert(S.logged('ITEM LOST') and S.logged('fh_chest_full'))
end)
case('server: addTrophy prechecks points < 1 and id > 64 before touching the DB', function()
    local S = server()
    assert(select(2, S.X.addTrophy('A', 'x#1', 0.5)) == 'fh_bad_points')
    assert(select(2, S.X.addTrophy('A', string.rep('x', 65), 3)) == 'fh_bad_trophy')
    assert(nrows(S.rows[PLOT]) == 0)
    assert(S.X.addTrophy('A', 'x#1', 3.7) == true and S.rows[PLOT]['x#1'] == 3)
end)
case('server: placeTrophy with a sub-1 trophy never takes the item', function()
    local S = server()
    S.points.trophy_deer = 0.5
    assert(select(2, S.X.placeTrophy(1, 'trophy_deer')) == 'fh_bad_points')
    assert(S.calls.removeItem == 0 and S.chest.trophy_deer == 3)
end)

-- MAJOR: capacity race. Concurrent places cannot pass the trophy_wall cap.
case('server: concurrent place on the same plot is refused while one is in flight; cap holds', function()
    local S = server()
    for i = 1, 5 do S.rows[PLOT]['t#' .. i] = 1 end
    S.hold.removeItem = true
    local finish = S.start(function() return S.X.placeTrophy(1, 'trophy_deer') end)
    local ok2, why2 = S.X.placeTrophy(1, 'trophy_deer')
    assert(ok2 == false and why2 == 'fh_busy', tostring(why2))
    assert(select(2, S.X.addTrophy('A', 'y#1', 1)) == 'fh_busy')
    assert(finish() == true)
    assert(select(2, S.X.placeTrophy(1, 'trophy_deer')) == 'fh_wall_full')
    assert(nrows(S.rows[PLOT]) == 6 and S.chest.trophy_deer == 2)
end)
case('server: the plot lock is released when a trophy change errors', function()
    local S = server()
    S.tiersThrow = true
    assert(select(2, S.X.placeTrophy(1, 'trophy_deer')) == 'fh_trophy_failed')
    S.tiersThrow = false
    assert(S.X.placeTrophy(1, 'trophy_deer') == true)
end)

-- MINOR: each refund failure has its own reason
case('server: refund failure reasons are distinct', function()
    local S = server()
    assert(S.X.placeTrophy(1, 'trophy_deer'))
    S.addThrows = true
    assert(select(2, S.X.unplaceTrophy(1, 'trophy_deer#1')) == 'fh_additem_unavailable')
    S.addThrows, S.addRefuses = false, false -- refused with no reason from fh_core
    assert(select(2, S.X.unplaceTrophy(1, 'trophy_deer#1')) == 'fh_chest_refused')
    S.addRefuses = 'fh_chest_full'
    assert(select(2, S.X.unplaceTrophy(1, 'trophy_deer#1')) == 'fh_chest_full')
    assert(S.rows[PLOT]['trophy_deer#1'] == 4) -- still on the wall after all three
end)

-- Round 2 (rn-df940ea043f8) M1: nothing moves and nothing is cached before H3's slot/claim load is ready
case('server: not ready: every trophy change is refused fh_not_ready, nothing taken or written', function()
    local S = server()
    S.rows[PLOT]['t#1'] = 2
    S.ready = false
    S.order = {}
    assert(select(2, S.X.placeTrophy(1, 'trophy_deer')) == 'fh_not_ready')
    assert(select(2, S.X.unplaceTrophy(1, 't#1')) == 'fh_not_ready')
    assert(select(2, S.X.addTrophy('A', 'x#1', 3)) == 'fh_not_ready')
    assert(select(2, S.X.removeTrophy('A', 't#1')) == 'fh_not_ready')
    assert(S.calls.removeItem == 0 and S.calls.addItem == 0 and S.chest.trophy_deer == 3)
    assert(S.rows[PLOT]['t#1'] == 2 and S.rows[PLOT]['x#1'] == nil)
    assert(#S.order == 0, 'no DB/export call while not ready')
end)
case('server: not ready: getComfort caches nothing and emits nothing; first read after ready counts from 0', function()
    local S = server()
    S.rows[PLOT]['t#1'] = 2
    S.ready = false
    assert(S.X.getComfort('A') == 0)
    assert(#S.order == 0, 'not-ready getComfort must not load anything (guard in refresh)')
    S.handlers['fh:homestead:slot_changed'](PLOT) -- even a slot event can't poison it
    assert(S.count('fh:homestead:comfort_changed') == 0)
    S.ready = true
    assert(S.X.getComfort('A') == 7) -- wall 5 + trophy 2, not a stale cached 0
    local cc = S.last('fh:homestead:comfort_changed')
    assert(cc[1] == 'A' and cc[2] == 7 and cc[3] == 0)
end)
case('server: not ready (getTiers fh_not_ready) inside the lock is reported, not fh_no_trophy_wall', function()
    local S = server()
    S.hold.query = true
    local finish = S.start(function() return S.X.placeTrophy(1, 'trophy_deer') end)
    S.ready = false -- e.g. a slots reload began while the trophy rows were loading
    local ok, why = finish()
    assert(ok == false and why == 'fh_not_ready', tostring(why))
    assert(S.calls.removeItem == 0 and S.chest.trophy_deer == 3)
end)

-- M2: ownership re-checked AFTER the insert await
case('server: unclaim + re-claim mid-INSERT: row taken back, item refunded, no trophy_placed', function()
    local S = server()
    assert(S.X.getComfort('A') == 5)
    S.hold.insert = true
    local finish = S.start(function() return S.X.placeTrophy(1, 'trophy_deer') end)
    S.unclaim(PLOT)
    S.tiers[PLOT] = {} -- the new claim has no trophy wall
    S.claim(PLOT, 'A')
    local ok, why = finish() -- INSERT ... SELECT now matches the new claim (affected 1)
    assert(ok == false and why == 'fh_no_plot', tostring(why))
    assert(nrows(S.rows[PLOT]) == 0, 'stale row must be undone')
    assert(S.chest.trophy_deer == 3, 'item back in the chest')
    assert(S.count('fh:homestead:trophy_placed') == 0)
    assert(S.X.getComfort('A') == 0)
    -- addTrophy has the same guard
    S.hold.insert = true
    local finish2 = S.start(function() return S.X.addTrophy('A', 'x#1', 3) end)
    S.unclaim(PLOT)
    S.claim(PLOT, 'A')
    local ok2, why2 = finish2()
    assert(ok2 == false and why2 == 'fh_no_plot' and nrows(S.rows[PLOT]) == 0, tostring(why2))
end)
case('server: unclaim right after the INSERT commits: no trophy_placed, no free refund', function()
    local S = server()
    S.hold.inserted = true
    local finish = S.start(function() return S.X.placeTrophy(1, 'trophy_deer') end)
    assert(S.rows[PLOT]['trophy_deer#1'] == 4) -- committed
    S.unclaim(PLOT) -- cascade destroys it with the plot
    local ok, why = finish()
    assert(ok == false and why == 'fh_no_plot', tostring(why))
    assert(S.calls.addItem == 0 and S.chest.trophy_deer == 2, 'trophy went with the plot; no refund')
    assert(S.count('fh:homestead:trophy_placed') == 0)
    assert(S.X.getComfort('A') == 0)
end)
-- ---- H15: comfort = the character's best home, max(claim, town lot) ----
local LOT = 'heartlands_lot_01'
local function withLot(S, cid, tiers) S.lots[cid], S.plots[LOT], S.tiers[LOT] = LOT, cid, tiers end
local function changes(S) return S.count('fh:homestead:comfort_changed') end

case('server H15: claim only', function()
    local S = server()
    S.tiers[PLOT] = { trophy_wall = 1, cabin = 1 }
    T.eq(15, S.X.getComfort('A'))
    T.eq(1, changes(S))
end)
case('server H15: lot only scores its own slots', function()
    local S = server()
    S.unclaim(PLOT)
    withLot(S, 'A', { station_1 = 1, chest_2 = 1 }) -- 3 + 2
    T.eq(5, S.X.getComfort('A'))
    T.eq(0, S.X.getComfort('Z'), 'no home')
    local ok, why = S.X.placeTrophy(1, 'trophy_deer') -- trophies stay claim-only
    T.eq(false, ok); T.eq('fh_no_plot', why)
end)
case('server H15: both homes, the larger wins either way', function()
    local S = server()
    S.tiers[PLOT] = { trophy_wall = 1, cabin = 1 } -- 15
    withLot(S, 'A', { station_1 = 1, chest_2 = 1 }) -- 5
    T.eq(15, S.X.getComfort('A'), 'claim wins')
    S.tiers[PLOT] = { trophy_wall = 1 }            -- 5
    withLot(S, 'A', { station_1 = 1, chest_2 = 1 })
    S.handlers['fh:homestead:slot_changed'](PLOT, 'cabin', 0)
    T.eq(5, S.X.getComfort('A'), 'tie')
    S.tiers[PLOT] = {}                              -- 0, trophy wall gone
    S.handlers['fh:homestead:slot_changed'](PLOT, 'trophy_wall', 0)
    T.eq(5, S.X.getComfort('A'), 'lot wins')
    T.eq(2, changes(S) - 0, 'first value 15, then 5 (tie emitted nothing)')
end)
case('server H15: trophies add to the claim side only', function()
    local S = server()
    withLot(S, 'A', { station_1 = 1, chest_2 = 1 }) -- 5
    T.eq(5, S.X.getComfort('A'))                     -- claim = wall 5, equal
    assert(S.X.placeTrophy(1, 'trophy_deer'))        -- claim 9
    T.eq(9, S.X.getComfort('A'))
    local cc = S.last('fh:homestead:comfort_changed')
    T.eq(9, cc[2]); T.eq(5, cc[3])
end)
case('server H15: unclaiming one home recomputes to the other, one event', function()
    local S = server()
    S.tiers[PLOT] = { trophy_wall = 1, cabin = 1 } -- 15
    withLot(S, 'A', { station_1 = 1, chest_2 = 1 }) -- 5
    T.eq(15, S.X.getComfort('A'))
    local n = changes(S)
    S.unclaim(PLOT)
    T.eq(n + 1, changes(S))
    local cc = S.last('fh:homestead:comfort_changed')
    T.eq('A', cc[1]); T.eq(5, cc[2]); T.eq(15, cc[3])
    T.eq(5, S.X.getComfort('A'))
    T.eq(n + 1, changes(S), 'reading again emits nothing')
    -- now the lot goes too
    S.lots.A, S.plots[LOT] = nil, nil
    S.handlers['fh:homestead:unclaimed']({ citizenid = 'A', plot_id = LOT })
    cc = S.last('fh:homestead:comfort_changed')
    T.eq(0, cc[2]); T.eq(5, cc[3]); T.eq(n + 2, changes(S))
    T.eq(0, S.X.getComfort('A'))
end)
case('server H15: abandoning the lot keeps the claim value and fires nothing', function()
    local S = server()
    S.tiers[PLOT] = { trophy_wall = 1, cabin = 1 } -- 15
    withLot(S, 'A', { station_1 = 1, chest_2 = 1 })
    T.eq(15, S.X.getComfort('A'))
    local n = changes(S)
    S.lots.A, S.plots[LOT] = nil, nil
    S.handlers['fh:homestead:unclaimed']({ citizenid = 'A', plot_id = LOT })
    T.eq(n, changes(S), 'best home unchanged: no event')
    T.eq(15, S.X.getComfort('A'))
end)
case('server H15: a lot build moves comfort only when it becomes the best home; no-op builds are silent', function()
    local S = server()
    S.unclaim(PLOT)
    withLot(S, 'A', { station_1 = 1 }) -- 3
    T.eq(3, S.X.getComfort('A'))
    local n = changes(S)
    S.handlers['fh:homestead:slot_changed'](LOT, 'station_1', 1) -- same tiers: no real change
    T.eq(n, changes(S))
    S.tiers[LOT] = { station_1 = 1, chest_2 = 1 }
    S.handlers['fh:homestead:slot_changed'](LOT, 'chest_2', 1)
    T.eq(n + 1, changes(S))
    local cc = S.last('fh:homestead:comfort_changed')
    T.eq(5, cc[2]); T.eq(3, cc[3])
    -- lot owner not cached yet (fresh server): slot_changed finds the owner by SQL and emits from 0
    local S2 = server()
    S2.unclaim(PLOT)
    withLot(S2, 'B', { chest_2 = 1 })
    S2.handlers['fh:homestead:slot_changed'](LOT, 'chest_2', 1)
    cc = S2.last('fh:homestead:comfort_changed')
    T.eq('B', cc[1]); T.eq(2, cc[2]); T.eq(0, cc[3])
end)
case('server H15: claim unclaimed mid-load still aborts with a lot held (gen guard)', function()
    local S = server()
    S.unclaim(PLOT)
    withLot(S, 'A', { chest_2 = 1 })
    S.claim(PLOT, 'A')
    S.hold.query = true
    local finish = S.start(function() return S.X.getComfort('A') end)
    S.unclaim(PLOT) -- claim released while its trophy rows were loading
    T.eq(2, finish(), 'stale claim ignored, lot value reported')
    T.eq(2, S.X.getComfort('A'))
end)
case('server H15: lot bought and built while the claim trophy load awaits is not lost', function()
    local S = server()
    S.tiers[PLOT] = {} -- claim 0, cache cold
    S.hold.query = true
    local finish = S.start(function() return S.X.getComfort('A') end)
    withLot(S, 'A', { station_1 = 1 }) -- bought + built during the await: 3
    S.handlers['fh:homestead:slot_changed'](LOT, 'station_1', 1)
    local cc = S.last('fh:homestead:comfort_changed')
    T.eq('A', cc[1]); T.eq(3, cc[2]); T.eq(0, cc[3])
    T.eq(3, finish(), 'the suspended call reports the lot')
    T.eq(1, changes(S), 'no bogus 0 afterwards')
    T.eq(3, S.X.getComfort('A'))
    S.tiers[LOT] = { station_1 = 1, chest_2 = 1 }
    S.handlers['fh:homestead:slot_changed'](LOT, 'chest_2', 1) -- byPlot still routes lot builds to A
    T.eq(5, S.last('fh:homestead:comfort_changed')[2])
end)
case('server H15: lot released (and re-bought by someone else) while the claim trophy load awaits', function()
    local S = server()
    S.tiers[PLOT] = {} -- claim 0
    withLot(S, 'A', { station_1 = 1, chest_2 = 1 }) -- would be 5
    S.hold.query = true
    local finish = S.start(function() return S.X.getComfort('A') end)
    S.lots.A, S.plots[LOT] = nil, nil
    S.handlers['fh:homestead:unclaimed']({ citizenid = 'A', plot_id = LOT })
    withLot(S, 'B', { station_1 = 1, chest_2 = 1 }) -- B buys and builds it
    S.handlers['fh:homestead:slot_changed'](LOT, 'chest_2', 1)
    T.eq(5, S.last('fh:homestead:comfort_changed')[2]); T.eq('B', S.last('fh:homestead:comfort_changed')[1])
    local n = changes(S)
    T.eq(0, finish(), "A does not inherit B's lot")
    T.eq(n, changes(S), 'nothing emitted for A')
    S.tiers[LOT] = { station_1 = 1 }
    S.handlers['fh:homestead:slot_changed'](LOT, 'chest_2', 0) -- the lot still routes to B, not A
    local cc = S.last('fh:homestead:comfort_changed')
    T.eq('B', cc[1]); T.eq(3, cc[2]); T.eq(5, cc[3])
end)
case('server H15: claim swapped repeatedly mid-load retries once, never loops', function()
    local S = server()
    S.unclaim(PLOT)
    S.claim(PLOT, 'A')
    S.hold.query = true
    local finish = S.start(function() return S.X.getComfort('A') end)
    S.unclaim(PLOT)
    S.claim('heartlands_02', 'A'); S.tiers.heartlands_02 = { trophy_wall = 1 }
    T.eq(5, finish(), 'one retry lands on the new claim')
end)
case('server H15: unclaim does not wipe the byPlot binding of a plot re-bought during its refresh await', function()
    local S = server()
    S.tiers[PLOT] = {}; S.unclaim(PLOT)
    withLot(S, 'A', { chest_2 = 1 })
    T.eq(2, S.X.getComfort('A')) -- A cached lot-only
    S.claim('heartlands_02', 'A'); S.tiers.heartlands_02 = {} -- A also holds a claim not loaded yet
    S.lots.A, S.plots[LOT] = nil, nil -- A abandons the lot
    S.hold.query = true
    local finish = S.start(function() S.handlers['fh:homestead:unclaimed']({ citizenid = 'A', plot_id = LOT }) end)
    withLot(S, 'B', { chest_2 = 1 }) -- B buys it while A's refresh awaits the claim's trophy rows
    S.handlers['fh:homestead:slot_changed'](LOT, 'chest_2', 1) -- B bound to LOT
    finish()
    S.lots.B, S.plots[LOT] = nil, nil
    S.handlers['fh:homestead:unclaimed']({ plot_id = LOT }) -- holder found only through byPlot
    local cc = S.last('fh:homestead:comfort_changed')
    T.eq('B', cc[1]); T.eq(0, cc[2]); T.eq(2, cc[3])
end)
T.finish()
