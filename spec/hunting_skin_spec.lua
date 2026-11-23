-- Run from repo root: `lua spec/hunting_skin_spec.lua` (or via tools/run-specs.py).
-- The real skin flow (shared/skin.lua) with fake natives/exports: claim once, refusals, destinations, event.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local describe, it, eq, same = T.describe, T.it, T.eq, T.same
local base = here .. '../server/resources/[fh]/fh_hunting/'
local cfg = dofile(base .. 'config.lua')
local A = dofile(base .. 'shared/animals.lua')
local Q = dofile(base .. 'shared/quality.lua')
local S = dofile(base .. 'shared/skin.lua')
local Containers = require('containers') -- fh_core/shared/containers.lua: the real size-class rules

local SRC, CID = 7, 'CID123'
local DEER = A.joaat('a_c_deer_01')
local BEAR = A.joaat('a_c_bear_01')

-- A world with one carcass (netId 101) next to the player and fakes for every dep. Override with `w`.
local function world(w)
    w = w or {}
    local W = {
        player = { x = 0, y = 0, z = 0 },
        carcass = { entity = 5001, isPed = true, isPlayer = false, model = w.model or DEER,
            coords = { x = 2, y = 0, z = 0 }, dead = true },
        saddlebag = { type = 'saddlebag', id = 'fh:saddle:' .. CID },
        wagon = nil,            -- { ref, coords } when a wagon is near
        adds = {},              -- every addItem call: { ref, name, n, info }
        refuse = {},            -- [container type] = err: addItem fails for that type
        finished = {},
        events = {},
        claims = S.newClaims(),
    }
    for k, v in pairs(w) do if k ~= 'model' then W[k] = v end end
    if w.carcassPatch then for k, v in pairs(w.carcassPatch) do W.carcass[k] = v end end
    W.deps = {
        citizenid = function(src) return src == SRC and CID or nil end,
        playerCoords = function() return W.player end,
        readCarcass = function(netId) if netId == 101 and W.carcass then return W.carcass end end,
        saddlebagOf = function() return W.saddlebag end,
        findCargoWagon = function() return W.wagon end,
        addItem = function(ref, name, n, info)
            W.adds[#W.adds + 1] = { ref = ref, name = name, n = n, info = info }
            if W.onAdd then W.onAdd(ref) end
            local err = W.refuse[ref.type]
            if err then return false, err end
            return true
        end,
        accepts = function(t, sc) return (Containers.accepts(t, sc)) end,
        finishCarcass = function(ent, netId) W.finished[#W.finished + 1] = { ent, netId } end,
        emit = function(name, payload) W.events[#W.events + 1] = { name = name, payload = payload } end,
        rng = function() return 0.99 end, -- never downgrades
    }
    W.skinner = S.new({ cfg = cfg, animals = A, quality = Q, claims = W.claims, deps = W.deps })
    W.skin = function(payload) return W.skinner.skin(SRC, payload or { netId = 101, bone = 'skel_head' }) end
    return W
end

local function wagonAt(x) return { ref = { type = 'wagon', id = 'fh:wagon:1' }, coords = { x = x, y = 0, z = 0 } } end

describe('hunting skin: claim registry', function()
    it('claim is test-and-set; release gives it back; skinned never releases', function()
        local c = S.newClaims()
        eq(true, c:claim(1, 'e')); eq(false, c:claim(1, 'e')); eq(true, c:isClaimed(1, 'e'))
        c:release(1, 'e'); eq(false, c:isClaimed(1, 'e')); eq(true, c:claim(1, 'e'))
        c:markSkinned(1, 'e'); c:release(1, 'e'); eq('skinned', c:state(1, 'e')); eq(false, c:claim(1, 'e'))
    end)
    it('a netId reused by another entity is not blocked by the stale entry', function()
        local c = S.newClaims()
        c:claim(1, 'old'); c:markSkinned(1, 'old')
        eq(false, c:isClaimed(1, 'new')); eq(true, c:claim(1, 'new'))
    end)
    it('prune drops skinned entries whose carcass is gone, keeps pending ones', function()
        local c = S.newClaims()
        c:claim(1, 'a'); c:markSkinned(1, 'a'); c:claim(2, 'b')
        eq(1, c:prune(function() return false end))
        eq(nil, c:state(1, 'a')); eq('pending', c:state(2, 'b'))
    end)
end)

describe('hunting skin: request sanitizing', function()
    it('needs a positive integer netId', function()
        eq('fh_bad_request', select(2, S.sanitize(nil)))
        for _, bad in ipairs({ 0, -3, 1.5, 0 / 0, math.huge, '5' }) do
            eq('fh_bad_request', select(2, S.sanitize({ netId = bad })), tostring(bad))
        end
        eq(9, S.sanitize({ netId = 9.0 }).netId)
    end)
    it('keeps a bone name or integer id, drops junk; clamps hints', function()
        eq('skel_head', S.sanitize({ netId = 1, bone = 'skel_head' }).bone)
        eq(21030, S.sanitize({ netId = 1, bone = 21030 }).bone)
        eq(nil, S.sanitize({ netId = 1, bone = 'skel head; drop' }).bone)
        eq(nil, S.sanitize({ netId = 1, bone = 1.5 }).bone)
        eq(nil, S.sanitize({ netId = 1, hits = -1 }).hits)
        eq(false, S.sanitize({ netId = 1, explosive = 'yes' }).explosive)
        eq(nil, S.sanitize({ netId = 1, nativeQuality = 99 }).nativeQuality)
    end)
end)

describe('hunting skin: destinations follow the fh_core size-class rules', function()
    local acc = function(t, sc) return (Containers.accepts(t, sc)) end
    it('bulky: saddlebag then wagon, never the backpack (pocket only)', function()
        same({ 'saddlebag', 'wagon' }, S.targetsFor('bulky', cfg, acc))
        local c = { GrantOrder = { bulky = { 'backpack', 'saddlebag' } } }
        same({ 'saddlebag' }, S.targetsFor('bulky', c, acc))
    end)
    it('cargo: wagon only', function()
        same({ 'wagon' }, S.targetsFor('cargo', cfg, acc))
        same({ 'wagon' }, S.targetsFor('cargo', { GrantOrder = { cargo = { 'saddlebag', 'wagon' } } }, acc))
    end)
end)

describe('hunting skin: claim once', function()
    it('a head-shot deer gives one 3 star pelt to the saddlebag, the carcass is finished', function()
        local W = world()
        local ok, res = W.skin()
        assert(ok, tostring(res))
        eq('pelt_deer', res.item); eq(3, res.stars); eq('saddlebag', res.container)
        eq(1, #W.adds); same({ stars = 3 }, W.adds[1].info); eq(1, W.adds[1].n)
        same({ { 5001, 101 } }, W.finished)
        eq('skinned', W.claims:state(101, 5001))
    end)
    it('a gut-shot deer gives a 1 star pelt', function()
        local W = world()
        local ok, res = W.skin({ netId = 101, bone = 'skel_pelvis' })
        assert(ok); eq(1, res.stars)
    end)
    it('a duplicate request after the grant is refused and grants nothing', function()
        local W = world()
        assert(W.skin())
        local ok, why = W.skin()
        eq(false, ok); eq('fh_already_claimed', why); eq(1, #W.adds)
    end)
    it('a request re-entering while the first is inside addItem is refused (no double grant)', function()
        local W = world()
        local inner
        W.onAdd = function()
            if not inner then inner = { W.skin() } end
        end
        local ok = W.skin()
        assert(ok)
        eq(false, inner[1]); eq('fh_already_claimed', inner[2])
        eq(1, #W.adds); eq(1, #W.events)
    end)
end)

describe('hunting skin: plausibility refusals leave the carcass claimable', function()
    it('out of range is refused', function()
        local W = world({ carcassPatch = { coords = { x = cfg.SkinRange + 0.5, y = 0, z = 0 } } })
        eq('fh_too_far', select(2, W.skin()))
        eq(0, #W.adds); eq(nil, W.claims:state(101, 5001))
    end)
    it('a live animal is refused', function()
        local W = world({ carcassPatch = { dead = false } })
        eq('fh_not_dead', select(2, W.skin()))
        eq(0, #W.adds); eq(nil, W.claims:state(101, 5001))
    end)
    it('unknown netId, a player ped, a non-huntable model, no character are refused', function()
        eq('fh_no_carcass', select(2, world().skinner.skin(SRC, { netId = 102 })))
        eq('fh_no_carcass', select(2, world({ carcassPatch = { isPlayer = true } }).skin()))
        eq('fh_not_huntable', select(2, world({ model = A.joaat('a_c_horse_morgan_bay') }).skin()))
        eq('fh_no_character', select(2, world().skinner.skin(99, { netId = 101 })))
    end)
end)

describe('hunting skin: cargo needs a wagon', function()
    it('a bear with no wagon is refused, the claim released, and it is skinnable again', function()
        local W = world({ model = BEAR })
        local ok, why = W.skin()
        eq(false, ok); eq('fh_no_wagon', why)
        eq(0, #W.adds); eq(nil, W.claims:state(101, 5001)); eq(0, #W.finished)
        assert(S.message(why, cfg):find('8 m'), S.message(why, cfg))
        W.wagon = wagonAt(5)
        local ok2, res = W.skin()
        assert(ok2, tostring(res)); eq('wagon', res.container); eq('pelt_bear', res.item)
    end)
    it('a wagon beyond WagonRange of the player does not count', function()
        local W = world({ model = BEAR, wagon = wagonAt(cfg.WagonRange + 1) })
        eq('fh_no_wagon', select(2, W.skin())); eq(0, #W.adds)
    end)
    it('a bear never goes to the saddlebag', function()
        local W = world({ model = BEAR, wagon = wagonAt(3) })
        assert(W.skin())
        eq(1, #W.adds); eq('wagon', W.adds[1].ref.type)
    end)
end)

describe('hunting skin: bulky grant and fallback', function()
    it('saddlebag full falls back to a wagon in range', function()
        local W = world({ wagon = wagonAt(4), refuse = { saddlebag = 'no_space' } })
        local ok, res = W.skin()
        assert(ok, tostring(res)); eq('wagon', res.container)
        eq(2, #W.adds); eq('saddlebag', W.adds[1].ref.type); eq('wagon', W.adds[2].ref.type)
    end)
    it('no saddlebag and no wagon: refused with fh_no_container, claim released', function()
        local W = world({ saddlebag = false })
        eq('fh_no_container', select(2, W.skin())); eq(nil, W.claims:state(101, 5001))
    end)
end)

describe('hunting skin: addItem failure releases the claim', function()
    it('every destination refusing releases the claim and keeps the carcass', function()
        local W = world({ refuse = { saddlebag = 'no_space' } })
        local ok, why = W.skin()
        eq(false, ok); eq('no_space', why)
        eq(nil, W.claims:state(101, 5001)); eq(0, #W.finished)
        W.refuse = {}
        assert(W.skin())
    end)
    it('an addItem that throws releases the claim', function()
        local W = world()
        W.deps.addItem = function() error('boom') end
        eq('fh_skin_error', select(2, W.skin())); eq(nil, W.claims:state(101, 5001))
    end)
end)

describe('hunting skin: quality inputs', function()
    it('multi-hit and explosive give 1 star', function()
        eq(1, select(2, world().skin({ netId = 101, bone = 'skel_head', hits = 3 })).stars)
        eq(1, select(2, world().skin({ netId = 101, bone = 'skel_head', explosive = true })).stars)
    end)
    it('native source uses the native values, and falls back to the roll when the client sent none', function()
        local c = setmetatable({ PeltQualitySource = 'native' }, { __index = cfg })
        local W = world()
        W.skinner = S.new({ cfg = c, animals = A, quality = Q, claims = W.claims, deps = W.deps })
        eq(2, select(2, W.skinner.skin(SRC, { netId = 101, bone = 'skel_head', nativeQuality = 1, cleanliness = 0 })).stars)
        local W2 = world()
        W2.skinner = S.new({ cfg = c, animals = A, quality = Q, claims = W2.claims, deps = W2.deps })
        eq(3, select(2, W2.skinner.skin(SRC, { netId = 101, bone = 'skel_head' })).stars)
    end)
end)

describe('hunting skin: fh:hunting:pelt_skinned', function()
    it('fires once on a grant with the agreed payload', function()
        local W = world()
        assert(W.skin({ netId = 101, bone = 'skel_spine1' }))
        eq(1, #W.events)
        eq('fh:hunting:pelt_skinned', W.events[1].name)
        same({ src = SRC, citizenid = CID, item_id = 'pelt_deer', animal = 'deer', quality = 2, size_class = 'bulky' },
            W.events[1].payload)
    end)
    it('cargo grant carries size_class cargo', function()
        local W = world({ model = BEAR, wagon = wagonAt(2) })
        assert(W.skin())
        eq('cargo', W.events[1].payload.size_class); eq('bear', W.events[1].payload.animal)
    end)
    it('never fires on a refusal or a failure', function()
        local cases = {
            world({ carcassPatch = { dead = false } }),
            world({ carcassPatch = { coords = { x = 50, y = 0, z = 0 } } }),
            world({ model = BEAR }),
            world({ refuse = { saddlebag = 'no_space' } }),
        }
        for i, W in ipairs(cases) do
            assert(not W.skin(), 'case ' .. i)
            eq(0, #W.events, 'case ' .. i)
        end
        local W = world()
        assert(W.skin()); assert(not W.skin())
        eq(1, #W.events, 'duplicate')
    end)
end)

describe('hunting skin: legendary bear pelt + trophy', function()
    local function legendaryWorld(w)
        w = w or {}
        w.model = BEAR
        w.carcassPatch = w.carcassPatch or {}
        w.carcassPatch.legendary = true
        w.carcassPatch.legendaryOwner = w.legendaryOwner or CID
        w.legendaryOwner = nil
        return world(w)
    end

    it('grants the cargo 3-star pelt to the wagon and the bulky trophy to the saddlebag', function()
        local W = legendaryWorld({ wagon = wagonAt(2) })
        local ok, res = W.skin()
        assert(ok, tostring(res))
        eq('pelt_legendary_bear', res.item); eq(3, res.stars); eq('wagon', res.container)
        eq('trophy_legendary_bear', res.trophy.item); eq('saddlebag', res.trophy.container)
        eq(2, #W.adds)
        eq('pelt_legendary_bear', W.adds[1].name); eq('wagon', W.adds[1].ref.type); same({ stars = 3 }, W.adds[1].info)
        eq('trophy_legendary_bear', W.adds[2].name); eq('saddlebag', W.adds[2].ref.type)
        same({ src = SRC, citizenid = CID, item_id = 'pelt_legendary_bear', animal = 'legendary_bear',
            quality = 3, size_class = 'cargo' }, W.events[1].payload)
    end)
    it('refuses a non-owner (no cross-player legendary farming)', function()
        local W = legendaryWorld({ wagon = wagonAt(2), legendaryOwner = 'OTHER' })
        eq('fh_not_your_legendary', select(2, W.skin()))
        eq(0, #W.adds); eq(0, #W.events)
    end)
    it('the trophy falls back to the wagon when the saddlebag is full', function()
        local W = legendaryWorld({ wagon = wagonAt(2), refuse = { saddlebag = 'no_space' } })
        local ok, res = W.skin()
        assert(ok)
        eq('pelt_legendary_bear', res.item); eq('wagon', res.container)
        eq('wagon', res.trophy.container)
        -- The pelt (cargo) goes straight to the wagon; the trophy (bulky) tries the saddlebag, is refused,
        -- and falls back to the wagon: three addItem calls, the failed saddlebag attempt included.
        eq(3, #W.adds)
        eq('pelt_legendary_bear', W.adds[1].name); eq('wagon', W.adds[1].ref.type)
        eq('trophy_legendary_bear', W.adds[2].name); eq('saddlebag', W.adds[2].ref.type)
        eq('trophy_legendary_bear', W.adds[3].name); eq('wagon', W.adds[3].ref.type)
    end)
    it('a throwing trophy grant still completes the pelt without double-paying', function()
        local W = legendaryWorld({ wagon = wagonAt(2) })
        local origAdd = W.deps.addItem
        W.deps.addItem = function(ref, name, n, info)
            if name == 'trophy_legendary_bear' then error('boom') end
            return origAdd(ref, name, n, info)
        end
        local ok, res = W.skin()
        assert(ok, tostring(res))
        eq('pelt_legendary_bear', res.item)
        eq('fh_skin_error', res.trophy.reason)
        eq(1, #W.adds) -- only the pelt; the trophy addItem threw before recording
        eq('skinned', W.claims:state(101, 5001)) -- the carcass never pays again
    end)
end)

T.finish()
