-- Run from repo root: `lua spec/spawn_rules_spec.lua` (or via busted / tools/run-specs.py).
-- Spawn-request state machine (fh_core shared/spawn_rules.lua). Invariant under test: one live entity per requestId.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local case = T.it
local R = require('spawn_rules')

local function spec(over)
    local s = { kind = 'horse', model = 'a_c_horse_morgan_bay', coords = { x = 10, y = 20, z = 30 }, heading = 90,
        owner = { kind = 'admin', id = 1 }, tag = 't' }
    for k, v in pairs(over or {}) do s[k] = v end
    return s
end

local function newReq(retries, specOver)
    local s = assert(R.validateSpec(spec(specOver)))
    local o = assert(R.validateOpts({ retries = retries or 1, timeoutMs = 1000 }))
    return R.newRequest(7, s, o)
end

local function info(req, over)
    local i = { exists = true, model = req.spec.modelHash, coords = { x = 10, y = 20, z = 30 }, owner = req.spawner }
    for k, v in pairs(over or {}) do i[k] = v end
    return i
end

-- dispatch to `id` with `tok`, then accept `created` and pass the entity check
local function adoptVia(req, id, tok, netId)
    assert(R.dispatch(req, id, tok, 0))
    T.eq('verify', R.onCreated(req, id, tok, netId))
    T.eq('adopted', R.finishVerify(req, tok, R.checkEntity(req, info(req)), nil, 100 + netId))
end

case('joaat matches the known GetHashKey value and modelHash normalises sign', function()
    T.eq(0xB779A091, R.joaat('adder'))
    T.eq(0xB779A091, R.joaat('ADDER'))
    T.eq(0xB779A091, R.modelHash(-1216765807)) -- signed form of 0xB779A091
    T.eq(0xB779A091, R.modelHash('-1216765807'))
    T.eq(nil, R.modelHash(1.5))
end)

case('validateSpec: kinds, vehicles refused, coords/heading/owner/tag checks', function()
    local s = assert(R.validateSpec(spec()))
    T.eq('horse', s.kind); T.eq(R.joaat('a_c_horse_morgan_bay'), s.modelHash); T.eq(90.0, s.heading)
    T.same({ kind = 'admin', id = 1 }, s.owner)
    local function code(o) local _, e = R.validateSpec(spec(o)) return e end
    T.eq('fh_spawn_kind_unsupported', code({ kind = 'vehicle' }))
    T.eq('wagon', assert(R.validateSpec(spec({ kind = 'wagon' }))).kind, 'wagon accepted (B7)')
    T.eq('fh_spawn_bad_kind', code({ kind = 'tank' }))
    T.eq('fh_spawn_bad_model', code({ model = '' }))
    T.eq('fh_spawn_bad_model', code({ model = {} }))
    T.eq('fh_spawn_bad_coords', code({ coords = { x = 1, y = 0 / 0, z = 0 } }))
    T.eq('fh_spawn_bad_heading', code({ heading = math.huge }))
    T.eq('fh_spawn_bad_owner', code({ owner = { id = 1 } }))
    T.eq('fh_spawn_bad_tag', code({ tag = 5 }))
    T.eq('fh_spawn_bad_spec', select(2, R.validateSpec(nil)))
end)

case('validateSpec: vec4-like coords give the heading; no owner -> system', function()
    local s = assert(R.validateSpec({ kind = 'object', model = 123, coords = { x = 1, y = 2, z = 3, w = 450 } }))
    T.eq(90.0, s.heading); T.same({ x = 1.0, y = 2.0, z = 3.0 }, s.coords)
    T.same({ kind = 'system', id = 0 }, s.owner)
end)

case('validateSpec: snap defaults true; snap == false is preserved as the opt-out', function()
    T.eq(true, assert(R.validateSpec(spec())).snap)
    T.eq(true, assert(R.validateSpec(spec({ snap = true }))).snap)
    T.eq(false, assert(R.validateSpec(spec({ snap = false }))).snap)
end)

