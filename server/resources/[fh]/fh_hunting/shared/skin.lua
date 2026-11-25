-- fh_hunting skin flow (spec L8, H2). Pure Lua, no natives: the carcass claim registry, the client-payload sanitizer,
-- the pelt destination plan and the whole server-side skin decision. server/main.lua injects every native and export
-- (deps below), so spec/hunting_skin_spec.lua runs the real flow.
--
-- Anti-duplication invariant: a carcass is claimed by a test-and-set (Claims:claim) right after the plausibility
-- check, with no call out and no yield in between, BEFORE the first export call (addItem may yield or re-enter). A second
-- request for the same carcass, in the same tick or re-entered from inside addItem, finds the claim and is refused.
-- Every exit after the claim either releases it (refusal / failure: the carcass stays skinnable) or marks it skinned
-- (grant: the carcass never pays again).
local M = {}

M.EVENT_SKINNED = 'fh:hunting:pelt_skinned'

local function finite(n) return type(n) == 'number' and n == n and n > -math.huge and n < math.huge end

local function xyz(v)
    if v == nil then return nil end
    local ok, x, y, z = pcall(function() return v.x, v.y, v.z end)
    if not ok or not finite(x) or not finite(y) or not finite(z) then return nil end
    return x, y, z
end

---Distance in metres between two vector3 / {x,y,z}; nil when either is unreadable.
function M.distance(a, b)
    local ax, ay, az = xyz(a)
    local bx, by, bz = xyz(b)
    if not ax or not bx then return nil end
    local dx, dy, dz = ax - bx, ay - by, az - bz
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- ---------------------------------------------------------------- claim registry

local Claims = {}
Claims.__index = Claims

---Claim registry, one entry per carcass netId: { token, state = 'pending' | 'skinned' }.
---token identifies the entity behind the netId (server entity handle): a netId reused by a new entity has another
---token, so a stale entry never blocks it.
function M.newClaims()
    return setmetatable({ entries = {} }, Claims)
end

function Claims:isClaimed(key, token)
    local e = self.entries[key]
    return e ~= nil and e.token == token
end

---Test-and-set. @return boolean claimed (false = someone holds it, or it is already skinned)
function Claims:claim(key, token)
    if key == nil or token == nil then return false end
    local e = self.entries[key]
    if e and e.token == token then return false end
    self.entries[key] = { token = token, state = 'pending' }
    return true
end

---Give a pending claim back (refusal / failure). A skinned carcass is never released.
function Claims:release(key, token)
    local e = self.entries[key]
    if e and e.token == token and e.state == 'pending' then self.entries[key] = nil end
end

function Claims:markSkinned(key, token)
    local e = self.entries[key]
    if e and e.token == token then e.state = 'skinned' end
end

function Claims:state(key, token)
    local e = self.entries[key]
    return e and e.token == token and e.state or nil
end

---Drop entries whose carcass is gone: keep(key, entry) -> boolean. Pending entries are kept (a skin is in flight).
---@return integer dropped
function Claims:prune(keep)
    local n = 0
    for k, e in pairs(self.entries) do
        if e.state ~= 'pending' and not keep(k, e) then
            self.entries[k] = nil
            n = n + 1
        end
    end
    return n
end

-- ---------------------------------------------------------------- client payload

local function intIn(v, lo, hi)
    if not finite(v) or v % 1 ~= 0 or v < lo or v > hi then return nil end
    return math.tointeger(v)
end

---Sanitize the client's skin request. Nothing in it is trusted beyond the quality hints: the carcass, its state and
---every distance are re-read server-side.
---payload = { netId, bone?, hits?, explosive?, nativeQuality?, cleanliness? }
---@return table|nil req, string|nil err
function M.sanitize(payload)
    if type(payload) ~= 'table' then return nil, 'fh_bad_request' end
    local netId = intIn(payload.netId, 1, 0x7FFFFFFF)
    if not netId then return nil, 'fh_bad_request' end
    local req = { netId = netId, explosive = payload.explosive == true }
    local bone = payload.bone
    if type(bone) == 'string' and #bone <= 64 and bone:match('^[%w_]+$') then
        req.bone = bone
    else
        req.bone = intIn(bone, -0x80000000, 0xFFFFFFFF)
    end
    req.hits = intIn(payload.hits, 0, 1000)
    req.nativeQuality = intIn(payload.nativeQuality, 0, 16)
    req.cleanliness = intIn(payload.cleanliness, 0, 16)
    return req
end

-- ---------------------------------------------------------------- destinations

