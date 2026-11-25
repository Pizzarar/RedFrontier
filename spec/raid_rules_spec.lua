-- Pure claim-raid rules spec (plan a-life-03 C1). Run via tools/run-specs.py.
-- Loads shared/alife_rules.lua + shared/raid_rules.lua against the real FhRegions + FhZonesConfig camps. rng injected.
-- Implemented A-Life — Thanks to S.T.A.L.K.E.R. A-Life by GSC Game World.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local case, eq, same = T.it, T.eq, T.same
local A = here .. '../server/resources/[fh]/fh_alife/'
FhAlifeRules = dofile(A .. 'shared/alife_rules.lua')
local Rules = FhAlifeRules
local R = dofile(A .. 'shared/raid_rules.lua')

local Regions = dofile(here .. 'support/world_config.lua')
dofile(here .. '../server/resources/[fh]/fh_zones/config.lua')
dofile(A .. 'config.lua')
local cfg = FhAlifeConfig
local camps = FhZonesConfig.camps
local ctx = Rules.context(cfg, Regions, camps)
local RC = cfg.claimRaids
local HEART = { 'heartlands_t1_01', 'heartlands_t1_02', 'heartlands_t1_03', 'heartlands_t2_01' }

local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

---Deterministic rng: next pre-set value (ignores lo/hi); errors when it runs out.
local function seq(...)
    local vals, i = { ... }, 0
    return function()
        i = i + 1
        assert(vals[i] ~= nil, 'seq rng exhausted at call ' .. i)
        return vals[i]
    end
end
local function noRng() error('rng must not be called') end
local function always(v) return function() return v end end

