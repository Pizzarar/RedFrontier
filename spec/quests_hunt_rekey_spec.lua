-- Run from repo root: `python tools/run-specs.py spec/quests_hunt_rekey_spec.lua`.
-- idea-902: hunt_request offer keys are region-scoped ('hunt_<region_id>_<animal>_<N>star'), so two regions that
-- offer the same animal/stars give distinct, independently completable jobs; and rows saved under the old unscoped
-- key ('<animal>_<N>star') are re-keyed on load without losing progress, double-claiming or double-paying.
-- idea-902b: matching is region-scoped too (where.region_id = the offer's region; fh_hunting emits the selling
-- trapper's region): a sale completes only the job of its own region; re-keyed legacy jobs keep their unscoped where.
-- Pure parts (builder, jobs.migrateLegacy / migratedId, ledger reason) first, then the server load path (main.lua +
-- api.lua over a stubbed oxmysql that keeps rows, a ledger and transactions).
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local describe, it, eq, same = T.describe, T.it, T.eq, T.same
local RES = here .. '../server/resources/[fh]/'
local QROOT = RES .. 'fh_quests/'
package.path = QROOT .. 'shared/?.lua;' .. package.path

local JT = dofile(QROOT .. 'shared/jobtypes.lua')
local Jobs = require('jobs')
local E = require('engine')
local I = require('intake')
local R = require('rewards')
local regions = require('regions')

local T0 = 1795651200
local ME = 'ABC123'
local OLD_ID = 'job:hunt_request:elk_3star'
local NEW_HL = 'job:hunt_request:hunt_heartlands_elk_3star'
local NEW_SM = 'job:hunt_request:hunt_scarlett_meadows_elk_3star'

local function events()
    local set = {}
    for _, name in ipairs(E.INTAKE) do set[name] = true end
    return set
end

-- Two regions sharing an animal/stars (the collision quests-02 C5 had to avoid in data).
local SHARED = { hunt = { { 'elk', 3, 42 } } }
local function offerIn(region_id) return JT.BUILDERS.hunt_request(region_id, SHARED)[1] end

local function accept(region_id, states, now, offer)
    local snap = assert(Jobs.snapshot('hunt_request', offer or offerIn(region_id), region_id, true))
    local def = assert(Jobs.def(snap, { regions = regions.regions, events = events() }))
    local st, err = E.start(def, states, ME, now or T0)
    if not st then return nil, err end
    st.progress.job = snap
    states[def.id] = st
    return def, st
end

local function hook(...) return JT.verdict('hunt_request', ...) end
local function sold(over)
    local p = { citizenid = ME, item_id = 'pelt_elk', animal = 'elk', size_class = 'bulky', quality = 3, price = 40,
        region_id = 'heartlands' }
    for k, v in pairs(over or {}) do p[k] = v end
    return p
end

-- The snapshot a pre-idea-902 acceptOffer stored (old key, region of the board it was accepted on).
local function legacySnap(region_id, key)
    return { job_type = 'hunt_request', key = key or 'elk_3star', region_id = region_id or 'heartlands',
        title = 'Pelt wanted: 3-star elk', text = 'Sell a 3-star or better elk pelt.', on = 'fh:hunting:pelt_sold',
        where = { quality = { min = 3 }, animal = { eq = 'elk' } },
        rewards = { money = 63, rep = { region_id = region_id or 'heartlands', delta = 2 } },
        cooldown_min = 60, hook = true }
end

local function legacyState(over)
    local st = { citizenid = ME, quest_id = OLD_ID, status = 'active', step = 1,
        progress = { count = 0, completions = 2, job = legacySnap() }, cooldown_until = T0 - 60, updated_at = T0 - 600 }
    for k, v in pairs(over or {}) do st[k] = v end
    return st
end

local OPTS = { regions = regions.regions }

-- ---------------------------------------------------------------- builder
describe('quests hunt rekey: region-scoped hunt_request keys', function()
    it('the key is hunt_<region>_<animal>_<N>star and the quest id fits the 64-char id limit for all data', function()
        eq('hunt_heartlands_elk_3star', offerIn('heartlands').key)
        local n = 0
        for region_id in pairs(JT.DATA) do
            for _, o in ipairs(JT.offers('hunt_request', region_id)) do
                local prefix = 'hunt_' .. region_id .. '_'
                eq(prefix, o.key:sub(1, #prefix), o.key)
                eq(JT.huntKey(region_id, o.animal, o.stars), o.key)
                assert(#Jobs.questId('hunt_request', o.key) <= E.LIMITS.idLen, o.key .. ' too long')
                -- the re-key of the old key this offer had is exactly the new key (rows land on the live offer)
                eq(o.key, Jobs.migrateKey('hunt_request', region_id, ('%s_%dstar'):format(o.animal, o.stars)))
                eq(nil, Jobs.legacyId(Jobs.questId('hunt_request', o.key), regions.regions), 'new key is not legacy')
                n = n + 1
            end
        end
        assert(n >= 20, 'every region data entry checked')
        -- the longest region id with the longest animal still fits
        assert(#Jobs.questId('hunt_request', JT.huntKey('cumberland_forest', 'alligator', 3)) <= E.LIMITS.idLen)
    end)

    it('two regions offering the same animal/stars give distinct offers and quest ids', function()
        local hl, sm = offerIn('heartlands'), offerIn('scarlett_meadows')
        assert(hl.key ~= sm.key, 'keys differ')
        eq(NEW_HL, Jobs.questId('hunt_request', hl.key))
        eq(NEW_SM, Jobs.questId('hunt_request', sm.key))
        eq('heartlands', hl.region_id); eq('scarlett_meadows', sm.region_id)
        -- idea-902b: same animal/quality predicates, but each offer matches only sales in its own region
        same({ quality = { min = 3 }, animal = { eq = 'elk' }, region_id = { eq = 'heartlands' } }, hl.where)
        same({ quality = { min = 3 }, animal = { eq = 'elk' }, region_id = { eq = 'scarlett_meadows' } }, sm.where)
    end)

    it('both can be held at once and completed independently, each with its own reward, reason and cooldown', function()
        local states = {}
        local defHl, stHl = accept('heartlands', states)
        assert(defHl, tostring(stHl))
        -- the second region's offer is not blocked by the first (no fh_quest_active collision)
        local defSm, stSm = accept('scarlett_meadows', states)
        assert(defSm, 'second region accept refused: ' .. tostring(stSm))
        eq('active', states[NEW_HL].status); eq('active', states[NEW_SM].status)

        -- complete only the heartlands one (feed its state alone): scarlett stays active
        local ch = I.feed({ [NEW_HL] = defHl }, { [NEW_HL] = states[NEW_HL] }, 'fh:hunting:pelt_sold', sold(), T0 + 10,
            function() return hook end)
        eq(1, #ch)
        states[NEW_HL] = ch[1].after
        eq('done', states[NEW_HL].status)
        eq('active', states[NEW_SM].status)
        eq('quest:' .. NEW_HL, R.reason(defHl))
        eq('heartlands', R.parts(defHl)[1].region_id)

        -- heartlands (reward paid) is in cooldown, scarlett is unaffected and completes on its own later
        states[NEW_HL] = R.finish(states[NEW_HL], T0 + 11)
        local _, err = accept('heartlands', states, T0 + 20)
        eq('fh_quest_cooldown', err)
        ch = I.feed({ [NEW_SM] = defSm }, { [NEW_SM] = states[NEW_SM] }, 'fh:hunting:pelt_sold',
            sold({ region_id = 'scarlett_meadows' }), T0 + 30, function() return hook end)
        eq(1, #ch)
        eq('done', ch[1].after.status)
        eq('quest:' .. NEW_SM, R.reason(defSm))
        eq('scarlett_meadows', R.parts(defSm)[1].region_id)
        assert(states[NEW_HL].cooldown_until ~= ch[1].after.cooldown_until, 'separate cooldowns')
    end)

    -- idea-902b: fh_hunting emits pelt_sold with the selling trapper's region (fh_hunting/shared/sell.lua:218-221).
    local function feedBoth(states, defs, payload, now, reasonOf)
        local ch = I.feed(defs, states, 'fh:hunting:pelt_sold', payload, now, function() return hook end)
        local done = {}
        for _, c in ipairs(ch) do
            states[c.quest_id] = c.after
            if c.after.status == 'done' then done[#done + 1] = c.quest_id end
            for _, fx in ipairs(c.effects) do
                if fx.type == 'reward' then eq('quest:' .. ((reasonOf or {})[c.quest_id] or c.quest_id), fx.reason) end
            end
        end
        table.sort(done)
        return done
    end

    it('both held: a sale in A completes only A; a later sale in B completes only B', function()
        local states = {}
        local defs = { [NEW_HL] = assert(accept('heartlands', states)), [NEW_SM] = assert(accept('scarlett_meadows', states)) }
        same({ NEW_HL }, feedBoth(states, defs, sold({ region_id = 'heartlands' }), T0 + 10))
        eq('done', states[NEW_HL].status); eq('active', states[NEW_SM].status)
        -- another heartlands sale changes nothing (A is done, B is not in heartlands)
        same({}, feedBoth(states, defs, sold({ region_id = 'heartlands' }), T0 + 20))
        eq('active', states[NEW_SM].status)
        same({ NEW_SM }, feedBoth(states, defs, sold({ region_id = 'scarlett_meadows' }), T0 + 30))
        eq('done', states[NEW_SM].status)
        eq(1, states[NEW_HL].progress.completions); eq(1, states[NEW_SM].progress.completions)
    end)

    it('a sale in a third region, or a pelt_sold without region_id, completes no scoped job', function()
        local states = {}
        local defs = { [NEW_HL] = assert(accept('heartlands', states)), [NEW_SM] = assert(accept('scarlett_meadows', states)) }
        same({}, feedBoth(states, defs, sold({ region_id = 'bayou_nwa' }), T0 + 10))
        local p = sold(); p.region_id = nil
        same({}, feedBoth(states, defs, p, T0 + 20))
        eq('active', states[NEW_HL].status); eq('active', states[NEW_SM].status)
        eq(0, states[NEW_HL].progress.count); eq(0, states[NEW_SM].progress.count)
    end)

    it('a legacy (unscoped) job still completes once on a sale in any region, then never again', function()
        local st = assert(Jobs.migrateLegacy(legacyState(), OPTS))
        eq(nil, st.progress.job.where.region_id, 'stored where stays unscoped (decided)')
        local def = assert(Jobs.def(st.progress.job, { regions = regions.regions, events = events() }))
        local states, defs = { [def.id] = st }, { [def.id] = def }
        local noRegion = sold(); noRegion.region_id = nil
        same({ NEW_HL }, feedBoth(states, defs, noRegion, T0, { [NEW_HL] = OLD_ID })) -- keeps its old ledger reason
        eq(3, states[NEW_HL].progress.completions)
        same({}, feedBoth(states, defs, sold({ region_id = 'scarlett_meadows' }), T0 + 5))
        eq(3, states[NEW_HL].progress.completions, 'completes once')
        -- next accept builds a fresh (scoped) snapshot from the live offer
        states[NEW_HL] = R.finish(states[NEW_HL], T0 + 6)
        assert(accept('heartlands', states, T0 + 3700))
        same({ eq = 'heartlands' }, states[NEW_HL].progress.job.where.region_id)
    end)
end)

describe('quests hunt rekey: legacy rows (jobs.migrateLegacy)', function()
    it('legacyId: only unscoped hunt_request keys are legacy', function()
        local jt, key = Jobs.legacyId(OLD_ID, regions.regions)
        eq('hunt_request', jt); eq('elk_3star', key)
        eq(nil, Jobs.legacyId(NEW_HL, regions.regions))
        eq(nil, Jobs.legacyId('job:camp_clear:camp_heartlands_t1_01', regions.regions))
        eq(nil, Jobs.legacyId('job:tier_test:heartlands_t1', regions.regions))
        eq(nil, Jobs.legacyId('family_hale_1', regions.regions))
        eq(nil, Jobs.legacyId('job:hunt_request:bogus', regions.regions))
    end)

    it('an active legacy row keeps status, counts, completions, cooldown; region comes from its snapshot', function()
        local before = legacyState({ progress = { count = 0, completions = 2, step_id = nil, job = legacySnap() } })
        local after = assert(Jobs.migrateLegacy(before, OPTS))
        eq(NEW_HL, after.quest_id)
        eq('active', after.status); eq(1, after.step); eq(ME, after.citizenid)
        eq(2, after.progress.completions); eq(0, after.progress.count)
        eq(before.cooldown_until, after.cooldown_until)
        eq('hunt_heartlands_elk_3star', after.progress.job.key)
        eq('elk_3star', after.progress.job.legacy_key)
        eq(OLD_ID, before.quest_id, 'input not mutated')
        eq('elk_3star', before.progress.job.key, 'input snapshot not mutated')
        -- the rebuilt def lands on the live offer's quest id and keeps the old ledger reason
        local def = assert(Jobs.def(after.progress.job, { regions = regions.regions, events = events() }))
        eq(NEW_HL, def.id)
        eq('quest:' .. OLD_ID, R.reason(def))
    end)

    it('the snapshot region wins over the data index (an old key several regions could build)', function()
        local st = legacyState({ progress = { count = 0, completions = 0, job = legacySnap('scarlett_meadows') } })
        local after = assert(Jobs.migrateLegacy(st, {
            regions = regions.regions, regionOf = function() return 'heartlands' end }))
        eq(NEW_SM, after.quest_id)
    end)

    it('without a snapshot: unique data index region, else the row is left as is', function()
        local bare = legacyState({ status = 'done', progress = { count = 0, completions = 1 }, cooldown_until = T0 + 900 })
        local after = assert(Jobs.migrateLegacy(bare, { regions = regions.regions,
            regionOf = function(jt, k) return jt == 'hunt_request' and k == 'elk_3star' and 'heartlands' or nil end }))
        eq(NEW_HL, after.quest_id); eq('done', after.status); eq(T0 + 900, after.cooldown_until)
        eq(nil, after.progress.job)
        local none, err = Jobs.migrateLegacy(bare, { regions = regions.regions, regionOf = function() return false end })
        eq(nil, none); eq('fh_legacy_region_unknown', err)
        none, err = Jobs.migrateLegacy(bare, OPTS)
        eq(nil, none); eq('fh_legacy_region_unknown', err)
        none, err = Jobs.migrateLegacy(bare, { regions = regions.regions, regionOf = function() return 'atlantis' end })
        eq(nil, none); eq('fh_legacy_bad_region', err)
    end)

    it('legacyHuntRegions: unique old keys map to their region; a key two regions build maps to false', function()
        local idx = JT.legacyHuntRegions()
        eq('heartlands', idx.elk_3star)
        eq('bayou_nwa', idx.alligator_1star)
        local saved = JT.DATA.scarlett_meadows
        JT.DATA.scarlett_meadows = { hunt = { { 'elk', 3, 42 } } }
        local ok, e = pcall(function() eq(false, JT.legacyHuntRegions().elk_3star) end)
        JT.DATA.scarlett_meadows = saved
        assert(ok, e)
    end)

    it('non-legacy rows are not touched', function()
        eq(nil, (Jobs.migrateLegacy({ citizenid = ME, quest_id = NEW_HL, status = 'active', progress = {} }, OPTS)))
        eq(nil, (Jobs.migrateLegacy({ citizenid = ME, quest_id = 'family_hale_1', status = 'done', progress = {} }, OPTS)))
        eq(nil, (Jobs.migrateLegacy({ citizenid = ME, quest_id = 'job:bounty:bounty_silas_crow', status = 'active',
            progress = {} }, OPTS)))
    end)

    it('after the re-key the live offer cannot be accepted on top of it (active / cooldown / reward pending)', function()
        local function blocked(st)
            local states = { [st.quest_id] = st }
            local _, err = accept('heartlands', states, T0)
            return err
        end
        eq('fh_quest_active', blocked(assert(Jobs.migrateLegacy(legacyState(), OPTS))))
        eq('fh_quest_cooldown', blocked(assert(Jobs.migrateLegacy(legacyState({ status = 'done',
            cooldown_until = T0 + 600 }), OPTS))))
        eq('fh_reward_pending', blocked(assert(Jobs.migrateLegacy(legacyState({ status = 'done',
            progress = { count = 0, completions = 1, reward_pending = true, job = legacySnap() } }), OPTS))))
    end)

    it('a re-keyed active row still completes on pelt_sold; a later re-accept pays under the new reason', function()
        local st = assert(Jobs.migrateLegacy(legacyState(), OPTS))
        local def = assert(Jobs.def(st.progress.job, { regions = regions.regions, events = events() }))
        local ch = I.feed({ [def.id] = def }, { [def.id] = st }, 'fh:hunting:pelt_sold', sold(), T0,
            function() return hook end)
        eq(1, #ch)
        eq('done', ch[1].after.status); eq(3, ch[1].after.progress.completions)
        local reward
        for _, fx in ipairs(ch[1].effects) do if fx.type == 'reward' then reward = fx end end
        eq('quest:' .. OLD_ID, reward.reason)
        -- reward paid, cooldown over: re-accept from the board -> fresh snapshot, no legacy reason
        local states = { [def.id] = R.finish(ch[1].after, T0 + 1) }
        local def2 = assert(accept('heartlands', states, T0 + 3700))
        eq(NEW_HL, def2.id)
        eq('quest:' .. NEW_HL, R.reason(def2))
        eq(nil, states[NEW_HL].progress.job.legacy_key)
        eq(3, states[NEW_HL].progress.completions)
    end)

    it('an in-flight payout of a re-keyed row is reconciled against the old ledger reason (no double pay)', function()
        local st = assert(Jobs.migrateLegacy(legacyState({ status = 'done', progress = { count = 0, completions = 1,
            reward_pending = true, reward_inflight = { key = 'money', at = T0 - 5 }, job = legacySnap() } }), OPTS))
        local def = assert(Jobs.def(st.progress.job, { regions = regions.regions, events = events() }))
        local paid, lookups = {}, {}
        local _, log = R.run(def, st, {
            now = T0, save = function() return true end,
            pay = function(part) paid[#paid + 1] = part.key; return true, true end,
            ledger = function(part, inflight)
                local _, params = R.ledgerQuery(def, part, ME, inflight)
                lookups[#lookups + 1] = params[3]
                return params[3] == 'quest:' .. OLD_ID -- fh_ledger has the pre-crash row under the old reason
            end,
        })
        same({ 'quest:' .. OLD_ID }, lookups)
        same({ 'rep' }, paid) -- money was already paid before the crash: only rep is paid now
        eq('paid', log[1].outcome)
    end)

    it('migratedId: a client journal still holding the old id finds the re-keyed row', function()
        local st = assert(Jobs.migrateLegacy(legacyState(), OPTS))
        eq(NEW_HL, Jobs.migratedId({ [st.quest_id] = st }, OLD_ID, regions.regions))
        eq(nil, Jobs.migratedId({ [st.quest_id] = st }, 'job:hunt_request:wolf_2star', regions.regions))
        eq(nil, Jobs.migratedId({ [st.quest_id] = st }, NEW_HL, regions.regions))
    end)
end)

-- ---------------------------------------------------------------- server load path (main.lua + api.lua)
local function deepCopy(v)
    if type(v) ~= 'table' then return v end
    local o = {}
    for k, x in pairs(v) do o[k] = deepCopy(x) end
    return o
end

local LEDGER_SQL = R.LEDGER_SQL

local function boot(seed, opts)
    opts = opts or {}
    local S = { db = {}, ledger = opts.ledger or {}, economy = {}, failTx = opts.failTx or false, txCount = 0,
        logs = {}, exports = {} }
    local blobs, nblob = {}, 0
    local json = {
        encode = function(t) nblob = nblob + 1; blobs[nblob] = deepCopy(t); return 'J#' .. nblob end,
        decode = function(s) return deepCopy(blobs[tonumber(s:match('^J#(%d+)$'))]) end,
    }
    local function put(row) S.db[row.citizenid .. '|' .. row.quest_id] = row end
    local function upsertParams(db, p)
        db[p[1] .. '|' .. p[2]] = { citizenid = p[1], quest_id = p[2], status = p[3], step = p[4], progress = p[5],
            cooldown_until = p[6] ~= 0 and p[6] or nil, updated_at = p[7] }
    end
    for _, st in ipairs(seed or {}) do
        put({ citizenid = st.citizenid, quest_id = st.quest_id, status = st.status, step = st.step or 1,
            progress = json.encode(st.progress), cooldown_until = st.cooldown_until, updated_at = st.updated_at or 0 })
    end
    function S.row(cid, qid)
        local r = S.db[cid .. '|' .. qid]
        if not r then return nil end
        local c = deepCopy(r)
        c.progress = json.decode(r.progress)
        return c
    end

    local MySQL = {
        scalar = { await = function(sql, p)
            if sql == LEDGER_SQL then
                for i, l in ipairs(S.ledger) do
                    if l.citizenid == p[1] and l.kind == p[2] and l.reason == p[3] and l.amount == p[4]
                        and l.region_id == p[5] then return i end
                end
                return nil
            end
            return 1 -- fh_quest_state exists
        end },
        query = { await = function(_, p)
            local out = {}
            for _, r in pairs(S.db) do if r.citizenid == p[1] then out[#out + 1] = deepCopy(r) end end
            return out
        end },
        update = { await = function(_, p) upsertParams(S.db, p); return 1 end },
        transaction = { await = function(list)
            S.txCount = S.txCount + 1
            if S.failTx then return false end
            local db = deepCopy(S.db)
            for _, q in ipairs(list) do
                if q.query:match('^INSERT') then upsertParams(db, q.values)
                elseif q.query:match('^DELETE') then db[q.values[1] .. '|' .. q.values[2]] = nil
                else return false end
            end
            S.db = db
            return true
        end },
    }
    local exportsT = setmetatable({
        ['rsg-core'] = { GetCoreObject = function()
            return { Functions = { GetPlayer = function(src)
                return src == 1 and { PlayerData = { citizenid = ME, source = 1 } } or nil
            end } }
        end },
        fh_economy = {
            pay = function(_, _, amount, reason, region_id)
                S.economy[#S.economy + 1] = { kind = 'pay', amount = amount, reason = reason, region_id = region_id }
                S.ledger[#S.ledger + 1] = { citizenid = ME, kind = 'pay', reason = reason, amount = amount,
                    region_id = region_id }
                return true
            end,
            rep = function(_, _, region_id, delta, reason)
                S.economy[#S.economy + 1] = { kind = 'rep', delta = delta, reason = reason, region_id = region_id }
                S.ledger[#S.ledger + 1] = { citizenid = ME, kind = 'rep', reason = reason, amount = delta,
                    region_id = region_id }
                return true
            end,
        },
    }, { __call = function(_, name, fn) S.exports[name] = fn end })
    local handlers, thread = {}, nil
    local env = setmetatable({
        exports = exportsT, MySQL = MySQL, json = json,
        os = setmetatable({ time = function() return S.now or T0 end }, { __index = os }),
        GetCurrentResourceName = function() return 'fh_quests' end,
        GetInvokingResource = function() return 'fh_quests' end,
        GetResourceState = function(res) return res == 'fh_progression' and 'missing' or 'started' end,
        GetPlayers = function() return { '1' } end,
        GetGameTimer = function() return 0 end,
        CreateThread = function(fn) thread = fn end,
        Wait = function() coroutine.yield('wait') end,
        TriggerEvent = function() end,
        TriggerClientEvent = function() end,
        AddEventHandler = function(name, fn) handlers[name] = handlers[name] or {}; table.insert(handlers[name], fn) end,
        print = function(msg) S.logs[#S.logs + 1] = msg end,
    }, { __index = _G })
    env._G = env
    local function run(p, ...)
        local fh = assert(io.open(p, 'rb')); local src = fh:read('a'); fh:close()
        return assert(load(src, '@' .. p, 't', env))(...)
    end
    for _, p in ipairs({ RES .. 'fh_core/shared/regions.lua', QROOT .. 'config.lua', QROOT .. 'shared/match.lua',
        QROOT .. 'shared/engine.lua', QROOT .. 'shared/board.lua', QROOT .. 'shared/jobs.lua',
        QROOT .. 'shared/watch_rules.lua', QROOT .. 'shared/jobtypes.lua', QROOT .. 'shared/jobtypes/hunt_request.lua',
        QROOT .. 'data/regions/heartlands.lua', QROOT .. 'data/regions/scarlett_meadows.lua',
        QROOT .. 'shared/intake.lua', QROOT .. 'shared/journal.lua', QROOT .. 'shared/rewards.lua',
        QROOT .. 'shared/store.lua', QROOT .. 'server/main.lua', QROOT .. 'server/api.lua' }) do
        run(p, 7) -- FXServer passes a number as the chunk vararg: shared files must fall back to their globals
    end
    local GJT = env.FhQuestsJobTypes
    -- hunt_request as server/jobtypes.lua registers it, offering one shared elk 3-star in every region
    assert(S.exports.registerJobType('hunt_request', {
        offers = function(region_id) return GJT.BUILDERS.hunt_request(region_id, SHARED) end,
        onEvent = function(name, payload, state) return GJT.verdict('hunt_request', name, payload, state) end,
    }))
    local co = coroutine.create(thread)
    local ok, why = coroutine.resume(co) -- Q.ready, then playerLoaded(1): load (+ re-key) and payoutAll
    assert(ok and why == 'wait', 'startup did not reach Wait: ' .. tostring(why))
    S.Q = env.FhQuestsServer
    function S.emit(name, payload) for _, fn in ipairs(handlers[name] or {}) do fn(payload) end end
    function S.offerId(region_id)
        local board = S.Q.boardFor(region_id, S.now or T0)
        return board.offers[1].id
    end
    function S.logged(pat)
        for _, l in ipairs(S.logs) do if tostring(l):find(pat) then return true end end
        return false
    end
    return S
end

describe('quests hunt rekey: server load path (persisted re-key)', function()
    it('an active legacy row is re-keyed in one transaction, blocks a double accept, and pays once', function()
        local S = boot({ legacyState() })
        eq(1, S.txCount)
        eq(nil, S.row(ME, OLD_ID), 'old row deleted')
        local r = assert(S.row(ME, NEW_HL), 'new row written')
        eq('active', r.status); eq(2, r.progress.completions)
        eq('hunt_heartlands_elk_3star', r.progress.job.key); eq('elk_3star', r.progress.job.legacy_key)

        local ok, err = S.exports.acceptOffer(1, S.offerId('heartlands'))
        eq(false, ok); eq('fh_quest_active', err)

        S.emit('fh:hunting:pelt_sold', sold())
        eq('done', S.row(ME, NEW_HL).status)
        eq(2, #S.economy)
        eq('quest:' .. OLD_ID, S.economy[1].reason); eq('pay', S.economy[1].kind); eq(63, S.economy[1].amount)
        eq('quest:' .. OLD_ID, S.economy[2].reason)
        S.emit('fh:hunting:pelt_sold', sold()) -- a second sale: nothing more
        eq(2, #S.economy)

        ok, err = S.exports.acceptOffer(1, S.offerId('heartlands'))
        eq(false, ok); eq('fh_quest_cooldown', err)
        -- the other region's same animal/stars is its own job: accept, complete, paid under its own id + region
        local ok2, err2, qid = S.exports.acceptOffer(1, S.offerId('scarlett_meadows'))
        eq(true, ok2, tostring(err2)); eq(NEW_SM, qid)
        S.emit('fh:hunting:pelt_sold', sold({ region_id = 'heartlands' })) -- wrong region: scoped job untouched
        eq('active', S.row(ME, NEW_SM).status); eq(2, #S.economy)
        S.emit('fh:hunting:pelt_sold', sold({ region_id = 'scarlett_meadows' }))
        eq('done', S.row(ME, NEW_SM).status)
        eq(4, #S.economy)
        eq('quest:' .. NEW_SM, S.economy[3].reason); eq('scarlett_meadows', S.economy[3].region_id)
        eq(1, S.txCount, 'no further re-key writes once migrated')
    end)

    it('a done legacy row in cooldown keeps blocking the live offer', function()
        local S = boot({ legacyState({ status = 'done', cooldown_until = T0 + 1800,
            progress = { count = 0, completions = 1, job = legacySnap() } }) })
        eq(nil, S.row(ME, OLD_ID))
        local ok, err = S.exports.acceptOffer(1, S.offerId('heartlands'))
        eq(false, ok); eq('fh_quest_cooldown', err)
        S.now = T0 + 1801
        local ok2, err2, qid = S.exports.acceptOffer(1, S.offerId('heartlands'))
        eq(true, ok2, tostring(err2)); eq(NEW_HL, qid)
        eq(1, S.row(ME, NEW_HL).progress.completions)
        eq(nil, S.row(ME, NEW_HL).progress.job.legacy_key)
    end)

    it('a crash-left in-flight legacy payout settles against the old ledger reason: money not paid twice', function()
        local S = boot({ legacyState({ status = 'done', cooldown_until = T0 + 3600, progress = { count = 0,
            completions = 1, reward_pending = true, reward_inflight = { key = 'money', at = T0 - 5 },
            job = legacySnap() } }) }, { ledger = { { citizenid = ME, kind = 'pay', reason = 'quest:' .. OLD_ID,
            amount = 63, region_id = 'heartlands' } } })
        eq(1, #S.economy)
        eq('rep', S.economy[1].kind); eq('quest:' .. OLD_ID, S.economy[1].reason)
        local r = S.row(ME, NEW_HL)
        eq('done', r.status); eq(nil, r.progress.reward_pending); eq(nil, r.progress.reward_inflight)
    end)

    it('a failed re-key write fails the load closed (old row intact), and the next load re-keys it', function()
        local S = boot({ legacyState() }, { failTx = true })
        assert(S.row(ME, OLD_ID), 'old row intact')
        eq(nil, S.row(ME, NEW_HL))
        assert(S.logged('legacy re%-key'), 'failure logged')
        local ok, err = S.exports.acceptOffer(1, S.offerId('heartlands'))
        eq(false, ok); eq('fh_db', err)
        eq(nil, S.row(ME, NEW_HL), 'no new-id row while the old one is still there')
        S.failTx = false
        local entries = S.exports.getActive(1)
        eq(1, #entries); eq(NEW_HL, entries[1].quest_id)
        eq(nil, S.row(ME, OLD_ID))
    end)

    it('a legacy row whose new id already exists is kept untouched and logged', function()
        local newer = legacyState({ quest_id = NEW_HL, status = 'done', cooldown_until = T0 + 60,
            progress = { count = 0, completions = 1, job = (function()
                local s = legacySnap(); s.key = 'hunt_heartlands_elk_3star'; return s end)() } })
        local S = boot({ legacyState(), newer })
        eq(0, S.txCount)
        assert(S.row(ME, OLD_ID)); assert(S.row(ME, NEW_HL))
        assert(S.logged('already exists'))
    end)

    -- idea-1017: one pelt_sold completes one job. The re-keyed row keeps its unscoped where, so a scarlett_meadows
    -- sale matches it and the scoped scarlett_meadows job: the legacy row (no accepted_at: it predates the field)
    -- is the older one and takes the pelt; the next pelt goes to the scoped job.
    it('a re-keyed legacy job and a newly accepted matching job: one pelt pays one job, oldest first', function()
        local S = boot({ legacyState() })
        S.now = T0 + 100
        local ok, err, qid = S.exports.acceptOffer(1, S.offerId('scarlett_meadows'))
        eq(true, ok, tostring(err)); eq(NEW_SM, qid)
        eq(T0 + 100, S.row(ME, NEW_SM).progress.accepted_at, 'accept time persisted')
        eq(nil, S.row(ME, NEW_HL).progress.accepted_at, 'legacy row has none')
        S.now = T0 + 200
        S.emit('fh:hunting:pelt_sold', sold({ region_id = 'scarlett_meadows' }))
        eq('done', S.row(ME, NEW_HL).status); eq('active', S.row(ME, NEW_SM).status)
        eq(2, #S.economy); eq('quest:' .. OLD_ID, S.economy[1].reason)
        S.emit('fh:hunting:pelt_sold', sold({ region_id = 'scarlett_meadows' }))
        eq('done', S.row(ME, NEW_SM).status)
        eq(4, #S.economy); eq('quest:' .. NEW_SM, S.economy[3].reason)
    end)

    it('abandon with the old id from a stale journal abandons the re-keyed job', function()
        local S = boot({ legacyState() })
        local ok, err = S.exports.abandon(1, OLD_ID)
        eq(true, ok, tostring(err))
        eq('abandoned', S.row(ME, NEW_HL).status)
        eq(nil, S.row(ME, OLD_ID))
    end)
end)

T.finish()
