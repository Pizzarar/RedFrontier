-- Edge cases for the fh_core spawn contract (core-07 S1). Two stubbed halves:
--  * server/spawn.lua against a fake world (players, entities, clock, thread pump): requestOfNetId after the entity is
--    gone, re-request loops that must terminate, dispatch/verify timeouts, late and duplicate acks, snap passthrough;
--  * client/spawn.lua against fake natives: one entity per token, delete/release guards, snap default / false.
-- Not a live boot: natives are fakes, threads are coroutines pumped by the spec.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local CORE = here .. '../server/resources/[fh]/fh_core/'

local FhSpawnRules, FhConfig, FhGroundSnap = require('spawn_rules'), require('config'), require('ground_snap')
local MODEL = 'a_c_horse_morgan_bay'
local HASH = FhSpawnRules.modelHash(MODEL)

local function loadInto(env, rel)
    local p = CORE .. rel
    local fh = assert(io.open(p, 'rb')); local src = fh:read('a'); fh:close()
    assert(load(src, '@' .. p, 't', env))()
end

-- ============================================================ server half
local S = {}
local function newServer()
    local w = { now = 0, ents = {}, nextEnt = 1000, players = {}, ready = {}, sent = {}, threads = {}, exports = {},
        handlers = {}, drops = {}, logs = {} }
    local env = setmetatable({
        FhSpawnRules = FhSpawnRules, FhConfig = FhConfig,
        GetCurrentResourceName = function() return 'fh_core' end, GetInvokingResource = function() return 'spec' end,
        GetConvar = function(_, d) return d end,
        GetGameTimer = function() return w.now end,
        GetPlayers = function() local o = {} for id in pairs(w.players) do o[#o + 1] = tostring(id) end table.sort(o) return o end,
        GetPlayerPed = function(id) return w.players[id] and 500 + id or 0 end,
        GetEntityCoords = function(e)
            if e >= 500 and e < 1000 then return { x = 10, y = 20, z = 30 } end
            return w.ents[e] and w.ents[e].coords or { x = 0, y = 0, z = 0 }
        end,
        NetworkGetEntityFromNetworkId = function(n) for e, x in pairs(w.ents) do if x.netId == n then return e end end return 0 end,
        DoesEntityExist = function(e) return w.ents[e] ~= nil end,
        GetEntityModel = function(e) return w.ents[e] and w.ents[e].model or 0 end,
        NetworkGetEntityOwner = function(e) return w.ents[e] and w.ents[e].owner or -1 end,
        DeleteEntity = function(e) w.ents[e] = nil end, SetEntityOrphanMode = function() end,
        IsPedAPlayer = function() return false end,
        TriggerClientEvent = function(name, target, data) w.sent[#w.sent + 1] = { name = name, target = target, data = data } end,
        RegisterNetEvent = function(name, fn) w.handlers[name] = fn end,
        AddEventHandler = function(name, fn) w.handlers[name] = fn end,
        exports = setmetatable({}, { __call = function(_, n, fn) w.exports[n] = fn end }),
        CreateThread = function(fn) local co = coroutine.create(fn); w.threads[#w.threads + 1] = co; assert(coroutine.resume(co)) end,
        Wait = function() coroutine.yield() end,
        print = function(...) w.logs[#w.logs + 1] = table.concat({ ... }, ' ') end,
    }, { __index = _G })
    env._G = env
    loadInto(env, 'server/spawn.lua')
    w.env = env
    function w.pump() -- resume every parked thread once (== one Wait elapsed)
        local alive = {}
        for _, co in ipairs(w.threads) do
            if coroutine.status(co) == 'suspended' then assert(coroutine.resume(co)); alive[#alive + 1] = co end
        end
        w.threads = alive
    end
    function w.tick() w.now = w.now + FhConfig.Spawn.TickMs; w.pump() end
    function w.join(id) w.players[id] = true; env.source = id; w.handlers['fh:spawn:client_ready']() end
    function w.fire(src, name, data) env.source = src; w.handlers[name](data) end
    function w.events(name) local o = {} for _, e in ipairs(w.sent) do if e.name == name then o[#o + 1] = e end end return o end
    function w.lastCreate() local e = w.events('fh:spawn:create'); return e[#e] end
    -- a spawner client made `netId` for the last dispatch: server-side entity + the ack
    function w.ack(create, netId, over)
        over = over or {}
        local e = w.nextEnt; w.nextEnt = e + 1
        if over.entity ~= false then
            w.ents[e] = { netId = netId, model = over.model or HASH, coords = create.data.coords, owner = over.owner or create.target }
        end
        w.fire(over.src or create.target, 'fh:spawn:created',
            { requestId = create.data.requestId, token = over.token or create.data.token, netId = netId })
        w.pump()
        return e
    end
    return w
end

local function spec(over)
    local s = { kind = 'horse', model = MODEL, coords = { x = 10, y = 20, z = 30 }, heading = 90, tag = 't' }
    for k, v in pairs(over or {}) do s[k] = v end
    return s
end

T.describe('server: snap passthrough (world block D)', function()
    for _, c in ipairs({ { 'omitted -> true', nil, true }, { 'false -> false', false, false }, { 'true -> true', true, true },
        { 'non-boolean "no" -> true (only literal false opts out)', 'no', true } }) do
        T.it(c[1], function()
            local w = newServer(); w.join(1)
            local id = w.exports.requestSpawn(spec({ snap = c[2] }))
            assert(id)
            T.eq(c[3], w.lastCreate().data.snap)
        end)
    end
end)

T.describe('server: requestOfNetId after the entity is gone', function()
    T.it('adopted entity vanishes: maps until the tick notices, then nil; the request goes back to pending', function()
        local w = newServer(); w.join(1)
        local id = w.exports.requestSpawn(spec())
        local ent = w.ack(w.lastCreate(), 77)
        T.eq('adopted', w.exports.getSpawn(id).state)
        T.eq(id, w.exports.requestOfNetId(77))
        w.ents[ent] = nil -- despawned by the engine
        T.eq(id, w.exports.requestOfNetId(77), 'still adopted until the next tick')
        w.tick()
        T.eq(nil, w.exports.requestOfNetId(77))
        local st = w.exports.getSpawn(id)
        T.eq(nil, st.netId)
        assert(st.state == 'dispatched' or st.state == 'pending', st.state)
    end)
    T.it('after despawn(): nil, and getSpawn is nil; despawn again is fh_spawn_unknown_request', function()
        local w = newServer(); w.join(1)
        local id = w.exports.requestSpawn(spec())
        w.ack(w.lastCreate(), 78)
        T.eq(true, w.exports.despawn(id))
        T.eq(nil, w.exports.requestOfNetId(78))
        T.eq(nil, w.exports.getSpawn(id))
        T.same({ false, 'fh_spawn_unknown_request' }, { w.exports.despawn(id) })
    end)
    T.it('junk netIds never map (nil, 0, -1, 1.5, nan, inf, string, table, > int32)', function()
        local w = newServer(); w.join(1)
        w.exports.requestSpawn(spec()); w.ack(w.lastCreate(), 79)
        for _, v in ipairs({ 0, -1, 1.5, 0 / 0, math.huge, '79', {}, 2 ^ 40 }) do T.eq(nil, w.exports.requestOfNetId(v), tostring(v)) end
        T.eq(nil, w.exports.requestOfNetId(nil))
        T.eq(true, w.exports.requestOfNetId(79.0) ~= nil, 'integer-valued float is the same netId')
    end)
    T.it('a re-used netId after re-request maps only to the new adoption, never the old request', function()
        local w = newServer(); w.join(1)
        local a = w.exports.requestSpawn(spec())
        local ea = w.ack(w.lastCreate(), 80)
        w.ents[ea] = nil; w.tick()                    -- a: entity gone, re-requested
        local b = w.exports.requestSpawn(spec({ tag = 'b' }))
        w.ack(w.lastCreate(), 80)                      -- b's entity happens to get netId 80
        T.eq(b, w.exports.requestOfNetId(80))
        assert(a ~= b)
    end)
end)

T.describe('server: re-request loops terminate', function()
    T.it('client acks a netId whose entity never reaches the server: bounded attempts, onFailed once, request removed', function()
        local w = newServer(); w.join(1)
        local failed = {}
        local id = w.exports.requestSpawn(spec(), { retries = 2, timeoutMs = 1000,
            onFailed = function(reason, rid) failed[#failed + 1] = { reason, rid } end })
        for _ = 1, 40 do
            local c = w.lastCreate()
            if w.exports.getSpawn(id) and w.exports.getSpawn(id).state == 'dispatched' and not c.acked then
                c.acked = true
                w.ack(c, 90 + #w.events('fh:spawn:create'), { entity = false })
            end
            w.now = w.now + 1000; w.tick()
            if not w.exports.getSpawn(id) then break end
        end
        T.eq(nil, w.exports.getSpawn(id), 'request failed and was dropped')
        T.eq(3, #w.events('fh:spawn:create'), 'retries=2 -> exactly 3 dispatches')
        T.eq(1, #failed); T.eq(id, failed[1][2])
        assert(failed[1][1], 'a reason is reported')
    end)
    T.it('client never acks: every dispatch times out, then fails after retries+1 dispatches', function()
        local w = newServer(); w.join(1)
        local failed = 0
        local id = w.exports.requestSpawn(spec(), { retries = 1, timeoutMs = 1000, onFailed = function() failed = failed + 1 end })
        for _ = 1, 20 do w.now = w.now + 1000; w.tick() end
        T.eq(nil, w.exports.getSpawn(id)); T.eq(1, failed); T.eq(2, #w.events('fh:spawn:create'))
        T.eq(2, #w.events('fh:spawn:delete'), 'each timed-out attempt tells its spawner to drop what it made')
    end)
    T.it('adopted entity gone and nobody online: parks, no dispatch spin over many ticks', function()
        local w = newServer(); w.join(1)
        local id = w.exports.requestSpawn(spec())
        local ent = w.ack(w.lastCreate(), 95)
        w.players[1] = nil; w.fire(1, 'playerDropped') -- spawner leaves (gated -> despawn_rerequest)
        w.ents[ent] = nil
        local before = #w.events('fh:spawn:create')
        for _ = 1, 50 do w.tick() end
        T.eq(before, #w.events('fh:spawn:create'), 'no client: nothing dispatched')
        T.eq('pending_no_client', w.exports.getSpawn(id).state)
        w.join(2); w.tick()
        T.eq(before + 1, #w.events('fh:spawn:create'), 'a joining client picks the parked request up once')
        T.eq(2, w.lastCreate().target)
    end)
    T.it('spawner drop mid-dispatch retries on another client and burns an attempt each time (bounded)', function()
        local w = newServer(); w.join(1); w.join(2)
        local id = w.exports.requestSpawn(spec(), { retries = 1, timeoutMs = 1000 })
        local first = w.lastCreate().target
        w.players[first] = nil; w.fire(first, 'playerDropped')
        local second = w.lastCreate().target
        assert(second ~= first, 'moves to the other client')
        w.players[second] = nil; w.fire(second, 'playerDropped')
        T.eq(nil, w.exports.getSpawn(id), 'attempts exhausted -> failed')
    end)
end)

T.describe('server: timeout and late / duplicate acks', function()
    T.it('ack after the dispatch timed out is stale: spawner told to delete that netId, state unchanged, nothing adopted', function()
        local w = newServer(); w.join(1)
        local id = w.exports.requestSpawn(spec(), { retries = 3, timeoutMs = 1000 })
        local old = w.lastCreate()
        w.now = w.now + 1000; w.tick()                 -- timed out -> retried (new token)
        local newTok = w.lastCreate().data.token
        assert(newTok ~= old.data.token)
        local before = #w.events('fh:spawn:delete')
        w.ack(old, 55)
        T.eq('dispatched', w.exports.getSpawn(id).state)
        T.eq(nil, w.exports.requestOfNetId(55))
        local del = w.events('fh:spawn:delete')
        T.eq(before + 1, #del)
        T.eq(55, del[#del].data.netId); T.eq(old.data.token, del[#del].data.token)
    end)
    T.it('late ack then the real ack on the new token: the new one is adopted, stale entity never is', function()
        local w = newServer(); w.join(1)
        local id = w.exports.requestSpawn(spec(), { retries = 3, timeoutMs = 1000 })
        local old = w.lastCreate()
        w.now = w.now + 1000; w.tick()
        w.ack(old, 55)
        w.ack(w.lastCreate(), 56)
        T.eq('adopted', w.exports.getSpawn(id).state)
        T.eq(56, w.exports.getSpawn(id).netId)
        T.eq(nil, w.exports.requestOfNetId(55)); T.eq(id, w.exports.requestOfNetId(56))
    end)
    T.it('duplicate ack, same netId, after adoption: ignored, nothing deleted', function()
        local w = newServer(); w.join(1)
        w.exports.requestSpawn(spec())
        local c = w.lastCreate(); w.ack(c, 60)
        local before = #w.events('fh:spawn:delete')
        w.fire(1, 'fh:spawn:created', { requestId = c.data.requestId, token = c.data.token, netId = 60 }); w.pump()
        T.eq(before, #w.events('fh:spawn:delete'))
        T.eq(60, w.exports.getSpawn(c.data.requestId).netId)
    end)
    T.it('duplicate ack with a DIFFERENT netId: only the extra entity is deleted, adopted netId untouched', function()
        local w = newServer(); w.join(1)
        w.exports.requestSpawn(spec())
        local c = w.lastCreate(); w.ack(c, 61)
        w.fire(1, 'fh:spawn:created', { requestId = c.data.requestId, token = c.data.token, netId = 62 }); w.pump()
        local del = w.events('fh:spawn:delete'); local d = del[#del]
        T.eq(62, d.data.netId)
        T.eq(61, w.exports.getSpawn(c.data.requestId).netId)
        T.eq('adopted', w.exports.getSpawn(c.data.requestId).state)
    end)
    T.it('ack from a client that was not asked: ignored (wrong source), request keeps waiting', function()
        local w = newServer(); w.join(1); w.join(2)
        local id = w.exports.requestSpawn(spec())
        local c = w.lastCreate()
        local other = c.target == 1 and 2 or 1
        w.ack(c, 63, { src = other })
        T.eq('dispatched', w.exports.getSpawn(id).state)
        T.eq(nil, w.exports.requestOfNetId(63))
    end)
    T.it('ack with bad netId (0, -3, nan, string, missing): ignored; the dispatch timeout still retries', function()
        local w = newServer(); w.join(1)
        local id = w.exports.requestSpawn(spec(), { retries = 3, timeoutMs = 1000 })
        local c = w.lastCreate()
        for _, n in ipairs({ 0, -3, 0 / 0, 'x', false }) do
            w.fire(1, 'fh:spawn:created', { requestId = c.data.requestId, token = c.data.token, netId = n })
        end
        w.fire(1, 'fh:spawn:created', { requestId = c.data.requestId, token = c.data.token })
        w.fire(1, 'fh:spawn:created', 'garbage'); w.fire(1, 'fh:spawn:created', nil)
        T.eq('dispatched', w.exports.getSpawn(id).state)
        w.now = w.now + 1000; w.tick()
        T.eq(2, #w.events('fh:spawn:create'))
    end)
    T.it('despawn while the client is still creating, then the ack arrives: unknown request, sender told to delete it', function()
        local w = newServer(); w.join(1)
        local id = w.exports.requestSpawn(spec())
        local c = w.lastCreate()
        T.eq(true, w.exports.despawn(id))
        local before = #w.events('fh:spawn:delete')
        assert(before >= 1, 'despawn tells the spawner to drop the token')
        w.ack(c, 64, { entity = false })
        T.eq(nil, w.exports.requestOfNetId(64))
        T.eq(before + 1, #w.events('fh:spawn:delete'))
    end)
    T.it('failed event: only the current spawner + token counts; a forged one changes nothing', function()
        local w = newServer(); w.join(1); w.join(2)
        local id = w.exports.requestSpawn(spec())
        local c = w.lastCreate()
        local other = c.target == 1 and 2 or 1
        w.fire(other, 'fh:spawn:failed', { requestId = id, token = c.data.token, reason = 'x' })
        w.fire(c.target, 'fh:spawn:failed', { requestId = id, token = 'nope', reason = 'x' })
        T.eq(1, #w.events('fh:spawn:create'))
        w.fire(c.target, 'fh:spawn:failed', { requestId = id, token = c.data.token, reason = 'model_timeout' })
        T.eq(2, #w.events('fh:spawn:create'), 'the real failure retries on the next attempt')
    end)
end)

-- ============================================================ client half
local function newClient()
    local c = { now = 0, handlers = {}, sent = {}, created = {}, deleted = {}, threads = {}, nextEnt = 2000, probes = {},
        networked = true, modelOk = true, fail = nil, local_events = {} }
    local env = setmetatable({
        FhSpawnRules = FhSpawnRules, FhGroundSnap = FhGroundSnap,
        FhSnap = { groundZAt = function(tag, x, y, z, above) c.probes[#c.probes + 1] = { tag, z, above }; return z - 4.0 end },
        FH = {
            onNet = function(name, fn) c.handlers[name] = fn end, on = function(name, fn) c.handlers[name] = fn end,
            thread = function(fn) local co = coroutine.create(fn); c.threads[#c.threads + 1] = co; assert(coroutine.resume(co)) end,
        },
        GetCurrentResourceName = function() return 'fh_core' end, GetGameTimer = function() return c.now end,
        Wait = function(ms) c.now = c.now + (ms or 0); coroutine.yield() end,
        IsModelInCdimage = function() return c.modelOk end, RequestModel = function() end,
        HasModelLoaded = function() return c.modelOk end, SetModelAsNoLongerNeeded = function() end,
        CreatePed = function(_, x, y, z) local e = c.nextEnt; c.nextEnt = e + 1; c.created[e] = { x = x, y = y, z = z }; return e end,
        CreateObject = function(_, x, y, z) local e = c.nextEnt; c.nextEnt = e + 1; c.created[e] = { x = x, y = y, z = z }; return e end,
        CreateVehicle = function(_, x, y, z) local e = c.nextEnt; c.nextEnt = e + 1; c.created[e] = { x = x, y = y, z = z }; return e end,
        SetEntityHeading = function() end, SetEntityAsMissionEntity = function() end,
        DoesEntityExist = function(e) return c.created[e] ~= nil end,
        DeleteEntity = function(e) c.deleted[#c.deleted + 1] = e; c.created[e] = nil end,
        NetworkGetEntityIsNetworked = function() return c.networked end,
        NetworkGetNetworkIdFromEntity = function(e) return e - 1000 end, NetworkDoesNetworkIdExist = function() return true end,
        Citizen = { InvokeNative = function() end },
        TriggerServerEvent = function(name, data) c.sent[#c.sent + 1] = { name = name, data = data } end,
        TriggerEvent = function(name, data) c.local_events[#c.local_events + 1] = { name = name, data = data } end,
    }, { __index = _G })
    env._G = env
    loadInto(env, 'client/spawn.lua')
    function c.run() for _, co in ipairs(c.threads) do if coroutine.status(co) == 'suspended' then assert(coroutine.resume(co)) end end end
    function c.sentNamed(n) local o = {} for _, e in ipairs(c.sent) do if e.name == n then o[#o + 1] = e end end return o end
    function c.create(over)
        local d = { requestId = 1, kind = 'horse', modelHash = HASH, coords = { x = 1, y = 2, z = 10 }, heading = 0, token = 'tok1', tag = 't' }
        for k, v in pairs(over or {}) do d[k] = v end
        c.handlers['fh:spawn:create'](d)
        for _ = 1, 4 do c.run() end
        return d
    end
    return c
end

T.describe('client: ground snap passthrough', function()
    T.it('snap omitted (nil) probes and snaps z to the ground', function()
        local c = newClient(); c.create()
        T.eq(1, #c.probes); T.eq(6.0, c.created[2000].z)
    end)
    T.it('snap=true snaps; snap=false keeps the requested z and never probes', function()
        local c = newClient(); c.create({ snap = true, token = 'a' })
        T.eq(6.0, c.created[2000].z)
        local d = newClient(); d.create({ snap = false })
        T.eq(0, #d.probes); T.eq(10, d.created[2000].z)
    end)
    T.it('wagons never snap, even by default', function()
        local c = newClient(); c.create({ kind = 'wagon' })
        T.eq(0, #c.probes); T.eq(10, c.created[2000].z)
    end)
end)

T.describe('client: ack / delete / release guards', function()
    T.it('a repeated fh:spawn:create for one token makes exactly one entity and one ack', function()
        local c = newClient(); local d = c.create()
        c.handlers['fh:spawn:create'](d); for _ = 1, 3 do c.run() end
        local n = 0 for _ in pairs(c.created) do n = n + 1 end
        T.eq(1, n); T.eq(1, #c.sentNamed('fh:spawn:created'))
    end)
    T.it('model never loads: fh:spawn:failed model_timeout, token freed so a re-dispatch of it can retry', function()
        local c = newClient(); c.modelOk = false
        c.create()
        T.eq('model_timeout', c.sentNamed('fh:spawn:failed')[1].data.reason)
        c.modelOk = true; c.handlers['fh:spawn:create']({ requestId = 1, kind = 'horse', modelHash = HASH,
            coords = { x = 1, y = 2, z = 10 }, heading = 0, token = 'tok1' })
        for _ = 1, 4 do c.run() end
        T.eq(1, #c.sentNamed('fh:spawn:created'))
    end)
    T.it('entity never networks: no_netid, local entity deleted, no ack', function()
        local c = newClient(); c.networked = false
        c.create()
        for _ = 1, 80 do c.run() end
        T.eq('no_netid', c.sentNamed('fh:spawn:failed')[1].data.reason)
        T.eq(0, #c.sentNamed('fh:spawn:created')); T.eq(1, #c.deleted)
    end)
    T.it('delete with a netId that is not ours, or an unknown token, deletes nothing', function()
        local c = newClient(); c.create()
        c.handlers['fh:spawn:delete']({ token = 'tok1', netId = 999 })
        c.handlers['fh:spawn:delete']({ token = 'other' })
        c.handlers['fh:spawn:delete']('junk'); c.handlers['fh:spawn:delete']({})
        T.eq(0, #c.deleted)
    end)
    T.it('delete with the matching netId (or none) removes our entity once', function()
        local c = newClient(); c.create()
        c.handlers['fh:spawn:delete']({ token = 'tok1', netId = 1000 })
        T.eq(1, #c.deleted)
        c.handlers['fh:spawn:delete']({ token = 'tok1' })
        T.eq(1, #c.deleted)
    end)
    T.it('delete arrives while still creating: no ack is sent and the entity is dropped', function()
        local c = newClient(); c.networked = false -- entity exists but has no netId yet: create() is parked in its Wait
        c.handlers['fh:spawn:create']({ requestId = 1, kind = 'horse', modelHash = HASH, coords = { x = 1, y = 2, z = 10 },
            heading = 0, token = 'tok1' })
        c.handlers['fh:spawn:delete']({ token = 'tok1' })
        c.networked = true
        for _ = 1, 6 do c.run() end
        T.eq(0, #c.sentNamed('fh:spawn:created'))
        T.eq(0, #c.sentNamed('fh:spawn:failed'), 'a cancelled create is silent')
        T.eq(1, #c.deleted)
    end)
    T.it('release fires the local adopted hook once; a release for the wrong netId or a repeat does nothing', function()
        local c = newClient(); c.create({ owner = { kind = 'admin', id = 1 } })
        c.handlers['fh:spawn:release']({ token = 'tok1', netId = 5 })
        T.eq(0, #c.local_events)
        c.handlers['fh:spawn:release']({ requestId = 1, token = 'tok1', netId = 1000 })
        T.eq(1, #c.local_events); T.eq('fh:spawn:adopted', c.local_events[1].name)
        c.handlers['fh:spawn:release']({ requestId = 1, token = 'tok1', netId = 1000 })
        T.eq(1, #c.local_events)
        c.handlers['fh:spawn:delete']({ token = 'tok1' })
        T.eq(0, #c.deleted, 'released entity is no longer ours to delete')
    end)
    T.it('malformed create payloads are ignored (non-table, missing token, missing coords)', function()
        local c = newClient()
        c.handlers['fh:spawn:create']('x'); c.handlers['fh:spawn:create']({ token = 1, coords = {} })
        c.handlers['fh:spawn:create']({ token = 't', coords = nil })
        for _ = 1, 3 do c.run() end
        T.eq(0, #c.sentNamed('fh:spawn:created') + #c.sentNamed('fh:spawn:failed'))
    end)
end)

T.finish()