case('validateOpts: defaults from config then DEFAULTS; bad values refused', function()
    local o = assert(R.validateOpts(nil, { Retries = 5 }))
    T.eq(5, o.retries); T.eq(R.DEFAULTS.TimeoutMs, o.timeoutMs)
    T.eq('fh_spawn_bad_retries', select(2, R.validateOpts({ retries = -1 })))
    T.eq('fh_spawn_bad_retries', select(2, R.validateOpts({ retries = 1.5 })))
    T.eq('fh_spawn_bad_timeout', select(2, R.validateOpts({ timeoutMs = 0 })))
    T.eq('fh_spawn_bad_coords', select(2, R.validateOpts({ near = { x = 1 } })))
end)

case('parseFlag: true/false spellings, unknown -> default', function()
    T.eq(true, R.parseFlag('true', false)); T.eq(true, R.parseFlag('1', false))
    T.eq(false, R.parseFlag('false', true)); T.eq(false, R.parseFlag('0', true)); T.eq(false, R.parseFlag('OFF', true))
    T.eq(true, R.parseFlag('', true)); T.eq(true, R.parseFlag(nil, true)); T.eq(true, R.parseFlag('maybe', true))
end)

case('transition: only listed moves; terminal states are final', function()
    local req = newReq()
    T.eq(false, (R.transition(req, 'adopted')))
    T.eq('pending', req.state)
    for to in pairs(R.TRANSITIONS) do
        T.eq(nil, R.TRANSITIONS.failed[to]); T.eq(nil, R.TRANSITIONS.despawned[to])
    end
end)

case('pickSpawner: nearest in range, untried first, fallback, none', function()
    local near = { x = 0, y = 0, z = 0 }
    local c = { { id = 1, coords = { x = 50, y = 0, z = 0 } }, { id = 2, coords = { x = 10, y = 0, z = 0 } },
        { id = 3, coords = { x = 900, y = 0, z = 0 } }, { id = 4 } }
    T.same({ 2, 'in_range' }, { R.pickSpawner(c, near, 300, true) })
    T.same({ 1, 'in_range' }, { R.pickSpawner(c, near, 300, true, { [2] = true }) })
    T.same({ 2, 'in_range' }, { R.pickSpawner(c, near, 300, true, { [1] = true, [2] = true }) }, 'tried in range beats out of range')
    local far = { { id = 3, coords = { x = 900, y = 0, z = 0 } }, { id = 4 } }
    T.same({ 3, 'fallback' }, { R.pickSpawner(far, near, 300, true) })
    T.eq(nil, R.pickSpawner(far, near, 300, false), 'no fallback: park')
    T.eq(nil, R.pickSpawner({}, near, 300, true), 'no players: park')
    T.same({ 5, 'in_range' }, { R.pickSpawner({ { id = 6, coords = near }, { id = 5, coords = near } }, near, 300) }, 'tie -> lower id')
end)

case('no-client park: pending_no_client, no attempt used, dispatches later', function()
    local req = newReq(0)
    assert(R.park(req))
    T.eq('pending_no_client', req.state); T.eq(0, req.attempts)
    assert(R.dispatch(req, 3, 'tok', 0))
    T.eq('dispatched', req.state); T.eq(1, req.attempts); T.eq(1000, req.deadline)
end)

case('happy path: created -> verify -> adopted', function()
    local req = newReq()
    adoptVia(req, 3, 'tok', 55)
    T.eq('adopted', req.state); T.eq(55, req.netId); T.eq(155, req.entity); T.eq(3, req.spawner)
end)

case('timeout -> retry with the next candidate, then failed when retries run out', function()
    local req = newReq(1)
    assert(R.dispatch(req, 3, 'a', 0))
    T.eq(nil, R.checkTimeout(req, 999))
    T.eq('retry', R.checkTimeout(req, 1000))
    T.eq('pending', req.state); T.eq(3, req.staleTokens.a)
    local cands = { { id = 3, coords = { x = 10, y = 20, z = 30 } }, { id = 4, coords = { x = 60, y = 20, z = 30 } } }
    T.eq(4, (R.pickSpawner(cands, req.near, 300, true, req.tried)), 'next candidate, not the one that timed out')
    assert(R.dispatch(req, 4, 'b', 2000))
    T.eq('failed', R.checkTimeout(req, 3000))
    T.eq('failed', req.state); T.eq('fh_spawn_timeout', req.failReason)
    T.eq(false, (R.dispatch(req, 5, 'c', 0)), 'failed is terminal')
end)

