-- fh_cargo wagon post services (roads-04 R17): call / stow / menu data at a trade post. Pure Lua: natives, exports and
-- the live-wagon table come in through `deps`, so spec/cargo_post_spec.lua drives this exact code with fakes.
--
-- Invariants:
--  1. Server-side proximity only: the post comes from deps.nearestPost(src) (fh_trade, same radius check as selling,
--     from the ped coords the server reads). Client coords and client post ids are never trusted.
--  2. One live wagon per player (any tier, including a spawn still in flight). CALL while one is live is REFUSED
--     ('fh_wagon_live', detail = its tier): refusing can never lose cargo, and stow is the explicit way to put it away.
--  3. CALL needs the tier OWNED (fh_wagons) and then goes through the normal spawnWagon, which keeps the wagon_t2/t3
--     rep gate. The stash id is deterministic (rules.wagonId) so cargo is kept.
--  4. STOW needs the player at a post AND the wagon within post.radius + cfg.StowMargin of that post (so no stowing
--     from across the map). It only despawns the entity (deps.stow); the container is never touched, cargo stays.
--  5. One action per player at a time (locks keyed by src and citizenid), always released.
local M = {}

local function finite(n) return type(n) == 'number' and n == n and n > -math.huge and n < math.huge end

---A usable post: { id, region, radius, x, y } (+ z, label). nil otherwise.
local function validPost(p)
    if type(p) ~= 'table' or type(p.id) ~= 'string' or p.id == '' then return nil end
    if type(p.region) ~= 'string' or p.region == '' then return nil end
    if not finite(p.x) or not finite(p.y) or not finite(p.radius) or p.radius <= 0 then return nil end
    return p
end

---Distance from `coords` to the post (3D when the post has a z).
function M.distToPost(post, coords)
    local dx, dy = coords.x - post.x, coords.y - post.y
    local dz = finite(post.z) and finite(coords.z) and (coords.z - post.z) or 0
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function lock(locks, src, cid)
    local kS, kC = 'src:' .. src, 'cid:' .. cid
    if locks[kS] or locks[kC] then return nil end
    locks[kS], locks[kC] = true, true
    return function() locks[kS], locks[kC] = nil, nil end
end

---Common front: src, character, post. -> cid, post | nil, err
local function front(deps, src)
    if type(src) ~= 'number' or src <= 0 then return nil, 'fh_no_player' end
    local cid = deps.citizenid(src)
    if not cid then return nil, 'fh_no_character' end
    local post = validPost(deps.nearestPost(src))
    if not post then return nil, 'fh_not_at_post' end
    return cid, post
end

---Call an owned tier to the post. -> true, { wagon, tier, post } | false, err, detail
function M.call(cfg, rules, deps, locks, src, tierArg)
    local tier = rules.parseTier(tierArg)
    if not tier then return false, 'fh_bad_tier' end
    local cid, post = front(deps, src)
    if not cid then return false, post end
    local release = lock(locks, src, cid)
    if not release then return false, 'fh_busy' end
    local ok, a, b, c = pcall(function()
        local owned = deps.owned(cid, tier.key) -- may yield
        if owned == nil then return false, 'fh_db_error' end
        if owned ~= true then return false, 'fh_not_owned' end
        -- re-check after the yield: same character, still at a post
        if deps.citizenid(src) ~= cid then return false, 'fh_no_character' end
        if not validPost(deps.nearestPost(src)) then return false, 'fh_not_at_post' end
        local live = deps.live(cid)
        if live then return false, 'fh_wagon_live', live.tier end
        local at = deps.spawnPoint(src)
        if not at then return false, 'fh_no_player' end
        local id, err = deps.spawn(src, tier.key, at) -- keeps the wagon_t2/t3 rep gate
        if not id then return false, err or 'fh_spawn_failed' end
        return true, { wagon = id, tier = tier.key, post = post.id }
    end)
    release()
    if not ok then
        deps.log('ERROR wagon call: ' .. tostring(a))
        return false, 'fh_call_error'
    end
    return a, b, c
end

---Stow the live wagon (must be near the post). Cargo is kept. -> true, { wagon, tier, post } | false, err
function M.stow(cfg, rules, deps, locks, src)
    local cid, post = front(deps, src)
    if not cid then return false, post end
    local release = lock(locks, src, cid)
    if not release then return false, 'fh_busy' end
    local ok, a, b = pcall(function()
        local live = deps.live(cid)
        if not live then return false, 'fh_no_wagon' end
        if not live.coords then return false, 'fh_wagon_not_ready' end -- still spawning
        local margin = tonumber(cfg.StowMargin) or 10.0
        if M.distToPost(post, live.coords) > post.radius + margin then return false, 'fh_wagon_far' end
        local sok, serr = deps.stow(live) -- despawn the entity only; the container is never cleared
        if not sok then return false, serr or 'fh_stow_failed' end
        return true, { wagon = live.id, tier = live.tier, post = post.id }
    end)
    release()
    if not ok then
        deps.log('ERROR wagon stow: ' .. tostring(a))
        return false, 'fh_stow_error'
    end
    return a, b
end

---Buy at the post: the post's region is the charge region (never a client value). Same busy lock as the others.
function M.buy(cfg, rules, deps, locks, src, tierArg)
    local tier = rules.parseTier(tierArg)
    if not tier then return false, 'fh_bad_tier' end
    local cid, post = front(deps, src)
    if not cid then return false, post end
    local release = lock(locks, src, cid)
    if not release then return false, 'fh_busy' end
    local ok, a, b = pcall(deps.buy, src, tier.key, post.region)
    release()
    if not ok then
        deps.log('ERROR wagon post buy: ' .. tostring(a))
        return false, 'fh_buy_error'
    end
    return a == true, b
end

---Menu rows for the post screen. -> { post, live, tiers = { { key, label, price, owned, locked, reason } } } | nil, err
function M.menu(cfg, rules, deps, src)
    local cid, post = front(deps, src)
    if not cid then return nil, post end
    local set = deps.ownedSet(cid)
    if set == nil then return nil, 'fh_db_error' end
    local live = deps.live(cid)
    local tiers = {}
    for _, key in ipairs(rules.ORDER) do
        local t = rules.TIERS[key]
        local row = { key = key, label = t.label, price = rules.wagonPrice(cfg.Prices, key), owned = set[key] == true }
        local unlockId = rules.unlockForTier(key)
        if unlockId and not row.owned then
            local callOk, uok, ureason = pcall(deps.canUnlock, src, unlockId)
            local allowed, why = rules.wagonTierGate(key, callOk, uok, ureason)
            if not allowed then row.locked, row.reason = true, why end
        end
        tiers[#tiers + 1] = row
    end
    return { post = { id = post.id, label = post.label, region = post.region },
        live = live and { id = live.id, tier = live.tier } or nil, tiers = tiers }
end

if GetCurrentResourceName then
    FhCargoPost = M
else
    return M
end
