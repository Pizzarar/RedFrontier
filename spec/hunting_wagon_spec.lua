-- Run from repo root: `lua spec/hunting_wagon_spec.lua` (or via tools/run-specs.py).
-- The fh_cargo:nearestWagon adapter (shared/wagon.lua), and that the skin flow treats "no wagon" as a refusal that
-- keeps the carcass claimable.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local describe, it, eq, same = T.describe, T.it, T.eq, T.same
local base = here .. '../server/resources/[fh]/fh_hunting/'
local cfg = dofile(base .. 'config.lua')
local A = dofile(base .. 'shared/animals.lua')
local Q = dofile(base .. 'shared/quality.lua')
local S = dofile(base .. 'shared/skin.lua')
local W = dofile(base .. 'shared/wagon.lua')
local Containers = require('containers')

local PC = { x = 1, y = 2, z = 3 }

describe('hunting wagon adapter', function()
    it('passes (src, coords, range) through and adapts { type, id } to { ref, coords }', function()
        local got
        local w = W.find(function(src, c, r) got = { src, c, r }; return { type = 'wagon', id = 'fh:wagon:9' } end, 7, PC, cfg.WagonRange)
        same({ 7, PC, 8.0 }, got)
        same({ type = 'wagon', id = 'fh:wagon:9' }, w.ref)
        same(PC, w.coords)
    end)
    it('nil from fh_cargo is no wagon', function()
        eq(nil, W.find(function() return nil end, 7, PC, 8))
    end)
    it('a throw (fh_cargo missing or stopped) is no wagon and does not propagate', function()
        eq(nil, W.find(function() error('No such export nearestWagon in resource fh_cargo') end, 7, PC, 8))
    end)
    it('malformed returns are no wagon', function()
        for _, bad in ipairs({ 5, 'wagon', true, {}, { type = 'horse', id = 'fh:wagon:1' }, { type = 'wagon' },
            { type = 'wagon', id = '' }, { type = 'wagon', id = 12 } }) do
            eq(nil, W.find(function() return bad end, 7, PC, 8))
        end
    end)
    it('no coords or no function is no wagon', function()
        eq(nil, W.find(function() return { type = 'wagon', id = 'fh:wagon:1' } end, 7, nil, 8))
        eq(nil, W.find(nil, 7, PC, 8))
    end)
end)

describe('hunting wagon adapter: vector3 coords', function()
    it('accepts a vector-like player position and passes it through', function()
        local v = setmetatable({}, { __index = { x = 1, y = 2, z = 3 } })
        local got
        local w = W.find(function(_, c) got = c; return { type = 'wagon', id = 'fh:wagon:2' } end, 7, v, 8)
        eq(true, got == v)
        eq('fh:wagon:2', w.ref.id)
        eq(true, w.coords == v)
    end)
    it('rejects coords without numeric x, y, z', function()
        local f = function() return { type = 'wagon', id = 'fh:wagon:2' } end
        eq(nil, W.find(f, 7, 'here', 8))
        eq(nil, W.find(f, 7, { x = 1, y = 2 }, 8))
        eq(nil, W.find(f, 7, setmetatable({}, { __index = { x = 1, y = 'a', z = 3 } }), 8))
    end)
end)

describe('hunting wagon adapter inside the skin flow', function()
    local SRC, CID = 7, 'CID123'
    local function skinner(nearest)
        local carcass = { entity = 5001, isPed = true, isPlayer = false, model = A.joaat('a_c_bear_01'),
            coords = { x = 2, y = 0, z = 0 }, dead = true }
        local adds, claims = {}, S.newClaims()
        local s = S.new({ cfg = cfg, animals = A, quality = Q, claims = claims, deps = {
            citizenid = function() return CID end,
            playerCoords = function() return { x = 0, y = 0, z = 0 } end,
            readCarcass = function(netId) if netId == 101 then return carcass end end,
            saddlebagOf = function() return { type = 'saddlebag', id = 'fh:saddle:' .. CID } end,
            findCargoWagon = function(src) return W.find(nearest, src, { x = 0, y = 0, z = 0 }, cfg.WagonRange) end,
            addItem = function(ref, name, n, info) adds[#adds + 1] = { ref = ref, name = name }; return true end,
            accepts = function(t, sc) return (Containers.accepts(t, sc)) end,
            finishCarcass = function() end, emit = function() end, rng = function() return 0.99 end,
        } })
        return s, adds, claims
    end
    local req = { netId = 101, bone = 'skel_head' }

    it('ok: a big-game pelt goes into the wagon fh_cargo returned', function()
        local s, adds = skinner(function() return { type = 'wagon', id = 'fh:wagon:3' } end)
        local ok = s.skin(SRC, req)
        eq(true, ok)
        same({ type = 'wagon', id = 'fh:wagon:3' }, adds[1].ref)
    end)
    it('nil: refused with fh_no_wagon and the carcass stays claimable', function()
        local s, adds, claims = skinner(function() return nil end)
        local ok, err = s.skin(SRC, req)
        eq(false, ok); eq('fh_no_wagon', err)
        eq(0, #adds)
        eq(false, claims:isClaimed(101, 5001))
    end)
    it('throw: same refusal, carcass stays claimable', function()
        local s, adds, claims = skinner(function() error('fh_cargo not started') end)
        local ok, err = s.skin(SRC, req)
        eq(false, ok); eq('fh_no_wagon', err)
        eq(0, #adds)
        eq(false, claims:isClaimed(101, 5001))
    end)
end)

T.finish()