case('late created after a timeout is stale: deleted, never adopted (exactly-once)', function()
    local req = newReq(2)
    assert(R.dispatch(req, 3, 'a', 0))
    R.checkTimeout(req, 1000)
    adoptVia(req, 4, 'b', 60)
    T.eq('stale', R.onCreated(req, 3, 'a', 99))
    T.eq('adopted', req.state); T.eq(60, req.netId)
end)

case('spawner drop mid-dispatch -> retry; other players dropping change nothing', function()
    local req = newReq(1)
    assert(R.dispatch(req, 3, 'a', 0))
    T.eq(nil, R.onPlayerDropped(req, 9, true))
    T.eq('dispatched', req.state)
    T.eq('retry', R.onPlayerDropped(req, 3, true))
    T.eq('pending', req.state); T.eq(nil, req.tried[3])
end)

case('spawner drop while verifying -> retry; the verify that finishes later is discarded', function()
    local req = newReq(1)
    assert(R.dispatch(req, 3, 'a', 0))
    T.eq('verify', R.onCreated(req, 3, 'a', 55))
    T.eq('retry', R.onPlayerDropped(req, 3, true))
    T.same({ nil, 'fh_spawn_stale_verify' }, { R.finishVerify(req, 'a', true, nil, 155) })
    T.eq('pending', req.state); T.eq(nil, req.netId)
end)

case('owner drop after adopt: gated -> despawn + re-request (fresh cycle); ungated -> keep', function()
    local req = newReq(0)
    adoptVia(req, 3, 'a', 55)
    T.eq('despawn_rerequest', R.onPlayerDropped(req, 3, true))
    T.eq('pending', req.state); T.eq(0, req.attempts); T.eq(nil, req.netId); T.eq(nil, req.entity)
    T.eq('stale', R.onCreated(req, 3, 'a', 55), 'old token cannot re-adopt')
    local u = newReq(0)
    adoptVia(u, 3, 'a', 55)
    T.eq('keep', R.onPlayerDropped(u, 3, false))
    T.eq('adopted', u.state); T.eq(55, u.netId)
    local o = newReq(0)
    adoptVia(o, 3, 'a', 55)
    T.eq('despawn_rerequest', R.onPlayerDropped(o, 8, true, 8), 'current network owner dropping counts too')
end)

case('duplicate created for the same request: extra entity deleted, adopted one kept', function()
    local req = newReq()
    assert(R.dispatch(req, 3, 'a', 0))
    T.eq('verify', R.onCreated(req, 3, 'a', 55))
    T.eq('duplicate', R.onCreated(req, 3, 'a', 56), 'while verifying')
    T.eq('adopted', R.finishVerify(req, 'a', true, nil, 155))
    T.eq('duplicate', R.onCreated(req, 3, 'a', 57), 'after adoption')
    T.eq('same', R.onCreated(req, 3, 'a', 55), 'same netId resent: no-op')
    T.eq('adopted', req.state); T.eq(55, req.netId)
end)

case('wrong source / wrong token / unknown request: rejected, state unchanged', function()
    local req = newReq()
    assert(R.dispatch(req, 3, 'a', 0))
    T.eq('wrong_source', R.onCreated(req, 4, 'a', 55))
    T.eq('wrong_token', R.onCreated(req, 3, 'zzz', 55))
    T.eq('wrong_token', R.onCreated(req, 3, nil, 55))
    T.eq('wrong_source', R.onCreated(req, 4, 'zzz', 55))
    T.eq('dispatched', req.state); T.eq(nil, req.netId)
    T.eq('unknown', R.onCreated(nil, 3, 'a', 55))
    R.checkTimeout(req, 1000)
    T.eq('wrong_source', R.onCreated(req, 4, 'a', 55), 'stale token from someone else is not theirs to delete')
end)