---Container types an item of `sizeClass` may go to, in order: cfg.GrantOrder[sizeClass] filtered by the fh_core
---size-class rules (accepts(type, sizeClass) -> boolean). A backpack listed for a bulky pelt is dropped here (§4.1).
function M.targetsFor(sizeClass, cfg, accepts)
    local out = {}
    for _, t in ipairs((cfg.GrantOrder or {})[sizeClass] or {}) do
        if accepts(t, sizeClass) then out[#out + 1] = t end
    end
    return out
end

---H8: raw_meat count for an animal from cfg.MeatPerSize (keyed by animal.size_class). Returns 0 if unconfigured.
function M.meatAmount(animal, cfg)
    local tbl = cfg and cfg.MeatPerSize
    local n = tbl and animal and tbl[animal.size_class]
    if type(n) == 'number' and n > 0 and n % 1 == 0 then return math.tointeger(n) end
    return 0
end

-- ---------------------------------------------------------------- player messages

local MESSAGES = {
    fh_already_claimed = 'This carcass is already being skinned, or has been.',
    fh_not_dead = 'It is still alive.',
    fh_too_far = 'Get closer to the carcass.',
    fh_no_carcass = 'There is nothing here to skin.',
    fh_not_huntable = 'There is nothing here to skin.',
    fh_no_container = 'Nowhere to put the pelt: you need your saddlebag or a wagon nearby.',
    fh_size_class = 'No room for the pelt in your saddlebag or a wagon.',
    fh_not_your_legendary = 'This legendary beast is not yours to claim.',
    no_space = 'No room for the pelt in your saddlebag or a wagon.',
    too_heavy = 'No room for the pelt in your saddlebag or a wagon.',
    fh_too_heavy = 'No room for the pelt in your saddlebag or a wagon.',
    fh_no_slot = 'No room for the pelt in your saddlebag or a wagon.',
}

---Player-facing text for a refusal code.
function M.message(reason, cfg)
    if reason == 'fh_no_wagon' then
        return ('This pelt is too big to carry: skin it with a wagon within %d m.'):format(math.floor((cfg and cfg.WagonRange) or 8))
    end
    return MESSAGES[reason] or ('Could not skin: ' .. tostring(reason))
end

-- ---------------------------------------------------------------- the skin decision

---Build a skinner. opts = {
---  cfg, animals (FhHuntingAnimals), quality (FhHuntingQuality), claims (M.newClaims()),
---  deps = {
---    citizenid(src)            -> string|nil
---    playerCoords(src)         -> coords|nil            (server-side ped position)
---    readCarcass(netId)        -> nil | { entity, isPed, isPlayer, model, coords, dead, legendary }
---    saddlebagOf(src)          -> container ref|nil
---    findCargoWagon(src)       -> nil | { ref, coords }  (a wagon the player owns or uses)
---    addItem(ref, name, n, info) -> ok, err
---    accepts(type, sizeClass)  -> boolean               (FhContainers.accepts)
---    finishCarcass(entity, netId)                       (mark skinned / delete; after a grant only)
---    releaseSpawn(netId)                                (optional; after a grant: end the fh_core spawn lifecycle)
---    emit(name, payload)                                (server-only TriggerEvent)
---    rng()                     -> [0,1)
---  } }
function M.new(opts)
    local cfg, animals, quality, claims, deps = opts.cfg, opts.animals, opts.quality, opts.claims, opts.deps
    local S = { claims = claims }

    local function refOf(t, src, pc)
        if t == 'saddlebag' then
            return deps.saddlebagOf(src)
        elseif t == 'wagon' then
            local w = deps.findCargoWagon(src)
            local d = w and M.distance(w.coords, pc)
            if w and w.ref and d and d <= cfg.WagonRange then return w.ref end
            return nil
        elseif t == 'backpack' then
            return { type = 'backpack', id = src }
        end
        return nil
    end

    local function stars(req, animal)
        local input = {
            legendary = animal.legendary == true, source = cfg.PeltQualitySource, bone = req.bone, hits = req.hits,
            explosive = req.explosive, nativeQuality = req.nativeQuality, cleanliness = req.cleanliness, rng = deps.rng,
        }
        local ok, s, detail = quality.resolve(input, cfg)
        if not ok and input.source == 'native' and s == 'fh_no_native_quality' then
            input.source = 'roll' -- the client could not read the natives: fall back to the bone roll
            ok, s, detail = quality.resolve(input, cfg)
        end
        return ok, s, detail
    end

    -- Grant an item into the player's containers for `sizeClass` (the same targetsFor path for every skinned item).
    -- Returns ok, { item, amount, container }|reason, granted. `not any` distinguishes "no such container" (fh_no_wagon
    -- / fh_no_container) from "every container refused" (lastErr).
    local function grantItem(src, sizeClass, itemName, info, pc, amount)
        amount = amount or 1
        local lastErr, any = nil, false
        for _, t in ipairs(M.targetsFor(sizeClass, cfg, deps.accepts)) do
            local ref = refOf(t, src, pc)
            if ref then
                any = true
                local added, err = deps.addItem(ref, itemName, amount, info)
                if added == true then return true, { item = itemName, amount = amount, container = t }, true end
                lastErr = err or 'fh_refused'
            end
        end
        if not any then return false, sizeClass == 'cargo' and 'fh_no_wagon' or 'fh_no_container', false end
        return false, lastErr, false
    end

    -- Runs while holding the claim. Returns ok, result|reason, granted (true once the pelt addItem succeeded).
    local function grant(src, req, animal, pc)
        local ok, s, detail = stars(req, animal)
        if not ok then return false, s, false end
        local pok, pres = grantItem(src, animal.size_class, animal.pelt, { stars = s }, pc, 1)
        if not pok then return false, pres, false end
        local res = { item = pres.item, stars = s, container = pres.container, zone = detail and detail.zone }
        -- H4: a legendary skin also yields the trophy (bulky, saddlebag then wagon). It is best-effort: the pelt is
        -- the primary grant and the skin never fails (or double-pays) because of a full saddlebag. A throw here must
        -- not abort the grant after the pelt was added, so the trophy path is pcalled.
        if animal.trophy then
            local tok, tgrant, tres = pcall(grantItem, src, 'bulky', animal.trophy, {}, pc, 1)
            if tok and tgrant then
                res.trophy = { item = tres.item, container = tres.container }
            elseif tok then
                res.trophy = { item = animal.trophy, container = nil, reason = tres }
            else
                res.trophy = { item = animal.trophy, container = nil, reason = 'fh_skin_error' }
            end
        end
        -- H8: skinning also yields rsg-core raw_meat (pocket size_class, amount by animal size_class). Best-effort
        -- after the pelt succeeds: if no container has room (or addItem throws), the pelt grant still stands.
        local meatCount = M.meatAmount(animal, cfg)
        if meatCount > 0 then
            local meatItem = cfg.MeatItem or 'raw_meat'
            local meatSize = cfg.MeatSizeClass or 'pocket'
            local mok, mgrant, mres = pcall(grantItem, src, meatSize, meatItem, {}, pc, meatCount)
            if mok and mgrant then
                res.meat = { item = mres.item, amount = meatCount, container = mres.container }
            elseif mok then
                res.meat = { item = meatItem, amount = 0, wanted = meatCount, container = nil, reason = mres }
            else
                res.meat = { item = meatItem, amount = 0, wanted = meatCount, container = nil, reason = 'fh_skin_error' }
            end
        end
        return true, res, true
    end

    ---@return boolean ok, table|string resultOrReason  result = { item, stars, container, zone? }
    function S.skin(src, payload)
        local req, err = M.sanitize(payload)
        if not req then return false, err end
        local cid = deps.citizenid(src)
        if not cid then return false, 'fh_no_character' end
        local pc = deps.playerCoords(src)
        if not pc then return false, 'fh_no_player' end
        local car = deps.readCarcass(req.netId)
        if not car or car.entity == nil or not car.isPed or car.isPlayer then return false, 'fh_no_carcass' end
        local animal = animals.get(car.model, car.legendary)
        if not animal then return false, 'fh_not_huntable' end
        -- H4: a legendary carcass belongs to the character whose chain spawned it; nobody else may skin it (prevents
        -- cross-player farming of the always-3-star legendary pelt and trophy).
        if animal.legendary and car.legendaryOwner and car.legendaryOwner ~= cid then
            return false, 'fh_not_your_legendary'
        end

        local key, token = req.netId, car.entity
        local okP, why = quality.plausibility({
            dead = car.dead == true, distance = M.distance(car.coords, pc), claimed = claims:isClaimed(key, token),
        }, cfg)
        if not okP then return false, why end
        -- No call out between the check above and this test-and-set.
        if not claims:claim(key, token) then return false, 'fh_already_claimed' end

        local granted = false
        local pok, ok, res = pcall(function()
            local o, r, g = grant(src, req, animal, pc)
            granted = g
            return o, r
        end)
        if not pok then
            ok, res = false, 'fh_skin_error'
        end
        if not ok and not granted then
            claims:release(key, token)
            return false, res
        end

        -- Granted (even if something after the addItem threw): the carcass never pays again.
        claims:markSkinned(key, token)
        pcall(deps.finishCarcass, car.entity, key)
        if deps.releaseSpawn then pcall(deps.releaseSpawn, req.netId) end -- H7: end the fh_core lifecycle, never fatal
        if type(res) ~= 'table' then return true, { item = animal.pelt } end
        pcall(deps.emit, M.EVENT_SKINNED, {
            src = src, citizenid = cid, item_id = animal.pelt, animal = animal.key, quality = res.stars,
            size_class = animal.size_class, meat = (res.meat and res.meat.amount) or 0,
        })
        return true, res
    end

    return S
end

---H7: end the fh_core spawn lifecycle of a skinned carcass so an adopted animal is not re-requested. Wild animals and
---unadopted entities map to no request (nil) and are left alone. Never throws; failures only warn.
---@param netId number
---@param core { requestOfNetId: fun(netId:number):string|number|nil, despawn: fun(id:string|number) }
---@param warn? fun(msg:string)
---@return boolean despawned
function M.releaseSpawn(netId, core, warn)
    warn = warn or function() end
    local ok, id = pcall(core.requestOfNetId, netId)
    if not ok then warn('requestOfNetId failed: ' .. tostring(id)); return false end
    if not id then return false end
    local dok, derr = pcall(core.despawn, id)
    if not dok then warn('despawn failed: ' .. tostring(derr)); return false end
    return true
end

if GetCurrentResourceName then
    FhHuntingSkin = M
else
    return M
end
