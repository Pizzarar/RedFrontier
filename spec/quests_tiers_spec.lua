-- Run from repo root: `lua spec/quests_tiers_spec.lua` (or via tools/run-specs.py).
-- quests-03 T1: offer min_tier (default 1), pure board.visible(offers, tier), server-side per-region tier gating on
-- board open + accept (fh_offer_locked), optional dev-flag locked = { min_tier }, getTier failure -> tier 1, and
-- fh:progression:tier_changed refreshing the board for that player only.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local describe, it, eq, same = T.describe, T.it, T.eq, T.same
local R = here .. '../server/resources/[fh]/'
local QROOT = R .. 'fh_quests/'
package.path = QROOT .. 'shared/?.lua;' .. package.path

local B = dofile(QROOT .. 'shared/board.lua')
local JT = dofile(QROOT .. 'shared/jobtypes.lua')
local J = dofile(QROOT .. 'shared/journal.lua')
local Jobs = require('jobs')
local TX = dofile(QROOT .. 'server/ui_text.lua')

local CLOCK = 1795651200 -- whole hour boundary

local function keysOf(list)
    local out = {}
    for i, o in ipairs(list or {}) do out[i] = o.key end
    return out
end

describe('quests tiers: offer min_tier default and builders', function()
    it('every built-in builder sets min_tier = 1 when omitted in region data', function()
        local FIELD = {
            hunt_request = 'hunt', camp_clear = 'camps', bounty = 'bounties', supply_run = 'supply',
            survey = 'surveys', escort = 'escorts', rescue = 'rescues',
        }
        local d = JT.DATA.heartlands
        for _, jt in ipairs(JT.TYPES) do
            local raw = d[FIELD[jt]] or {}
            local list = JT.offers(jt, 'heartlands')
            assert(#list > 0, 'expected heartlands offers for ' .. jt)
            local omitted = 0
            for i, o in ipairs(list) do
                local src = raw[i]
                if src and src.min_tier == nil and (jt ~= 'hunt_request' or src[4] == nil) then
                    omitted = omitted + 1
                    eq(1, o.min_tier, jt .. ':' .. o.key .. ' default min_tier')
                end
            end
            assert(omitted >= 1, 'expected at least one omitted min_tier entry in heartlands for ' .. jt)
        end
    end)

    it('every built-in builder preserves an explicit min_tier and normalizes invalid values to 1', function()
        local probe = 'tier_probe_region'
        JT.registerRegion(probe, {
            hunt = {
                { 'deer', 1, 6 },
                { 'wolf', 3, 24, min_tier = 2 },
                { 'bear', 3, 50, 3 },
                { 'coyote', 1, 5, min_tier = 0 },
            },
            camps = {
                { id = 'c1', label = 'Camp 1', money = 30, rep = 2 },
                { id = 'c2', label = 'Camp 2', money = 60, rep = 4, min_tier = 2 },
            },
            bounties = {
                { key = 'b1', name = 'One', model = 'm', coords = { x = 1, y = 2, z = 3 }, heading = 0, money = 20, rep = 1 },
                { key = 'b2', name = 'Two', model = 'm', coords = { x = 1, y = 2, z = 3 }, heading = 0, money = 50, rep = 3, min_tier = 3 },
            },
            supply = {
                { post = 'p1', item = 'trade_cloth', amount = 2, money = 10, rep = 1 },
                { post = 'p2', item = 'trade_salt', amount = 5, money = 30, rep = 2, min_tier = 2 },
            },
            surveys = {
                { key = 's1', name = 'S1', points = { { x = 1, y = 2, z = 3 } }, money = 20, rep = 2 },
                { key = 's2', name = 'S2', points = { { x = 1, y = 2, z = 3 } }, money = 40, rep = 3, min_tier = 2 },
            },
            escorts = {
                { key = 'e1', name = 'E1', model = 'm', start = { x = 1, y = 2, z = 3 }, destination = { x = 4, y = 5, z = 6 }, heading = 0, money = 20, rep = 2 },
                { key = 'e2', name = 'E2', model = 'm', start = { x = 1, y = 2, z = 3 }, destination = { x = 4, y = 5, z = 6 }, heading = 0, money = 50, rep = 4, min_tier = 3 },
            },
            rescues = {
                { key = 'r1', name = 'R1', camp = 'c1', model = 'm', coords = { x = 1, y = 2, z = 3 }, heading = 0, money = 20, rep = 2 },
                { key = 'r2', name = 'R2', camp = 'c2', model = 'm', coords = { x = 1, y = 2, z = 3 }, heading = 0, money = 50, rep = 4, min_tier = 2 },
            },
        })
        local ok, err = pcall(function()
            local hunt = JT.offers('hunt_request', probe)
            eq(1, hunt[1].min_tier); eq(2, hunt[2].min_tier); eq(3, hunt[3].min_tier); eq(1, hunt[4].min_tier)
            local camps = JT.offers('camp_clear', probe)
            eq(1, camps[1].min_tier); eq(2, camps[2].min_tier)
            local bounties = JT.offers('bounty', probe)
            eq(1, bounties[1].min_tier); eq(3, bounties[2].min_tier)
            local supply = JT.offers('supply_run', probe)
            eq(1, supply[1].min_tier); eq(2, supply[2].min_tier)
            local surveys = JT.offers('survey', probe)
            eq(1, surveys[1].min_tier); eq(2, surveys[2].min_tier)
            local escorts = JT.offers('escort', probe)
            eq(1, escorts[1].min_tier); eq(3, escorts[2].min_tier)
            local rescues = JT.offers('rescue', probe)
            eq(1, rescues[1].min_tier); eq(2, rescues[2].min_tier)
        end)
        JT.DATA[probe] = nil
        assert(ok, err)
    end)
end)

describe('quests tiers: pure board.visible(offers, tier)', function()
    it('filters by min_tier <= tier, preserves order, defaults omitted min_tier to 1, and does not mutate input', function()
        local list = {
            { key = 'a', title = 'A' },                  -- omitted -> 1
            { key = 'b', title = 'B', min_tier = 2 },
            { key = 'c', title = 'C', min_tier = 1 },
            { key = 'd', title = 'D', min_tier = 3 },
            { key = 'e', title = 'E', min_tier = 2 },
        }
        same({ 'a', 'c' }, keysOf(B.visible(list, 1)))
        same({ 'a', 'b', 'c', 'e' }, keysOf(B.visible(list, 2)))
        same({ 'a', 'b', 'c', 'd', 'e' }, keysOf(B.visible(list, 3)))
        eq(5, #list, 'input list not mutated')
    end)

    it('works on rotated board entries and handles nil/invalid tier as tier 1', function()
        local rotated = B.rotate('heartlands', 10, {
            bounty = {
                { key = 't1', title = 'T1' },
                { key = 't2', title = 'T2', min_tier = 2 },
                { key = 't3', title = 'T3', min_tier = 3 },
            },
        }, { min = 3, max = 3 })
        eq(3, #rotated)
        for _, o in ipairs(rotated) do
            local want = o.key == 't1' and 1 or (o.key == 't2' and 2 or 3)
            eq(want, o.min_tier)
        end
        eq(1, #B.visible(rotated, 1))
        eq(1, #B.visible(rotated, nil))
        eq(1, #B.visible(rotated, 0/0))
        eq(2, #B.visible(rotated, 2))
        eq(3, #B.visible(rotated, 3))
        same({}, B.visible(nil, 2))
    end)

    it('journal.boardView attaches locked = { min_tier } only when passed a locked map', function()
        local offers = {
            { id = 'heartlands:1:bounty:a', job_type = 'bounty', key = 'a', title = 'A', offer = { text = 'A' } },
            { id = 'heartlands:1:bounty:b', job_type = 'bounty', key = 'b', title = 'B', offer = { text = 'B', min_tier = 2 } },
        }
        local vDefault = J.boardView('heartlands', 1, 3600, offers, {}, Jobs.questId)
        eq(nil, vDefault.offers[1].locked)
        eq(nil, vDefault.offers[2].locked)
        local vFlag = J.boardView('heartlands', 1, 3600, offers, {}, Jobs.questId, { ['heartlands:1:bounty:b'] = 2 })
        eq(nil, vFlag.offers[1].locked)
        same({ min_tier = 2 }, vFlag.offers[2].locked)
    end)

    it('ui_text maps fh_offer_locked to a player-facing error notice', function()
        local n = TX.acceptNotice(false, 'fh_offer_locked')
        eq('error', n.notice_kind)
        assert(n.notice ~= TX.DEFAULT, 'fh_offer_locked should have its own message, not generic default')
    end)
end)

-- ---------------------------------------------------------------- stubbed server harness (main.lua + api.lua)
local function bootServer(opts)
    opts = opts or {}
    local S = {
        online = opts.online or { [1] = 'CID_A', [2] = 'CID_B' },
        tiers = opts.tiers or {},            -- [src] = { [region_id] = tier }
        progState = opts.progState or 'started',
        getTierThrows = opts.getTierThrows or false,
        getTierCalls = {},
        canUnlockCalls = 0,
        events = {},                         -- local TriggerEvent calls
        clientEvents = {},                   -- TriggerClientEvent calls
        economyCalls = {},                   -- fh_economy pay/rep calls
        handlers = {},                       -- eventName -> { fn, ... }
        exports = {},                        -- exported server fns
        acceptHookCalls = 0,
        dbWrites = 0,
        source = 0,
    }

    local exportsT = setmetatable({
        ['rsg-core'] = {
            GetCoreObject = function()
                return {
                    Functions = {
                        GetPlayer = function(src)
                            local cid = S.online[src]
                            return cid and { PlayerData = { citizenid = cid, source = src } } or nil
                        end,
                    },
                }
            end,
        },
        fh_progression = {
            getTier = function(_, src, region_id)
                S.getTierCalls[#S.getTierCalls + 1] = { src = src, region_id = region_id }
                if S.getTierThrows then error('fh_progression getTier boom') end
                if opts.getTierReturn ~= nil then return opts.getTierReturn end
                local bySrc = S.tiers[src]
                return bySrc and bySrc[region_id] or 1
            end,
            canUnlock = function()
                S.canUnlockCalls = S.canUnlockCalls + 1
                error('must not gate contracts on canUnlock')
            end,
        },
        fh_economy = {
            pay = function(_, src, amount, reason, region_id)
                S.economyCalls[#S.economyCalls + 1] = {
                    kind = 'pay', src = src, amount = amount, reason = reason, region_id = region_id,
                }
                return true
            end,
            rep = function(_, src, region_id, delta, reason)
                S.economyCalls[#S.economyCalls + 1] = {
                    kind = 'rep', src = src, region_id = region_id, delta = delta, reason = reason,
                }
                return true
            end,
        },
    }, {
        __call = function(_, name, fn) S.exports[name] = fn end,
    })

    local MySQL = {
        scalar = { await = function() return 1 end },
        query = { await = function() return {} end },
        update = { await = function() S.dbWrites = S.dbWrites + 1; return 1 end },
    }
    local json = {
        encode = function() return '{}' end,
        decode = function() return {} end,
    }
    local thread
    local env = setmetatable({
        exports = exportsT,
        MySQL = MySQL,
        json = json,
        os = setmetatable({ time = function() return CLOCK end }, { __index = os }),
        GetCurrentResourceName = function() return 'fh_quests' end,
        GetInvokingResource = function() return 'fh_quests' end,
        GetResourceState = function(res)
            if res == 'fh_progression' then return S.progState end
            return 'started'
        end,
        GetPlayers = function()
            local out = {}
            for src in pairs(S.online) do out[#out + 1] = tostring(src) end
            table.sort(out)
            return out
        end,
        GetGameTimer = function() return 0 end,
        CreateThread = function(fn) thread = fn end,
        Wait = function() coroutine.yield('wait') end,
        TriggerEvent = function(name, payload)
            S.events[#S.events + 1] = { name = name, payload = payload }
        end,
        TriggerClientEvent = function(name, target, payload)
            S.clientEvents[#S.clientEvents + 1] = { name = name, target = target, payload = payload }
        end,
        AddEventHandler = function(name, fn)
            S.handlers[name] = S.handlers[name] or {}
            S.handlers[name][#S.handlers[name] + 1] = fn
        end,
        print = function() end,
    }, { __index = _G })
    env._G = env

    local files = {
        R .. 'fh_core/shared/regions.lua',
        QROOT .. 'config.lua',
        QROOT .. 'shared/match.lua',
        QROOT .. 'shared/engine.lua',
        QROOT .. 'shared/board.lua',
        QROOT .. 'shared/jobs.lua',
        QROOT .. 'shared/intake.lua',
        QROOT .. 'shared/journal.lua',
        QROOT .. 'shared/rewards.lua',
        QROOT .. 'shared/store.lua',
        QROOT .. 'server/main.lua',
        QROOT .. 'server/api.lua',
    }
    for _, p in ipairs(files) do
        local fh = assert(io.open(p, 'rb'))
        local src = fh:read('a')
        fh:close()
        assert(load(src, '@' .. p, 't', env))()
    end

    if opts.showLockedOffers ~= nil then
        env.FhQuestsConfig.showLockedOffers = opts.showLockedOffers
    end

    -- Boot the startup thread to set Q.ready = true and load online players.
    assert(thread, 'main.lua did not start its thread')
    local co = coroutine.create(thread)
    local ok, why = coroutine.resume(co)
    assert(ok and why == 'wait', 'startup did not reach Wait: ' .. tostring(why))

    -- Register a test job type supplying predictable t1 + t2 + t3 offers per region (all <= 5 so rotate keeps all).
    local regOk, regErr = S.exports.registerJobType('tier_test', {
        offers = function(region_id)
            return {
                { key = region_id .. '_t1', title = 'T1 ' .. region_id, on = 'fh:zones:camp_cleared',
                  rewards = { money = 10, rep = { region_id = region_id, delta = 2 } }, region_id = region_id, min_tier = 1 },
                { key = region_id .. '_t2', title = 'T2 ' .. region_id, on = 'fh:zones:camp_cleared',
                  rewards = { money = 20, rep = { region_id = region_id, delta = 4 } }, region_id = region_id, min_tier = 2 },
                { key = region_id .. '_t3', title = 'T3 ' .. region_id, on = 'fh:zones:camp_cleared',
                  rewards = { money = 40, rep = { region_id = region_id, delta = 6 } }, region_id = region_id, min_tier = 3 },
            }
        end,
        accept = function()
            S.acceptHookCalls = S.acceptHookCalls + 1
            return true
        end,
    })
    assert(regOk, tostring(regErr))

    -- Clear startup noise so tests assert cleanly on their own actions.
    S.events = {}
    S.clientEvents = {}
    S.getTierCalls = {}
    S.env = env
    S.Q = env.FhQuestsServer

    function S.emit(name, payload, src)
        env.source = src or 0
        for _, fn in ipairs(S.handlers[name] or {}) do fn(payload) end
        env.source = 0
    end

    function S.offerId(region_id, key)
        local board = S.Q.boardFor(region_id, CLOCK)
        for _, o in ipairs(board.offers) do
            if o.key == key then return o.id end
        end
        error('no offer ' .. key .. ' in ' .. region_id)
    end

    return S
end

local function offerKeys(view)
    local out = {}
    for _, o in ipairs(view.offers or {}) do
        out[o.id:match('([^:]+)$')] = true
    end
    return out
end

describe('quests tiers: server gating, per-region tier, fallback, dev flag, tier_changed', function()
    it('accept of a t2 offer by a t1 player fails with fh_offer_locked (no hook, no DB write)', function()
        local S = bootServer({ tiers = { [1] = { heartlands = 1 } } })
        local t2Id = S.offerId('heartlands', 'heartlands_t2')
        local ok, err = S.exports.acceptOffer(1, t2Id)
        eq(false, ok)
        eq('fh_offer_locked', err)
        eq(0, S.acceptHookCalls)
        eq(0, S.dbWrites)
        eq(0, S.canUnlockCalls)

        -- Raising tier to 2 allows accepting the exact same offer id.
        S.tiers[1].heartlands = 2
        local ok2, err2, qid = S.exports.acceptOffer(1, t2Id)
        eq(true, ok2, tostring(err2))
        eq('job:tier_test:heartlands_t2', qid)
        eq(1, S.acceptHookCalls)
    end)

    it('per-region tier: t3 in bayou_nwa, t1 in heartlands -> bayou t2 visible/acceptable, heartlands t2 hidden/locked', function()
        local S = bootServer({ tiers = { [1] = { bayou_nwa = 3, heartlands = 1 } } })

        local bayouView = assert(S.exports.getBoard(1, 'bayou_nwa'))
        local bayouKeys = offerKeys(bayouView)
        eq(true, bayouKeys.bayou_nwa_t1)
        eq(true, bayouKeys.bayou_nwa_t2)
        eq(true, bayouKeys.bayou_nwa_t3)

        local hlView = assert(S.exports.getBoard(1, 'heartlands'))
        local hlKeys = offerKeys(hlView)
        eq(true, hlKeys.heartlands_t1)
        eq(nil, hlKeys.heartlands_t2)
        eq(nil, hlKeys.heartlands_t3)

        -- Accept checks the offer's region too.
        local okBayou, errBayou = S.exports.acceptOffer(1, S.offerId('bayou_nwa', 'bayou_nwa_t2'))
        eq(true, okBayou, tostring(errBayou))
        local okHl, errHl = S.exports.acceptOffer(1, S.offerId('heartlands', 'heartlands_t2'))
        eq(false, okHl)
        eq('fh_offer_locked', errHl)
        eq(0, S.canUnlockCalls)
    end)

    it('getTier failure or fh_progression not started falls back to tier 1', function()
        local S1 = bootServer({ progState = 'stopped', tiers = { [1] = { heartlands = 3 } } })
        local v1 = assert(S1.exports.getBoard(1, 'heartlands'))
        eq(1, #v1.offers)
        eq(true, offerKeys(v1).heartlands_t1)
        local ok1, err1 = S1.exports.acceptOffer(1, S1.offerId('heartlands', 'heartlands_t2'))
        eq(false, ok1); eq('fh_offer_locked', err1)

        local S2 = bootServer({ getTierThrows = true, tiers = { [1] = { heartlands = 3 } } })
        local v2 = assert(S2.exports.getBoard(1, 'heartlands'))
        eq(1, #v2.offers)
        eq(true, offerKeys(v2).heartlands_t1)
        local ok2, err2 = S2.exports.acceptOffer(1, S2.offerId('heartlands', 'heartlands_t2'))
        eq(false, ok2); eq('fh_offer_locked', err2)
    end)

    it('dev flag off hides locked offers; dev flag on includes them with locked = { min_tier } (still rejected on accept)', function()
        local SOff = bootServer({ tiers = { [1] = { heartlands = 1 } }, showLockedOffers = false })
        local vOff = assert(SOff.exports.getBoard(1, 'heartlands'))
        eq(1, #vOff.offers)
        eq(nil, vOff.offers[1].locked)

        local SOn = bootServer({ tiers = { [1] = { heartlands = 1 } }, showLockedOffers = true })
        local vOn = assert(SOn.exports.getBoard(1, 'heartlands'))
        eq(3, #vOn.offers)
        local byKey = {}
        for _, o in ipairs(vOn.offers) do byKey[o.id:match('([^:]+)$')] = o end
        eq(nil, byKey.heartlands_t1.locked)
        same({ min_tier = 2 }, byKey.heartlands_t2.locked)
        same({ min_tier = 3 }, byKey.heartlands_t3.locked)

        -- Even when shown via the dev flag, server acceptOffer still refuses with fh_offer_locked.
        local ok, err = SOn.exports.acceptOffer(1, byKey.heartlands_t2.id)
        eq(false, ok); eq('fh_offer_locked', err)
    end)

    it('fh:progression:tier_changed triggers a board refresh for that player only', function()
        local S = bootServer({ tiers = { [1] = { heartlands = 1 }, [2] = { heartlands = 1 } } })
        -- Both players open the heartlands board at tier 1.
        local vA = assert(S.exports.getBoard(1, 'heartlands'))
        local vB = assert(S.exports.getBoard(2, 'heartlands'))
        eq(1, #vA.offers); eq(1, #vB.offers)
        S.events = {}
        S.clientEvents = {}

        -- Player 1 reaches tier 2 in heartlands.
        S.tiers[1].heartlands = 2
        S.emit('fh:progression:tier_changed', { src = 1, citizenid = 'CID_A', region_id = 'heartlands', old = 1, new = 2 })

        -- board_changed emitted for heartlands + player 1.
        eq(1, #S.events)
        eq('fh:quests:board_changed', S.events[1].name)
        eq('heartlands', S.events[1].payload.region_id)
        eq(1, S.events[1].payload.src)

        -- fh:quests:sync sent ONLY to player 1, with the t2 offer now visible; player 2 untouched.
        eq(1, #S.clientEvents)
        eq('fh:quests:sync', S.clientEvents[1].name)
        eq(1, S.clientEvents[1].target)
        local syncedKeys = offerKeys(S.clientEvents[1].payload.board)
        eq(true, syncedKeys.heartlands_t1)
        eq(true, syncedKeys.heartlands_t2)
        eq(nil, syncedKeys.heartlands_t3)

        -- A client-sourced tier_changed event is ignored.
        S.events = {}; S.clientEvents = {}
        S.emit('fh:progression:tier_changed', { src = 1, citizenid = 'CID_A', region_id = 'heartlands', old = 2, new = 3 }, 1)
        eq(0, #S.events)
        eq(0, #S.clientEvents)

        -- Tier change in another region (bayou_nwa) does not push a heartlands sync.
        S.tiers[1].bayou_nwa = 2
        S.emit('fh:progression:tier_changed', { src = 1, citizenid = 'CID_A', region_id = 'bayou_nwa', old = 1, new = 2 })
        eq(1, #S.events)
        eq('bayou_nwa', S.events[1].payload.region_id)
        eq(1, S.events[1].payload.src)
        eq(0, #S.clientEvents)
    end)
end)

describe('quests tiers: T2 reward scaling frozen in job snapshot at accept', function()
    it('accept of a t2 offer stores x1.5 rewards in progress.job and pays x1.5 via fh_economy', function()
        local S = bootServer({ tiers = { [1] = { heartlands = 2 } } })
        local t2Id = S.offerId('heartlands', 'heartlands_t2')
        local ok, err, qid = S.exports.acceptOffer(1, t2Id)
        eq(true, ok, tostring(err))
        local st = S.Q.cache['CID_A'][qid]
        assert(st and st.progress and st.progress.job, 'job snapshot stored')
        eq(30, st.progress.job.rewards.money, '20 * 1.5 = 30')
        eq(6, st.progress.job.rewards.rep.delta, '4 * 1.5 = 6')

        -- Complete the job and verify payout goes through fh_economy with the scaled values.
        S.emit('fh:zones:camp_cleared', { citizenid = 'CID_A', region_id = 'heartlands' })
        eq(2, #S.economyCalls)
        eq('pay', S.economyCalls[1].kind); eq(30, S.economyCalls[1].amount); eq('quest:' .. qid, S.economyCalls[1].reason)
        eq('rep', S.economyCalls[2].kind); eq(6, S.economyCalls[2].delta); eq('quest:' .. qid, S.economyCalls[2].reason)
    end)

    it('accept of a t1 offer by a t3 player leaves t1 rewards unchanged (scales by offer min_tier, not player tier)', function()
        local S = bootServer({ tiers = { [1] = { heartlands = 3 } } })
        local t1Id = S.offerId('heartlands', 'heartlands_t1')
        local ok, err, qid = S.exports.acceptOffer(1, t1Id)
        eq(true, ok, tostring(err))
        local st = S.Q.cache['CID_A'][qid]
        eq(10, st.progress.job.rewards.money)
        eq(2, st.progress.job.rewards.rep.delta)

        S.emit('fh:zones:camp_cleared', { citizenid = 'CID_A', region_id = 'heartlands' })
        eq(2, #S.economyCalls)
        eq(10, S.economyCalls[1].amount)
        eq(2, S.economyCalls[2].delta)
    end)

    it('a later player tier change or config multiplier change does not alter a running job payout', function()
        local S = bootServer({ tiers = { [1] = { heartlands = 2 } } })
        local t2Id = S.offerId('heartlands', 'heartlands_t2')
        local ok, err, qid = S.exports.acceptOffer(1, t2Id)
        eq(true, ok, tostring(err))

        -- Mutate both player tier and config multipliers after accept, and drop memoized defs to force rebuild from snapshot.
        S.tiers[1].heartlands = 3
        S.env.FhQuestsConfig.tierRewardMultipliers[2] = 5.0
        S.Q.resetJobDefs()

        S.emit('fh:zones:camp_cleared', { citizenid = 'CID_A', region_id = 'heartlands' })
        eq(2, #S.economyCalls)
        eq('pay', S.economyCalls[1].kind); eq(30, S.economyCalls[1].amount)
        eq('rep', S.economyCalls[2].kind); eq(6, S.economyCalls[2].delta)
    end)

    it('accept of a t3 offer stores x2.25 rewards and does not mutate the shared board offer', function()
        local S = bootServer({ tiers = { [1] = { heartlands = 3 } } })
        local t3Id = S.offerId('heartlands', 'heartlands_t3')
        local ok, err, qid = S.exports.acceptOffer(1, t3Id)
        eq(true, ok, tostring(err))
        local st = S.Q.cache['CID_A'][qid]
        eq(90, st.progress.job.rewards.money, '40 * 2.25 = 90')
        eq(14, st.progress.job.rewards.rep.delta, '6 * 2.25 = 13.5 -> 14')

        -- Shared board offer retains its unscaled base rewards.
        local boardOffer = S.env.FhQuestsBoard.find(S.Q.boardFor('heartlands', CLOCK).offers, t3Id)
        eq(40, boardOffer.offer.rewards.money)
        eq(6, boardOffer.offer.rewards.rep.delta)
    end)
end)

describe('quests lockedFor: optional per-player display lock hook (idea-873)', function()
    local function reg(S, hook, name)
        local ok, err = S.exports.registerJobType(name or 'lock_test', {
            offers = function(region_id)
                return {
                    { key = region_id .. '_lk', title = 'LK', on = 'fh:zones:camp_cleared', region_id = region_id,
                      rewards = { money = 5 }, min_tier = 1 },
                    { key = region_id .. '_lk2', title = 'LK2', on = 'fh:zones:camp_cleared', region_id = region_id,
                      rewards = { money = 5 }, min_tier = 2 },
                }
            end,
            lockedFor = hook,
        })
        assert(ok, tostring(err))
    end
    local function byKey(view)
        local out = {}
        for _, o in ipairs(view.offers) do out[o.id:match('([^:]+)$')] = o end
        return out
    end
    local function only1(offer, src)
        if src == 1 and offer.key == 'heartlands_lk' then return { reason = 'need_contracts_t2' } end
        return nil
    end

    it('rejects a non-callable lockedFor at registration', function()
        local S = bootServer({})
        local ok, err = S.exports.registerJobType('bad_lock', { offers = function() return {} end, lockedFor = 5 })
        eq(false, ok); eq('fh_bad_hook:lockedFor', err)
    end)

    it('locks or unlocks per player (flag on shows locked + reason; flag off hides the offer)', function()
        local S = bootServer({ showLockedOffers = true, tiers = { [1] = { heartlands = 3 }, [2] = { heartlands = 3 } } })
        reg(S, only1)
        local a, b = byKey(assert(S.exports.getBoard(1, 'heartlands'))), byKey(assert(S.exports.getBoard(2, 'heartlands')))
        same({ reason = 'need_contracts_t2' }, a.heartlands_lk.locked)
        eq(nil, b.heartlands_lk.locked)
        eq(nil, a.heartlands_lk2.locked)

        local Soff = bootServer({ showLockedOffers = false, tiers = { [1] = { heartlands = 3 }, [2] = { heartlands = 3 } } })
        reg(Soff, only1)
        eq(nil, byKey(assert(Soff.exports.getBoard(1, 'heartlands'))).heartlands_lk)
        eq(true, byKey(assert(Soff.exports.getBoard(2, 'heartlands'))).heartlands_lk ~= nil)
    end)

    it('absent hook leaves behaviour unchanged', function()
        local S = bootServer({ showLockedOffers = true, tiers = { [1] = { heartlands = 1 } } })
        reg(S, nil)
        local v = byKey(assert(S.exports.getBoard(1, 'heartlands')))
        eq(nil, v.heartlands_lk.locked)
        same({ min_tier = 2 }, v.heartlands_lk2.locked)
    end)

    it('a throwing hook shows the offer locked (flag on) and hides it (flag off); never unlocked', function()
        local S = bootServer({ showLockedOffers = true, tiers = { [1] = { heartlands = 3 } } })
        reg(S, function() error('boom') end)
        local v = byKey(assert(S.exports.getBoard(1, 'heartlands')))
        same({ reason = 'fh_lock_error' }, v.heartlands_lk.locked)
        local Soff = bootServer({ showLockedOffers = false, tiers = { [1] = { heartlands = 3 } } })
        reg(Soff, function() error('boom') end)
        eq(nil, byKey(assert(Soff.exports.getBoard(1, 'heartlands'))).heartlands_lk)
    end)

    it('combines with the tier lock: tier min_tier kept, hook reason added, hook-only lock needs no tier', function()
        local S = bootServer({ showLockedOffers = true, tiers = { [1] = { heartlands = 1 } } })
        reg(S, function(offer) return { reason = 'r_' .. offer.key } end)
        local v = byKey(assert(S.exports.getBoard(1, 'heartlands')))
        same({ min_tier = 2, reason = 'r_heartlands_lk2' }, v.heartlands_lk2.locked)
        same({ reason = 'r_heartlands_lk' }, v.heartlands_lk.locked)
        eq(nil, v.heartlands_t1.locked, 'other job types unaffected')
        -- accept stays authoritative: the tier gate still answers fh_offer_locked
        local ok, err = S.exports.acceptOffer(1, S.offerId('heartlands', 'heartlands_lk2'))
        eq(false, ok); eq('fh_offer_locked', err)
    end)

    it('board cache is shared: the hook never mutates the cached offers and both players see one board', function()
        local seen
        local S = bootServer({ showLockedOffers = true, tiers = { [1] = { heartlands = 3 }, [2] = { heartlands = 3 } } })
        reg(S, function(offer) offer.title = 'MUTATED'; seen = true; return nil end)
        local before = S.Q.boardFor('heartlands', CLOCK)
        assert(S.exports.getBoard(1, 'heartlands')); assert(S.exports.getBoard(2, 'heartlands'))
        eq(true, seen)
        eq(before, S.Q.boardFor('heartlands', CLOCK), 'same cached board table')
        for _, o in ipairs(before.offers) do eq(true, o.offer.title ~= 'MUTATED') end
    end)
end)

T.finish()