case('client-reported failure: only current spawner + token, then retry', function()
    local req = newReq(1)
    assert(R.dispatch(req, 3, 'a', 0))
    T.eq('fh_spawn_wrong_source', select(2, R.onClientFailed(req, 4, 'a', 'x')))
    T.eq('fh_spawn_wrong_token', select(2, R.onClientFailed(req, 3, 'b', 'x')))
    T.eq('retry', R.onClientFailed(req, 3, 'a', 'model_timeout'))
    T.eq('fh_spawn_client:model_timeout', req.lastReason)
end)

case('checkEntity: no entity, model mismatch (signed hash ok), out of range', function()
    local req = newReq()
    assert(R.dispatch(req, 3, 'a', 0))
    T.eq(true, (R.checkEntity(req, info(req), 25)))
    local signed = req.spec.modelHash >= 0x80000000 and req.spec.modelHash - 0x100000000 or req.spec.modelHash
    T.eq(true, (R.checkEntity(req, info(req, { model = signed }), 25)), 'GetEntityModel signed form')
    T.eq('fh_spawn_no_entity', select(2, R.checkEntity(req, info(req, { exists = false }), 25)))
    T.eq('fh_spawn_model_mismatch', select(2, R.checkEntity(req, info(req, { model = R.joaat('other') }), 25)))
    T.eq('fh_spawn_out_of_range', select(2, R.checkEntity(req, info(req, { coords = { x = 10, y = 60, z = 30 } }), 25)))
    T.eq('fh_spawn_out_of_range', select(2, R.checkEntity(req, info(req, { coords = 'junk' }), 25)))
end)

case('verify mismatch -> retry with a new attempt; the rejected token cannot adopt later', function()
    local req = newReq(1)
    assert(R.dispatch(req, 3, 'a', 0))
    T.eq('verify', R.onCreated(req, 3, 'a', 55))
    local ok, why = R.checkEntity(req, info(req, { model = 1 }), 25)
    T.eq('retry', R.finishVerify(req, 'a', ok, why))
    T.eq('fh_spawn_model_mismatch', req.lastReason)
    T.eq('stale', R.onCreated(req, 3, 'a', 55))
    T.eq('pending', req.state)
end)

case('exactly-once: whatever arrives, at most one adoption per request', function()
    local req = newReq(3)
    local adopted = 0
    local events = {
        function() R.dispatch(req, 3, 'a', 0) end,
        function() if R.onCreated(req, 3, 'a', 1) == 'verify' then R.finishVerify(req, 'a', false, 'fh_spawn_no_entity') end end,
        function() R.dispatch(req, 4, 'b', 0) end,
        function() R.checkTimeout(req, 5000) end,
        function() R.dispatch(req, 5, 'c', 0) end,
        function() if R.onCreated(req, 4, 'b', 2) == 'verify' then adopted = adopted + 1 end end,
        function() if R.onCreated(req, 5, 'c', 3) == 'verify' then
            if R.finishVerify(req, 'c', true, nil, 103) == 'adopted' then adopted = adopted + 1 end end end,
        function() if R.onCreated(req, 5, 'c', 4) == 'verify' then adopted = adopted + 1 end end,
        function() if R.onCreated(req, 3, 'a', 5) == 'verify' then adopted = adopted + 1 end end,
    }
    for _, e in ipairs(events) do e() end
    T.eq(1, adopted); T.eq('adopted', req.state); T.eq(3, req.netId)
end)

case('despawn: from adopted returns the entity; from dispatched returns the in-flight token; terminal after', function()
    local req = newReq()
    adoptVia(req, 3, 'a', 55)
    local d = assert(R.despawn(req))
    T.eq(55, d.netId); T.eq(155, d.entity); T.eq('despawned', req.state)
    T.eq('fh_spawn_not_live', select(2, R.despawn(req)))
    T.eq('unknown', R.onCreated(req, 3, 'a', 55), 'late created after despawn is deleted')
    local f = newReq()
    assert(R.dispatch(f, 4, 'b', 0))
    local d2 = assert(R.despawn(f))
    T.eq('b', d2.token); T.eq(4, d2.spawner); T.eq(nil, d2.netId)
    T.eq(nil, R.checkTimeout(f, 99999), 'no retry after despawn')
end)