---Park-Miller LCG rng(lo, hi), with a call log.
local function lcg(seed)
    local s, log = seed, {}
    return function(lo, hi)
        s = (s * 16807) % 2147483647
        local v = lo + (s % (hi - lo + 1))
        log[#log + 1] = v
        return v
    end, log
end

---State with every camp law-held except `outlaw` (a list of camp ids).
local function stateWith(outlaw)
    local st = Rules.newState()
    local keep = {}
    for _, c in ipairs(outlaw or {}) do keep[c] = true end
    for id in pairs(camps) do if not keep[id] then st.owners[id] = 'lawmen' end end
    return st
end

local NIL = {} -- override sentinel: pairs() skips nil values
local function apply(p, extra)
    for k, v in pairs(extra or {}) do if v == NIL then p[k] = nil else p[k] = v end end
    return p
end
local function claim(owner, extra)
    local p = { class = 'claim', raidable = true, lawSafe = false, owner = owner, region = 'heartlands',
        coords = { x = 1, y = 2, z = 3 }, fenceBuilt = false }
    return apply(p, extra)
end
local function townLot(owner, extra)
    local p = { class = 'town_lot', raidable = false, lawSafe = true, owner = owner, region = 'heartlands',
        coords = { x = 1, y = 2, z = 3 }, fenceBuilt = false }
    return apply(p, extra)
end

---Run `n` sim steps the way the server will: FhAlifeRules.tick(1) then R.tick. @return raid effects (all steps)
local function run(st, n, world, rng)
    local out = {}
    for _ = 1, n do
        Rules.tick(ctx, st, 1, function() return 100 end) -- 100 > chancePct: no road raids; retakes irrelevant
        for _, e in ipairs(R.tick(ctx, st, world, rng)) do out[#out + 1] = e end
    end
    return out
end

local function types(effects)
    local out = {}
    for _, e in ipairs(effects) do out[#out + 1] = e.type end
    return out
end

-- ---------------------------------------------------------------- eligibility

case('config: claimRaids knobs match the plan', function()
    eq(180, RC.cooldownTicks); eq(2, RC.stealStacks); eq(0.5, RC.stealMaxFraction); eq(5, RC.warnTicks)
    assert(RC.liveCap >= 1 and RC.baseChance > 0 and RC.fenceMitigation > 0 and RC.fenceMitigation < 1)
end)

case('eligible: raidable claim + owner + owner online', function()
    eq(true, R.eligible(claim('CID1'), { CID1 = true }))
    eq(true, R.eligible(claim('CID1'), true))
    local ok, why = R.eligible(claim('CID1'), { CID2 = true })
    eq(false, ok); eq('owner_offline', why)
    ok, why = R.eligible(claim(nil), { CID1 = true })
    eq(false, ok); eq('no_owner', why)
    ok, why = R.eligible(claim(''), true)
    eq(false, ok); eq('no_owner', why)
    eq(false, (R.eligible(nil, true)))
    eq(false, (R.eligible(claim('CID1', { raidable = 'yes' }), true)), 'raidable must be exactly true')
end)

case('eligible: town lots never (raidable=false, class town_lot, lawSafe, bad/missing class)', function()
    local bad = {
        townLot('CID1'),
        townLot('CID1', { class = NIL }),
        townLot('CID1', { class = '' }),
        townLot('CID1', { class = 42 }),
        townLot('CID1', { class = 'town_lot', raidable = true }), -- inconsistent facts: class wins
        townLot('CID1', { raidable = true, lawSafe = NIL }),       -- class alone still refuses
        claim('CID1', { lawSafe = true }),                        -- lawSafe wins
        claim('CID1', { class = NIL }),                           -- raidable but no class: refused
        claim('CID1', { class = {} }),
    }
    for i, p in ipairs(bad) do
        local ok, why = R.eligible(p, { CID1 = true })
        eq(false, ok, 'case ' .. i); eq('not_raidable', why, 'case ' .. i)
    end
end)

case('town lots never raid: 300 ticks, owner online and home, max odds, rng never called', function()
    local st = stateWith(HEART) -- every heartlands camp outlaw-held
    local world = { online = { CID1 = true }, home = {}, plots = {
        lot_a = townLot('CID1'),
        lot_b = townLot('CID1', { class = NIL }),
        lot_c = townLot('CID1', { class = 'garbage', raidable = false }),
        lot_d = townLot('CID1', { raidable = true }),
    } }
    for id in pairs(world.plots) do world.home[id] = true end
    same({}, run(st, 300, world, noRng))
    same({}, R.listRaids(st))
    -- the admin force path refuses too
    for id, p in pairs(world.plots) do
        local sq, err = R.forceRaid(ctx, st, id, p, true, noRng)
        eq(nil, sq); eq('fh_alife_not_raidable', err)
    end
end)

-- ---------------------------------------------------------------- odds

case('raidChance: base x outlaw camps x fence mitigation, capped at 1', function()
    local p = claim('CID1')
    eq(0, (R.raidChance(ctx, stateWith({}), p)))
    local c, n = R.raidChance(ctx, stateWith({ HEART[1] }), p)
    eq(RC.baseChance, c); eq(1, n)
    c, n = R.raidChance(ctx, stateWith({ HEART[1], HEART[3] }), p)
    eq(RC.baseChance * 2, c); eq(2, n)
    c = R.raidChance(ctx, stateWith({ HEART[1], HEART[3] }), claim('CID1', { fenceBuilt = true }))
    eq(RC.baseChance * 2 * (1 - RC.fenceMitigation), c)
    -- an outlaw camp in another region does not count
    eq(0, (R.raidChance(ctx, stateWith({ 'scarlett_meadows_t1_01' }), p)))
    local big = Rules.context({ claimRaids = { baseChance = 0.6 } }, Regions, camps)
    eq(1, (R.raidChance(big, stateWith(HEART), p)))
    eq(0, (R.raidChance(ctx, stateWith(HEART), claim('CID1', { region = NIL }))))
    eq(0, (R.raidChance(ctx, stateWith(HEART), claim('CID1', { region = 'bogus' }))))
end)

case('zero outlaw camps in the region: never raids and makes no rng call', function()
    local st = stateWith({ 'scarlett_meadows_t1_01' }) -- outlaws elsewhere only
    local world = { plots = { p1 = claim('CID1') }, online = { CID1 = true } }
    same({}, run(st, 300, world, noRng))
    local sq, err = R.forceRaid(ctx, st, 'p1', claim('CID1'), true, noRng)
    eq(nil, sq); eq('fh_alife_no_camp', err)
end)

case('odds roll: rng(1, 10000) <= chance x 10000 (hit at the edge, miss one past it)', function()
    local world = { plots = { p1 = claim('CID1') }, online = { CID1 = true } }
    local st = stateWith({ HEART[1] })
    local edge = RC.baseChance * 10000
    same({}, R.tick(ctx, st, world, seq(edge + 1)))
    local effects = R.tick(ctx, st, world, seq(edge, 4))
    same({ 'raid_warned' }, types(effects))
    local e = effects[1]
    eq('sq1', e.squad_id); eq('p1', e.plot_id); eq('CID1', e.citizenid); eq(HEART[1], e.camp_id)
    eq('heartlands', e.region_id); eq('outlaws', e.faction); eq(4, e.strength); eq(RC.warnTicks, e.warn_ticks)
    eq(st.tick + RC.warnTicks, e.arrive_tick)
    assert(type(e.camp_label) == 'string' and e.camp_label ~= '')
    same({ id = 'sq1', goal = 'raid', faction = 'outlaws', strength = 4, from = HEART[1], to = 'p1', plot = 'p1',
        region = 'heartlands', citizenid = 'CID1', phase = 'warn', travel = RC.returnTicks,
        etaTick = st.tick + RC.warnTicks }, st.squads.sq1)
end)

case('raiding camp: the first outlaw-held camp by id when several', function()
    local st = stateWith({ HEART[4], HEART[2], HEART[3] })
    eq(HEART[2], R.raidingCamp(ctx, st, 'heartlands'))
    same({ HEART[2], HEART[3], HEART[4] }, R.outlawCamps(ctx, st, 'heartlands'))
    local sq = R.forceRaid(ctx, st, 'p1', claim('CID1'), true, seq(3))
    eq(HEART[2], sq.from)
end)

case('offline owner or no owner: never rolls', function()
    local st = stateWith(HEART)
    same({}, run(st, 50, { plots = { p1 = claim('CID1') }, online = {} }, noRng))
    same({}, run(st, 50, { plots = { p1 = claim(nil) }, online = { CID1 = true } }, noRng))
    same({}, run(st, 50, { plots = { p1 = claim('CID1') } }, noRng))
    same({}, run(st, 50, nil, noRng))
end)

-- ---------------------------------------------------------------- cooldown + cap

case('cooldown: no roll on the claim for cooldownTicks after the warning, then rolls again', function()
    local st = stateWith({ HEART[1] })
    local world = { plots = { p1 = claim('CID1') }, online = { CID1 = true }, home = {} }
    local start = st.tick
    same({ 'raid_warned' }, types(R.tick(ctx, st, world, seq(1, 3))))
    eq(start + RC.cooldownTicks, st.raidCooldowns.p1)
    eq(true, (R.onCooldown(st, 'p1')))
    -- run the whole raid out; rng is only asked for nothing until the cooldown ends
    local rolls = 0
    local function counting() rolls = rolls + 1 return 10000 end -- always a miss
    run(st, RC.cooldownTicks - 1, world, counting)
    eq(0, rolls, 'no roll during the cooldown')
    same({}, R.listRaids(st), 'the raid came and went')
    run(st, 1, world, counting)
    eq(1, rolls, 'rolls again once the cooldown ends')
    eq(nil, st.raidCooldowns.p1, 'expired cooldown pruned')
end)

case('global live-raid cap: at most liveCap warned at once (plot id order)', function()
    local st = stateWith(HEART)
    local world = { online = { A = true, B = true, C = true }, plots = {
        c3 = claim('C'), a1 = claim('A'), b2 = claim('B') } }
    local effects = R.tick(ctx, st, world, always(1))
    eq(RC.liveCap, #effects)
    eq('a1', effects[1].plot_id); eq('b2', effects[2].plot_id)
    eq(RC.liveCap, R.liveRaidCount(st))
    same({}, R.tick(ctx, st, world, noRng), 'cap reached: no roll')
    -- a forced raid ignores the cap and the cooldown
    local sq, eff = R.forceRaid(ctx, st, 'c3', world.plots.c3, world.online, seq(3))
    eq('c3', sq.plot); eq('raid_warned', eff[1].type)
    local again, err = R.forceRaid(ctx, st, 'c3', world.plots.c3, world.online, noRng)
    eq(nil, again); eq('fh_alife_raid_live', err)
end)

case('forceRaid: refuses bad ids and offline owners', function()
    local st = stateWith(HEART)
    eq('fh_alife_bad_plot', select(2, R.forceRaid(ctx, st, nil, claim('A'), true)))
    eq('fh_alife_owner_offline', select(2, R.forceRaid(ctx, st, 'p', claim('A'), {})))
    eq('fh_alife_no_owner', select(2, R.forceRaid(ctx, st, 'p', claim(nil), true)))
end)

-- ---------------------------------------------------------------- lifecycle

local function warned(home)
    local st = stateWith({ HEART[1] })
    local world = { plots = { p1 = claim('CID1') }, online = { CID1 = true }, home = { p1 = home or nil } }
    R.forceRaid(ctx, st, 'p1', world.plots.p1, world.online, seq(4))
    return st, world, st.squads.sq1
end

case('lifecycle home: warn -> fight (owner tag alife_raid) -> withdraw -> return -> removed', function()
    local st, world, sq = warned(true)
    local arrive = sq.etaTick
    same({}, run(st, RC.warnTicks - 1, world, noRng))
    eq('warn', sq.phase)
    local eff = run(st, 1, world, noRng)
    eq(arrive, st.tick)
    same({ 'raid_fight' }, types(eff))
    eq('raid', eff[1].goal); eq('alife_raid', eff[1].owner_tag); eq('p1', eff[1].plot_id); eq(4, eff[1].strength)
    eq('fight', sq.phase); eq('fight', sq.mode); eq(st.tick + RC.fightTicks, sq.etaTick)
    eq(st.tick + RC.fightTicks, eff[1].until_tick)
    same({}, run(st, RC.fightTicks - 1, world, noRng))
    eff = run(st, 1, world, noRng)
    same({ 'raid_withdrew' }, types(eff)); eq('fight_over', eff[1].reason)
    eq('return', sq.phase)
    same({}, run(st, RC.returnTicks - 1, world, noRng))
    eff = run(st, 1, world, noRng)
    same({ 'raid_returned' }, types(eff)); eq('fight', eff[1].mode); eq(nil, eff[1].cancelled)
    eq(nil, st.squads.sq1)
end)

case('lifecycle away: warn -> steal at arrival (no rng in tick) -> return -> removed', function()
    local st, world, sq = warned(false)
    local eff = run(st, RC.warnTicks, world, noRng)
    same({ 'raid_steal' }, types(eff))
    local e = eff[1]
    eq('sq1', e.squad_id); eq('p1', e.plot_id); eq('CID1', e.citizenid); eq(HEART[1], e.camp_id)
    eq('outlaws', e.faction); eq('heartlands', e.region_id); assert(type(e.camp_label) == 'string')
    eq('return', sq.phase); eq('steal', sq.mode)
    eq(0, R.liveRaidCount(st), 'a returning raid is not live')
    eff = run(st, RC.returnTicks, world, noRng)
    same({ 'raid_returned' }, types(eff)); eq('steal', eff[1].mode)
    same({}, R.listRaids(st))
end)

case('owner offline at warn: cancelled, returns, nothing stolen', function()
    local st, world, sq = warned(false)
    run(st, 2, world, noRng)
    world.online = {}
    local eff = run(st, 1, world, noRng)
    same({ 'raid_cancelled' }, types(eff))
    eq('owner_offline', eff[1].reason); eq('warn', eff[1].phase)
    eq('return', sq.phase); eq('owner_offline', sq.cancelled); eq(nil, sq.mode)
    world.online = { CID1 = true } -- back online: the cancelled raid does not resume
    eff = run(st, RC.warnTicks + RC.returnTicks, world, noRng)
    same({ 'raid_returned' }, types(eff)); eq(nil, eff[1].mode); eq('owner_offline', eff[1].cancelled)
end)

case('owner offline mid-fight: cancelled, returns', function()
    local st, world, sq = warned(true)
    run(st, RC.warnTicks, world, noRng)
    eq('fight', sq.phase)
    world.online = {}
    local eff = run(st, 1, world, noRng)
    same({ 'raid_cancelled' }, types(eff)); eq('fight', eff[1].phase); eq('return', sq.phase)
end)

case('owner offline while returning: nothing to cancel', function()
    local st, world, sq = warned(false)
    run(st, RC.warnTicks, world, noRng)
    eq('return', sq.phase)
    world.online = {}
    same({ 'raid_returned' }, types(run(st, RC.returnTicks, world, noRng)))
end)

case('cancel reasons: plot gone, not raidable, owner changed, camp lost (during warn)', function()
    local function check(mutate, reason)
        local st, world, sq = warned(false)
        mutate(st, world)
        local eff = run(st, 1, world, noRng)
        same({ 'raid_cancelled' }, types(eff), reason); eq(reason, eff[1].reason); eq('return', sq.phase)
    end
    check(function(_, w) w.plots = {} end, 'plot_gone')
    check(function(_, w) w.plots.p1 = townLot('CID1') end, 'not_raidable')
    check(function(_, w) w.plots.p1 = claim('CID2'); w.online.CID2 = true end, 'owner_changed')
    check(function(st) st.owners[HEART[1]] = 'lawmen' end, 'camp_lost')
end)

case('FhAlifeRules.tick never advances or resolves raid squads', function()
    local st = warned(false)
    local sq = st.squads.sq1
    sq.etaTick = 0
    Rules.tick(ctx, st, 5, function() return 100 end)
    eq(sq, st.squads.sq1); eq('warn', sq.phase)
end)

-- ---------------------------------------------------------------- repelled

case('repelled: wiping a fighting raid squad adds regionPressure (as a-life-02) and emits raid_repelled', function()
    local st, world, sq = warned(true)
    run(st, RC.warnTicks, world, noRng)
    eq('fight', sq.phase)
    local eff, err = R.onSquadKill(ctx, st, 'sq1')
    eq(nil, err); same({}, eff)
    eq(1, Rules.getPressure(st, 'heartlands', 'outlaws'))
    eff = R.onSquadKill(ctx, st, 'sq1', 3)
    same({ 'squad_wiped', 'raid_repelled' }, types(eff))
    eq('raid', eff[1].goal)
    same({ type = 'raid_repelled', squad_id = 'sq1', plot_id = 'p1', citizenid = 'CID1', camp_id = HEART[1],
        region_id = 'heartlands', faction = 'outlaws' }, eff[2])
    eq(math.min(4, cfg.raids.pressureMax), Rules.getPressure(st, 'heartlands', 'outlaws'))
    eq(nil, st.squads.sq1)
    same({}, run(st, 20, world, noRng), 'nothing left to tick')
    -- non-raid squads pass straight through; a missing squad keeps the a-life-02 error
    eq('fh_alife_no_squad', select(2, R.onSquadKill(ctx, st, 'nope')))
end)

-- ---------------------------------------------------------------- steal pick

case('pickSteal: empty or junk chest -> {} and no rng call', function()
    same({}, R.pickSteal(ctx, {}, noRng))
    same({}, R.pickSteal(ctx, nil, noRng))
    same({}, R.pickSteal(ctx, { [1] = { name = 'x', amount = 0 }, [2] = { amount = 5 }, [3] = 'junk',
        [4] = { name = '', amount = 3 }, foo = { name = 'y', amount = 2 } }, noRng))
end)

case('pickSteal: up to stealStacks stacks, rolls pick then amount, slot order pool', function()
    local chest = { [7] = { name = 'gold', amount = 10, slot = 7 }, [2] = { name = 'ammo', amount = 40, slot = 2 },
        [5] = { name = 'revolver', amount = 1, slot = 5 } }
    -- pool by slot: [ammo(2), revolver(5), gold(7)]; pick 3 -> gold, take 5 (max 5); pick 1 -> ammo, take 20 (max)
    same({ { slot = 7, name = 'gold', amount = 5, of = 10 }, { slot = 2, name = 'ammo', amount = 20, of = 40 } },
        R.pickSteal(ctx, chest, seq(3, 5, 1, 20)))
    -- a 1-item stack: at least 1 wins over the fraction
    same({ { slot = 5, name = 'revolver', amount = 1, of = 1 } },
        R.pickSteal(Rules.context({ claimRaids = { stealStacks = 1 } }, Regions, camps), chest, seq(2, 1)))
    -- fewer stacks than stealStacks: takes what is there
    same({ { slot = 1, name = 'salt', amount = 1, of = 3 } },
        R.pickSteal(ctx, { { name = 'salt', amount = 3 } }, seq(1, 1)))
    -- out-of-range rng values are clamped to the bounds (never more than the fraction)
    same({ { slot = 1, name = 'salt', amount = 1, of = 3 } },
        R.pickSteal(ctx, { { name = 'salt', amount = 3 } }, seq(99, 99)))
end)

case('pickSteal: invariants over 2000 random chests (fraction cap, >= 1, distinct slots, deterministic)', function()
    local gen = lcg(12345)
    for trial = 1, 2000 do
        local chest = {}
        local slots = gen(0, 8)
        for s = 1, slots do
            if gen(1, 4) > 1 then chest[s] = { name = 'item' .. gen(1, 5), amount = gen(1, 60), slot = s } end
        end
        local seed = gen(1, 2147483646)
        local r1, log1 = lcg(seed)
        local r2, log2 = lcg(seed)
        local a = R.pickSteal(ctx, chest, r1)
        local b = R.pickSteal(ctx, chest, r2)
        same(a, b, 'deterministic given the rng (trial ' .. trial .. ')')
        same(log1, log2)
        local stacks = count(chest)
        eq(math.min(RC.stealStacks, stacks), #a, 'pick count')
        eq(2 * #a, #log1, 'two rolls per picked stack, none otherwise')
        local seen = {}
        for _, p in ipairs(a) do
            assert(not seen[p.slot], 'distinct slots'); seen[p.slot] = true
            local src = chest[p.slot]
            eq(src.name, p.name); eq(src.amount, p.of)
            assert(p.amount >= 1, 'at least 1')
            assert(p.amount <= math.max(1, math.floor(src.amount * RC.stealMaxFraction)), 'fraction cap')
        end
    end
end)

-- ---------------------------------------------------------------- save

case('save v3 roundtrip: raid squads and cooldowns survive', function()
    local st, world = warned(true)
    run(st, RC.warnTicks, world, noRng) -- now fighting
    local saved = R.serialize(st)
    eq(3, saved.version); eq(Rules.VERSION, saved.version)
    local st2, err, eff = R.deserialize(saved, ctx, world.plots)
    eq(nil, err); same({}, eff)
    same(st.squads, st2.squads); same(st.raidCooldowns, st2.raidCooldowns); eq(st.tick, st2.tick)
    eq(st.nextSquadId, st2.nextSquadId)
    -- and it keeps running after the load
    same({ 'raid_withdrew' }, types(run(st2, RC.fightTicks, world, noRng)))
end)

case('a-life-02 v2 and a-life-01 v1 saves still load (no raids, no cooldowns)', function()
    local v2 = { version = 2, tick = 40, nextSquadId = 5, owners = { [HEART[1]] = 'lawmen' },
        regionPressure = { heartlands = { outlaws = 2 } },
        squads = { sq4 = { id = 'sq4', goal = 'reinforce', faction = 'lawmen', strength = 2, from = 'heartlands',
            to = HEART[1], region = 'heartlands', phase = 'hold', travel = 3, etaTick = 45 } } }
    local st, err, eff = R.deserialize(v2, ctx, {})
    eq(nil, err); same({}, eff)
    eq(40, st.tick); eq(2, st.squads.sq4.strength); same({}, st.raidCooldowns); same({}, R.listRaids(st))
    eq(2, Rules.getPressure(st, 'heartlands', 'outlaws'))
    local v1 = { version = 1, tick = 7, nextSquadId = 2, owners = { [HEART[1]] = 'lawmen' },
        squads = { sq1 = { id = 'sq1', faction = 'outlaws', strength = 4, from = 'heartlands', to = HEART[1],
            etaTick = 22, goal = 'retake' } } }
    st, err, eff = R.deserialize(v1, ctx)
    eq(nil, err); same({}, eff); eq(4, st.squads.sq1.strength); same({}, st.raidCooldowns)
    eq(3, R.serialize(st).version)
    -- a loaded old save raids normally
    same({ 'raid_warned' }, types(R.tick(ctx, st, { plots = { p1 = claim('A') },
        online = { A = true } }, seq(1, 3))))
end)

case('load drops raids whose plot or camp is gone (no error), keeps the rest', function()
    local st = stateWith(HEART)
    local plots = { p1 = claim('A'), p2 = claim('B'), p3 = claim('C') }
    R.forceRaid(ctx, st, 'p1', plots.p1, true, seq(3)) -- sq1
    R.forceRaid(ctx, st, 'p2', plots.p2, true, seq(3)) -- sq2
    R.forceRaid(ctx, st, 'p3', plots.p3, true, seq(3)) -- sq3
    st.squads.sq3.from = 'camp_removed_from_config'
    local saved = R.serialize(st)
    local now = { p1 = claim('A'), p2 = townLot('B') } -- p2 became a town lot, p3 vanished too
    local st2, err, eff = R.deserialize(saved, ctx, now)
    eq(nil, err)
    eq('sq1', R.listRaids(st2)[1].id); eq(1, #R.listRaids(st2))
    table.sort(eff, function(a, b) return a.squad_id < b.squad_id end)
    same({ { type = 'raid_dropped', reason = 'plot_missing', squad_id = 'sq2', plot_id = 'p2', camp_id = HEART[1] },
        { type = 'raid_dropped', reason = 'camp_missing', squad_id = 'sq3', plot_id = 'p3',
            camp_id = 'camp_removed_from_config' } }, eff)
    eq(3, count(st2.raidCooldowns), 'cooldowns stay')
    -- unclaimed plot (no owner) is gone too; without plots only camp/shape checks run
    local st3, _, eff3 = R.deserialize(saved, ctx, { p1 = claim(nil), p2 = claim('B') })
    eq(2, #eff3); eq('sq2', R.listRaids(st3)[1].id)
    local st4, _, eff4 = R.deserialize(saved, ctx)
    eq(1, #eff4); eq(2, #R.listRaids(st4))
end)

case('load drops malformed raids and junk cooldowns', function()
    local base = { id = 'r', goal = 'raid', faction = 'outlaws', strength = 3, from = HEART[1], to = 'p1', plot = 'p1',
        region = 'heartlands', citizenid = 'A', phase = 'warn', travel = 3, etaTick = 5 }
    local function with(k, v) local c = {} for a, b in pairs(base) do c[a] = b end c[k] = v return c end
    local bads = { with('phase', 'dance'), with('plot', nil), with('citizenid', 7), with('region', nil),
        with('mode', 'party'), with('to', 'other') }
    local squads = {}
    for i, b in ipairs(bads) do b.id = 'b' .. i squads[b.id] = b end
    local good = with('strength', -4); good.id = 'g'; good.travel = 0 / 0; good.cancelled = 12
    squads.g = good
    local st, err, eff = R.deserialize({ version = 3, tick = 1, squads = squads,
        raidCooldowns = { p1 = 200, p2 = 'soon', [3] = 10, p4 = -1, p5 = 0 / 0 } }, ctx, { p1 = claim('A') })
    eq(nil, err)
    eq(#bads, #eff)
    for _, e in ipairs(eff) do eq('bad_shape', e.reason) end
    same({ 'g' }, (function() local o = {} for _, s in ipairs(R.listRaids(st)) do o[#o + 1] = s.id end return o end)())
    eq(0, st.squads.g.strength); eq(1, st.squads.g.travel); eq(nil, st.squads.g.cancelled)
    same({ p1 = 200 }, st.raidCooldowns)
    eq('fh_alife_version', select(2, R.deserialize({ version = 99 }, ctx)))
    eq('fh_alife_bad_state', select(2, R.deserialize(nil, ctx)))
end)

case('describeRaid: one /alife line', function()
    local st = warned(false)
    local line = R.describeRaid(ctx, st.squads.sq1)
    assert(line:find('^sq1 raid p1 by outlaws x4 from .+ warn %(eta tick %d+%)$'), line)
end)

-- ---------------------------------------------------------------- C2c loot ledger
-- Implemented A-Life — Thanks to S.T.A.L.K.E.R. A-Life by GSC Game World.

local function names(list) local o = {} for _, e in ipairs(list or {}) do o[#o + 1] = e.name end return o end

case('C2c ledger: lootAdd appends oldest-first, serialize round trip (restart), lootTake empties it', function()
    local st = Rules.newState()
    eq(true, (R.lootAdd(ctx, st, HEART[1], { name = 'bread', amount = 2 })))
    eq(true, (R.lootAdd(ctx, st, HEART[1], { name = 'rope', amount = 1, info = { q = 7 } })))
    eq(true, (R.lootAdd(ctx, st, HEART[2], { name = 'gold', amount = 1 })))
    eq(2, R.lootCount(st, HEART[1])); eq(0, R.lootCount(st, 'nope'))
    eq('raid loot: ' .. HEART[1] .. '=2 ' .. HEART[2] .. '=1', R.describeLoot(st))
    local st2, err = R.deserialize(R.serialize(st), ctx)
    eq(nil, err)
    same(st.raidLoot, st2.raidLoot)
    same({ { name = 'bread', amount = 2 }, { name = 'rope', amount = 1, info = { q = 7 } } }, R.lootTake(st2, HEART[1]))
    eq(0, R.lootCount(st2, HEART[1]))
    same({}, R.lootTake(st2, HEART[1]), 'a second take gets nothing')
    eq('raid loot: ' .. HEART[2] .. '=1', R.describeLoot(st2))
    eq(nil, R.serialize(st2).raidLoot[HEART[1]], 'emptied ledger is not saved')
    eq('raid loot: none', R.describeLoot(Rules.newState()))
end)

case('C2c ledger: cap lootStacksMax per camp drops the oldest first (returned for logging)', function()
    eq(20, RC.lootStacksMax); eq(20, R.DEFAULTS.lootStacksMax)
    local st = Rules.newState()
    for i = 1, 20 do
        local ok, _, dropped = R.lootAdd(ctx, st, HEART[1], { name = 'i' .. i, amount = 1 })
        eq(true, ok); same({}, dropped)
    end
    local ok, _, dropped = R.lootAdd(ctx, st, HEART[1], { name = 'i21', amount = 3 })
    eq(true, ok)
    same({ { name = 'i1', amount = 1 } }, dropped)
    eq(20, R.lootCount(st, HEART[1]))
    eq('i2', st.raidLoot[HEART[1]][1].name); eq('i21', st.raidLoot[HEART[1]][20].name)
    eq(0, R.lootCount(st, HEART[2]), 'cap is per camp')
end)

case('C2c ledger: bad entries refused (nothing recorded); lootRestore puts entries back in front', function()
    local st = Rules.newState()
    for _, bad in ipairs({ { name = '', amount = 1 }, { name = 'x', amount = 0 }, { name = 'x', amount = 0 / 0 },
        { amount = 2 }, 'junk' }) do
        local ok, err, dropped = R.lootAdd(ctx, st, HEART[1], bad)
        eq(false, ok); eq('fh_alife_bad_loot', err); same({}, dropped)
    end
    eq('fh_alife_bad_camp', select(2, R.lootAdd(ctx, st, nil, { name = 'x', amount = 1 })))
    eq(0, R.lootCount(st, HEART[1]))
    R.lootAdd(ctx, st, HEART[1], { name = 'new', amount = 1 })
    same({}, R.lootRestore(ctx, st, HEART[1], { { name = 'a', amount = 1 }, { name = 'b', amount = 2 } }))
    same({ 'a', 'b', 'new' }, names(st.raidLoot[HEART[1]]))
end)

case('C2c ledger: a v3 save without raidLoot (C1/C2) loads with an empty ledger; junk entries dropped', function()
    local st, err = R.deserialize({ version = 3, tick = 5, owners = {}, squads = {}, raidCooldowns = {} }, ctx)
    eq(nil, err); same({}, st.raidLoot)
    R.lootAdd(ctx, st, HEART[1], { name = 'bread', amount = 1 })
    eq(1, R.lootCount(st, HEART[1]), 'old save then raids normally')
    local st2 = R.deserialize({ version = 3, raidLoot = { [HEART[1]] = { { name = 'ok', amount = 2.5 },
        { name = 'bad', amount = -1 }, 'junk', { name = 'info', amount = 1, info = 'str' } },
        [HEART[2]] = { { amount = 1 } }, [7] = { { name = 'num', amount = 1 } }, [''] = { { name = 'empty', amount = 1 } },
        x = 'notalist' } }, ctx)
    same({ [HEART[1]] = { { name = 'ok', amount = 2 }, { name = 'info', amount = 1 } } }, st2.raidLoot)
    eq(nil, st2.raidLoot[''], 'empty campId rejected on deserialize')
    local st3 = R.deserialize({ version = 2, tick = 1 }, ctx)
    same({}, st3.raidLoot)
end)

case('C2c ledger: lootAdd sanitises info (JSON-safe copy: drops fn/thread/NaN, string keys only, depth/cycle limit)', function()
    local st = Rules.newState()
    local deep = { l1 = { l2 = { l3 = { l4 = { ok6 = true, l5 = { tooDeep = 1 } } } } } }
    local cyc = { keep = 'yes' }; cyc.self = cyc
    local srcInfo = {
        q = 2,
        flag = true,
        label = 'worn',
        fn = function() end,
        th = coroutine.create(function() end),
        nan = 0 / 0,
        inf = math.huge,
        [1] = 'numkey',
        [true] = 'boolkey',
        [{}] = 'tblkey',
        nested = deep,
        cyc = cyc,
    }
    local ok, err = R.lootAdd(ctx, st, HEART[1], { name = 'rifle', amount = 1, info = srcInfo })
    eq(true, ok); eq(nil, err)
    local got = st.raidLoot[HEART[1]][1].info
    same({
        q = 2,
        flag = true,
        label = 'worn',
        nested = { l1 = { l2 = { l3 = { l4 = { ok6 = true } } } } },
        cyc = { keep = 'yes' },
    }, got)
    -- deep copy: mutating source info does not mutate the ledger
    srcInfo.q = 999
    eq(2, st.raidLoot[HEART[1]][1].info.q)
    -- all-junk info collapses to nil
    R.lootAdd(ctx, st, HEART[1], { name = 'junk_info', amount = 1, info = { fn = function() end, [1] = 'x' } })
    eq(nil, st.raidLoot[HEART[1]][2].info)
end)

case('C2c ledger: deserialize trims each camp ledger to lootStacksMax, oldest dropped', function()
    local big = {}
    for i = 1, 25 do big[i] = { name = 'i' .. i, amount = 1 } end
    local st, err = R.deserialize({ version = 3, raidLoot = { [HEART[1]] = big } }, ctx)
    eq(nil, err)
    eq(20, R.lootCount(st, HEART[1]))
    eq('i6', st.raidLoot[HEART[1]][1].name)
    eq('i25', st.raidLoot[HEART[1]][20].name)
    -- custom cap via ctx
    local smallCtx = Rules.context({ claimRaids = { lootStacksMax = 3 } }, Regions, camps)
    local st2 = R.deserialize({ version = 3, raidLoot = { [HEART[1]] = {
        { name = 'a', amount = 1 }, { name = 'b', amount = 1 }, { name = 'c', amount = 1 },
        { name = 'd', amount = 1 }, { name = 'e', amount = 1 },
    } } }, smallCtx)
    same({ 'c', 'd', 'e' }, names(st2.raidLoot[HEART[1]]))
end)

T.finish()