case('entity gone after adopt -> re-request as a fresh cycle', function()
    local req = newReq(0)
    adoptVia(req, 3, 'a', 55)
    T.eq('rerequest', R.rerequest(req, 'fh_spawn_entity_gone'))
    T.eq('pending', req.state); T.eq(0, req.attempts)
    adoptVia(req, 3, 'b', 56)
    T.eq(56, req.netId)
    T.eq('fh_spawn_bad_transition', select(2, R.rerequest(newReq(), 'x')), 'only from adopted')
end)

case('offsetForward: heading 0 is +y, 90 is -x', function()
    local p = R.offsetForward({ x = 0, y = 0, z = 1 }, 0, 2)
    assert(math.abs(p.x) < 1e-9 and math.abs(p.y - 2) < 1e-9 and p.z == 1)
    local q = R.offsetForward({ x = 0, y = 0, z = 1 }, 90, 2)
    assert(math.abs(q.x + 2) < 1e-9 and math.abs(q.y) < 1e-9)
end)

-- Review rn-5638a710a250 (Gemini) on 33a65cd. Each HIGH case below fails on 33a65cd.

case('HIGH-1 duplicate created: delete targets only the extra netId, never the live one', function()
    local req = newReq()
    assert(R.dispatch(req, 3, 'a', 0))
    T.eq('verify', (R.onCreated(req, 3, 'a', 55)))
    T.same({ 'duplicate', 56 }, { R.onCreated(req, 3, 'a', 56) }, 'while verifying')
    T.eq('adopted', (R.finishVerify(req, 'a', true, nil, 155)))
    T.same({ 'duplicate', 57 }, { R.onCreated(req, 3, 'a', 57) }, 'after adoption')
    T.same({ 'same' }, { R.onCreated(req, 3, 'a', 55) }, 'live netId: no delete')
    local r2 = newReq(1)
    adoptVia(r2, 3, 'a', 55)
    R.rerequest(r2, 'x')
    adoptVia(r2, 4, 'b', 66)
    T.same({ 'stale', 55 }, { R.onCreated(r2, 3, 'a', 55) }, 'stale: delete the old entity')
    T.same({ 'same' }, { R.onCreated(r2, 3, 'a', 66) }, 'stale token naming the live netId: no delete')
end)

case('HIGH-2 checkEntity: refuses an entity the spawner does not own, another request holds, or a player ped', function()
    local req = newReq()
    assert(R.dispatch(req, 3, 'a', 0))
    T.eq('fh_spawn_not_owner', select(2, R.checkEntity(req, info(req, { owner = 9 }), 25)), "someone else's horse")
    T.eq('fh_spawn_not_owner', select(2, R.checkEntity(req, info(req, { owner = false }), 25)), 'owner unknown')
    T.eq('fh_spawn_already_claimed', select(2, R.checkEntity(req, info(req, { claimedBy = 2 }), 25)))
    T.eq('fh_spawn_player_entity', select(2, R.checkEntity(req, info(req, { isPlayer = true }), 25)))
    local other = newReq()
    adoptVia(other, 4, 'b', 55)
    local all = { [7] = req, [8] = other }
    T.eq(8, R.findClaim(all, 55, 7), 'netId 55 belongs to request 8')
    T.eq(nil, R.findClaim(all, 55, 8), 'own request is not a claim')
    T.eq(nil, R.findClaim(all, 99, 7))
    R.despawn(other)
    T.eq(nil, R.findClaim(all, 55, 7), 'despawned requests hold nothing')
end)

case('HIGH-3 spawner drop / verify timeout while verifying: in-flight netId handed back for cleanup', function()
    local req = newReq(2)
    assert(R.dispatch(req, 3, 'a', 0))
    T.eq('verify', (R.onCreated(req, 3, 'a', 55)))
    R.noteOwner(req, 'a', 3)
    local outcome, inflight = R.onPlayerDropped(req, 3, true)
    T.eq('retry', outcome)
    T.same({ netId = 55, token = 'a', spawner = 3, seenOwned = true }, inflight)
    local function ent(over)
        local i = { exists = true, model = req.spec.modelHash }
        for k, v in pairs(over or {}) do i[k] = v end
        return i
    end
    T.eq(true, R.canCleanup(req, inflight, ent()), 'ours: delete it, else OneSync may migrate it (2 live)')
    T.eq(false, R.canCleanup(req, inflight, ent({ claimedBy = 9 })), 'another request holds it')
    T.eq(false, R.canCleanup(req, inflight, ent({ model = 1 })), 'not our model')
    T.eq(false, R.canCleanup(req, inflight, ent({ exists = false })))
    local unseen = { netId = 55, spawner = 3, seenOwned = false }
    T.eq(false, R.canCleanup(req, unseen, ent({ owner = 8 })), 'never seen owned by the spawner: not ours to delete')
    T.eq(true, R.canCleanup(req, unseen, ent({ owner = 3 })), 'still owned by the dropped spawner')
    assert(R.dispatch(req, 4, 'b', 0))
    T.eq('verify', (R.onCreated(req, 4, 'b', 66, 100, 500)))
    T.eq(nil, (R.checkTimeout(req, 599)))
    local o2, inf2 = R.checkTimeout(req, 600)
    T.eq('retry', o2); T.eq(66, inf2.netId); T.eq('fh_spawn_verify_timeout', req.lastReason)
    T.eq(nil, select(2, R.onPlayerDropped(newReq(), 3, true)), 'nothing in flight: nothing to clean')
end)

case('HIGH-3 despawn while verifying returns the in-flight entity, not an adopted one', function()
    local req = newReq()
    assert(R.dispatch(req, 3, 'a', 0))
    R.onCreated(req, 3, 'a', 55)
    local d = assert(R.despawn(req))
    T.eq(nil, d.netId); T.eq(55, d.inflight.netId)
end)

case('MED-4 modelHash: no crash on huge/inf/fractional numbers; out-of-range hashes refused', function()
    T.eq(nil, R.modelHash('1e100')); T.eq(nil, R.modelHash(1e100)); T.eq(nil, R.modelHash(math.huge))
    T.eq(nil, R.modelHash(0 / 0)); T.eq(nil, R.modelHash('1.5')); T.eq(nil, R.modelHash(0x100000000))
    T.eq(R.joaat('inf'), R.modelHash('inf'), "Lua's tonumber rejects 'inf': it is a (silly) model name")
    T.eq(0xFFFFFFFF, R.modelHash(-1))
    T.eq('fh_spawn_bad_model', select(2, R.validateSpec(spec({ model = '1e100' }))))
end)

case('MED-5 netId must be a positive integer; verifying cannot wedge', function()
    T.eq(5, R.validNetId(5)); T.eq(5, R.validNetId(5.0))
    for _, bad in ipairs({ 0, -1, 1.5, 0 / 0, math.huge, '5', 1e100 }) do T.eq(nil, R.validNetId(bad), tostring(bad)) end
    local req = newReq()
    assert(R.dispatch(req, 3, 'a', 0))
    T.eq('bad_netid', (R.onCreated(req, 3, 'a', 0 / 0)))
    T.eq('bad_netid', (R.onCreated(req, 3, 'a', math.huge)))
    T.eq('dispatched', req.state, 'ignored; the dispatch timeout still applies')
    T.eq('retry', (R.checkTimeout(req, 1000)))
end)

case('B7 wagon: CREATE/isPedKind map; wagon request pending -> dispatched -> verifying -> adopted', function()
    T.eq('vehicle', R.CREATE.wagon); T.eq('ped', R.CREATE.horse); T.eq('ped', R.CREATE.ped); T.eq('object', R.CREATE.object)
    assert(R.isPedKind('horse') and R.isPedKind('ped'), 'peds are IsPedAPlayer-checked')
    assert(not R.isPedKind('wagon') and not R.isPedKind('object'), 'wagon/object never player peds')
    assert(not R.isPedKind('vehicle') and not R.isPedKind(nil), 'unknown kinds are not peds')
    for k in pairs(R.KINDS) do assert(R.CREATE[k], 'every accepted kind has a create native: ' .. k) end
    local req = newReq(1, { kind = 'wagon', model = 'cart01' })
    T.eq('wagon', req.spec.kind); T.eq(R.joaat('cart01'), req.spec.modelHash)
    T.eq('pending', req.state)
    assert(R.dispatch(req, 4, 'w', 0)); T.eq('dispatched', req.state)
    T.eq('verify', R.onCreated(req, 4, 'w', 77)); T.eq('verifying', req.state)
    T.eq('adopted', R.finishVerify(req, 'w', R.checkEntity(req, info(req)), nil, 177))
    T.eq('adopted', req.state); T.eq(77, req.netId); T.eq(177, req.entity)
end)

case('B7 wagon: gated owner drop -> despawn_rerequest (fresh cycle at the spawn point); ungated -> keep', function()
    local req = newReq(0, { kind = 'wagon', model = 'cart01' })
    adoptVia(req, 3, 'a', 55)
    T.eq('despawn_rerequest', R.onPlayerDropped(req, 3, true))
    T.eq('pending', req.state); T.eq(0, req.attempts); T.eq(nil, req.netId); T.eq(nil, req.entity)
    T.same({ x = 10, y = 20, z = 30 }, req.spec.coords, 're-request keeps the original spawn point')
    T.eq('stale', R.onCreated(req, 3, 'a', 55), 'old wagon token cannot re-adopt')
    local u = newReq(0, { kind = 'wagon', model = 'cart01' })
    adoptVia(u, 3, 'a', 55)
    T.eq('keep', R.onPlayerDropped(u, 3, false))
    T.eq('adopted', u.state)
end)

case('C3c requestOfNetId: hit, miss, non-number, stale after re-adopt, after despawn', function()
    local req, other = newReq(), newReq()
    adoptVia(req, 3, 'a', 55)
    adoptVia(other, 4, 'b', 66)
    local all = { [7] = req, [8] = other }
    T.eq(7, R.requestOfNetId(all, 55), 'hit')
    T.eq(8, R.requestOfNetId(all, 66))
    T.eq(nil, R.requestOfNetId(all, 99), 'miss')
    for _, bad in ipairs({ 'x', '55', 0, -1, 55.5, 1e100, 0/0, true }) do T.eq(nil, R.requestOfNetId(all, bad)) end
    T.eq(nil, R.requestOfNetId(all, nil))
    local v = newReq()
    assert(R.dispatch(v, 3, 'c', 0)); R.onCreated(v, 3, 'c', 77)
    T.eq(nil, R.requestOfNetId({ [9] = v }, 77), 'verifying (not adopted) does not map')
    -- owner drop (gated) -> re-request clears the old netId; re-adopt under a new netId
    T.eq('despawn_rerequest', R.onPlayerDropped(req, 3, true))
    T.eq(nil, R.requestOfNetId(all, 55), 'stale netId after re-request')
    assert(R.dispatch(req, 5, 'd', 0))
    T.eq('verify', (R.onCreated(req, 5, 'd', 56)))
    T.eq(nil, R.requestOfNetId(all, 56), 'not adopted yet')
    local ok = R.finishVerify(req, 'd', true, nil, 1234)
    T.eq('adopted', ok)
    T.eq(7, R.requestOfNetId(all, 56), 'new netId maps')
    T.eq(nil, R.requestOfNetId(all, 55), 'old netId still stale after re-adopt')
    R.despawn(other)
    T.eq(nil, R.requestOfNetId(all, 66), 'despawned request (still in table) holds nothing')
    all[8] = nil
    T.eq(nil, R.requestOfNetId(all, 66), 'removed request holds nothing')
end)

T.finish()
