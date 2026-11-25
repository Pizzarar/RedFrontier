-- Pure freight-contract rules (spec L6, roads R4). No natives, no DB, no clock: callers pass `now` (unix seconds),
-- the config and gathered facts, so everything is deterministic and specced (spec/freight_spec.lua).
-- Contracts are a fh_quests job type ('freight'); the quest id is job:freight:<key>.
local M = {}

M.JOB_TYPE = 'freight'
M.QUEST_PREFIX = 'job:freight:'
M.EVENT_DELIVERED = 'fh:trade:contract_delivered'
M.EVENT_FAILED = 'fh:trade:contract_failed'
M.EVENTS = { M.EVENT_DELIVERED, M.EVENT_FAILED }

local function finite(n) return type(n) == 'number' and n == n and n > -math.huge and n < math.huge end
local function int(n) return finite(n) and n % 1 == 0 end

function M.questId(key) return M.QUEST_PREFIX .. key end

---Key out of a quest id, or nil when it is not a freight quest id.
function M.keyOf(questId)
    if type(questId) ~= 'string' or questId:sub(1, #M.QUEST_PREFIX) ~= M.QUEST_PREFIX then return nil end
    local k = questId:sub(#M.QUEST_PREFIX + 1)
    return k ~= '' and k or nil
end

---Stable per template: same (from, to, item, tier) = same key. fh_quests ids are <= 64 chars of [A-Za-z0-9_.:-].
---T1 keys are unchanged (`from.to.item`); T2 keys get a `.t2` suffix so both tiers can sit on one board.
function M.offerKey(from, to, item, tier)
    local k = ('%s>%s>%s'):format(from, to, item):gsub('>', '.')
    if tier == 2 then k = k .. '.t2' end
    return k
end

M.T2_UNLOCK = 'contracts_t2'

---T2 settings (roads-02 R9) or nil when T2 freight is not configured.
local function t2cfg(cfg)
    local t = (cfg.freight or {}).t2
    return type(t) == 'table' and t or nil
end

---Offer tier, 1 when absent (offers generated before T2 existed). 1 and 2 are the only tiers.
---A present non-number tier (false, 0, '2', ...) is returned as-is so validateOffer reports bad_tier.
function M.tierOf(offer)
    if type(offer) ~= 'table' or offer.tier == nil then return 1 end
    return offer.tier
end

---fh_progression unlock id gating a tier, or nil (T1 is never gated).
function M.unlockFor(cfg, tier)
    if tier ~= 2 then return nil end
    local t = t2cfg(cfg)
    return t and t.unlock or M.T2_UNLOCK
end

---Smallest wagon tier number (fh_cargo TIERS[*].tier) a contract tier needs. T1: 1 (any wagon).
function M.minWagonTier(cfg, tier)
    if tier ~= 2 then return 1 end
    local t = t2cfg(cfg)
    return t and t.minWagonTier or 2
end

local function excludeSet(f)
    local set = {}
    local ex = type(f) == 'table' and f.exclude
    if type(ex) ~= 'table' then return set end
    for k, v in pairs(ex) do
        if type(k) == 'number' and type(v) == 'string' and v ~= '' then
            set[v] = true
        elseif type(k) == 'string' and k ~= '' and v == true then
            set[k] = true
        end
    end
    return set
end

local function validDest(d, defaultRadius)
    if type(d) ~= 'table' or not finite(d.x) or not finite(d.y) then return nil end
    local r = finite(d.radius) and d.radius > 0 and d.radius or defaultRadius
    return {
        x = d.x, y = d.y, z = finite(d.z) and d.z or 0, radius = r,
        post = type(d.post) == 'string' and d.post or nil,
    }
end

local function postCoords(p, rposts)
    if type(p) ~= 'table' then return nil end
    local rp = rposts and type(p.id) == 'string' and rposts[p.id] or nil
    local region = (type(p.region) == 'string' and p.region ~= '' and p.region)
        or (rp and type(rp.region) == 'string' and rp.region ~= '' and rp.region)
        or nil
    local x = finite(p.x) and p.x or (rp and finite(rp.x) and rp.x or nil)
    local y = finite(p.y) and p.y or (rp and finite(rp.y) and rp.y or nil)
    local z = finite(p.z) and p.z or (rp and finite(rp.z) and rp.z or 0)
    return region, x, y, z
end

---Resolve freight destinations (region_id -> { x, y, z, radius, post? }) from `cfg.posts` (filled from FhRegions.posts
---at load, or via the optional `regions` table) plus per-region `freight.overrides` and `freight.exclude` (roads-03 R12).
---Only regions with >= 1 post get destinations (legacy `freight.destinations` is still read as a fallback when no post
---supplied the region). Posts/entries with missing coords are skipped (never throw).
function M.resolveDestinations(cfg, regions)
    local f = type(cfg) == 'table' and type(cfg.freight) == 'table' and cfg.freight or {}
    local defaultRadius = (finite(f.destinationRadius) and f.destinationRadius > 0) and f.destinationRadius or 40.0
    local excluded = excludeSet(f)
    local dests, hasPost, byPostId = {}, {}, {}
    local rposts = type(regions) == 'table' and type(regions.posts) == 'table' and regions.posts or nil
    local hasPostsList = type(cfg) == 'table' and type(cfg.posts) == 'table'

    if hasPostsList then
        for _, p in ipairs(cfg.posts) do
            local region, x, y, z = postCoords(p, rposts)
            if type(p) == 'table' and type(p.id) == 'string' and p.id ~= '' and x and y then
                byPostId[p.id] = { x = x, y = y, z = z, region = region, post = p.id }
            end
            if region then
                hasPost[region] = true
                if not excluded[region] and not dests[region] and x and y then
                    dests[region] = { x = x, y = y, z = z, radius = defaultRadius, post = type(p.id) == 'string' and p.id or nil }
                end
            end
        end
    end

    if type(f.destinations) == 'table' then
        for region, d in pairs(f.destinations) do
            if type(region) == 'string' and region ~= '' and not excluded[region] and not dests[region] then
                local v = validDest(d, defaultRadius)
                if v then dests[region] = v end
            end
        end
    end

    if type(f.overrides) == 'table' then
        for region, ov in pairs(f.overrides) do
            if type(region) == 'string' and region ~= '' and not excluded[region] and type(ov) == 'table' then
                if not hasPostsList or hasPost[region] or dests[region] then
                    local base = dests[region]
                    if type(ov.post) == 'string' and byPostId[ov.post] then
                        base = byPostId[ov.post]
                    end
                    local merged = {
                        x = ov.x ~= nil and ov.x or (base and base.x),
                        y = ov.y ~= nil and ov.y or (base and base.y),
                        z = ov.z ~= nil and ov.z or (base and base.z),
                        radius = ov.radius ~= nil and ov.radius or (base and base.radius),
                        post = ov.post ~= nil and ov.post or (base and base.post),
                    }
                    dests[region] = validDest(merged, defaultRadius)
                end
            end
        end
    end

    return dests
end

---Resolved freight destination for one region, or nil when excluded / no post / missing coords.
function M.destinationFor(cfg, region, regions)
    if type(region) ~= 'string' or region == '' then return nil end
    return M.resolveDestinations(cfg, regions)[region]
end

local function defaults(cfg)
    local f = cfg.freight or {}
    return {
        minQty = f.minQty or 1, maxQty = f.maxQty or 20, qtyPerLevel = f.qtyPerLevel or 20,
        premium = f.premium or 1.25, repDelta = f.repDelta or 2, deadlineSeconds = f.deadlineSeconds or 1800,
        maxOffers = f.maxOffers or 3, cooldownMin = f.cooldownMin or 30, rewardCap = f.rewardCapMultiple or 4,
        allowSameRegion = f.allowSameRegion == true,
        minDistance = (finite(f.minDistance) and f.minDistance >= 0) and f.minDistance or 0,
    }
end

local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end

local function dist2d(a, b)
    if type(a) ~= 'table' or type(b) ~= 'table' or not finite(a.x) or not finite(a.y) or not finite(b.x) or not finite(b.y) then return nil end
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

---Horizontal route length (m) between two regions' freight destinations, or nil when either has none.
function M.routeDistance(cfg, from, to, regions)
    local dest = M.resolveDestinations(cfg, regions)
    return dist2d(dest[from], dest[to])
end

---T2 deadline (s): deadlineBase + distance * deadlinePerMeter, whole seconds, clamped to 60..86400.
function M.t2Deadline(cfg, distance)
    local t = t2cfg(cfg) or {}
    local s = math.floor((t.deadlineBase or 900) + distance * (t.deadlinePerMeter or 1.0))
    return clamp(s, 60, 86400)
end

---Matching T1 qty for a shortage level: clamp(ceil(level * qtyPerLevel), minQty, maxQty). Shared by T1 generation and as
---the reference quantity T2 pay scales from.
local function t1Qty(d, level)
    return clamp(math.ceil(clamp(level, 0, 1) * d.qtyPerLevel), d.minQty, d.maxQty)
end

---Matching T1 pay for a shortage level: floor(t1Qty * price * premium). T2 pays a multiple of this, so pay keeps
---following the goods' value (whiskey > cloth > salt) instead of inverting on the bigger T2 quantities.
local function t1Pay(d, level, price)
    return math.floor(t1Qty(d, level) * price * d.premium)
end

---T2 qty for a shortage level: clamp(ceil(level * qtyPerLevel), minQty, min(maxQty, floor(maxLoad / weight))).
---Capped by the t2 wagon's SLOTS (maxQty) and by the load in grams (maxLoad / weight), never by weight alone.
---nil when the good is missing, too heavy to even carry minQty, or the T2 qty settings are unusable.
local function t2Qty(t, good, level)
    if type(t) ~= 'table' or not int(t.minQty) or not int(t.maxQty) or not int(t.qtyPerLevel) then return nil end
    if t.minQty < 1 or t.maxQty < t.minQty or t.qtyPerLevel < 1 then return nil end
    local cap = t.maxQty
    local w = type(good) == 'table' and good.weight
    if finite(w) and w > 0 and finite(t.maxLoad) and t.maxLoad > 0 then
        cap = math.min(cap, math.floor(t.maxLoad / w))
    end
    if cap < t.minQty then return nil end
    return clamp(math.ceil(clamp(finite(level) and level or 0, 0, 1) * t.qtyPerLevel), t.minQty, cap)
end

---T2 offers for one route: one per shortage with a qty template, only on routes of at least minDistance.
local function t2Offers(cfg, d, fromRegion, to, dist, list, out)
    local t = t2cfg(cfg)
    if not t then return end
    if not dist or dist < (t.minDistance or 0) then return end
    local deadline = M.t2Deadline(cfg, dist)
    local cooldown = math.max(t.cooldownMin or d.cooldownMin, math.ceil(deadline / 60)) -- not re-takeable while one could be live
    local payMult = math.min(t.payMultiple or 3, t.payCapMultiple or 4) -- ~3x the matching T1 pay, never more than the cap
    for _, s in ipairs(list) do
        local good = cfg.goods[s.item]
        if good and finite(s.level) and finite(s.price) then
            local qty = t2Qty(t, good, s.level)
            if qty then
                local reward = math.floor(t1Pay(d, s.level, s.price) * payMult)
                if reward >= 1 then
                    local label = good.label or s.item
                    out[#out + 1] = {
                        key = M.offerKey(fromRegion, to, s.item, 2), tier = 2, locked = true, unlock = M.unlockFor(cfg, 2),
                        min_wagon_tier = M.minWagonTier(cfg, 2),
                        title = ('[T2] Freight: %dx %s to %s'):format(qty, label, to),
                        text = ('Bulk haul: %dx %s from %s to %s (%d m). Needs rep tier 2 for T2 contracts and a wagon (t2) or bigger.')
                            :format(qty, label, fromRegion, to, math.floor(dist)),
                        region_id = fromRegion, from_region = fromRegion, to_region = to,
                        item = s.item, qty = qty, reward = reward, level = s.level, deadline_s = deadline, cooldown_min = cooldown,
                        rewards = { money = reward, rep = { region_id = to, delta = t.repDelta or d.repDelta } },
                    }
                end
            end
        end
    end
end

---Offers for a board at `fromRegion`, one per shortage in the OTHER post regions with valid destination coords and
---horizontal route distance >= that tier's minDistance.
---`shortagesByRegion[region] = fh_trade shortages list { item, level, multiplier, price }`. Pure; worst shortage first.
---T1 offers (tier = 1) are listed first, capped at maxOffers; then T2 offers (tier = 2, freight.t2 configured, routes of
---at least t2.minDistance), capped at t2.maxOffers. fh_quests calls offers(region_id) with no player, so a T2 offer is
---always `locked = true` (gated by `unlock`): the board is shared and the per-player check happens at accept.
---@return table[] offers { key, tier, title, text, from_region, to_region, item, qty, reward, rewards, deadline_s, level, region_id, locked?, unlock?, min_wagon_tier? }
function M.generate(cfg, fromRegion, shortagesByRegion, regions)
    local d, out, t2out = defaults(cfg), {}, {}
    if type(fromRegion) ~= 'string' or fromRegion == '' then return out end
    local dests = M.resolveDestinations(cfg, regions)
    local fromDest = dests[fromRegion]
    if not fromDest then return out end
    local listRegions = {}
    for r in pairs(shortagesByRegion or {}) do listRegions[#listRegions + 1] = r end
    table.sort(listRegions)
    for _, to in ipairs(listRegions) do
        local toDest = dests[to]
        if (to ~= fromRegion or d.allowSameRegion) and toDest then
            local dist = dist2d(fromDest, toDest)
            if dist and dist >= d.minDistance then
                for _, s in ipairs(shortagesByRegion[to]) do
                    local good = cfg.goods[s.item]
                    if good and finite(s.level) and finite(s.price) then
                        local qty = clamp(math.ceil(s.level * d.qtyPerLevel), d.minQty, d.maxQty)
                        local reward = math.floor(qty * s.price * d.premium)
                        if reward >= 1 then
                            local label = good.label or s.item
                            out[#out + 1] = {
                                key = M.offerKey(fromRegion, to, s.item), tier = 1,
                                title = ('Freight: %dx %s to %s'):format(qty, label, to),
                                text = ('Haul %dx %s from %s to %s before time runs out.'):format(qty, label, fromRegion, to),
                                region_id = fromRegion, from_region = fromRegion, to_region = to,
                                item = s.item, qty = qty, reward = reward, level = s.level, deadline_s = d.deadlineSeconds, cooldown_min = d.cooldownMin,
                                rewards = { money = reward, rep = { region_id = to, delta = d.repDelta } },
                            }
                        end
                    end
                end
            end
            t2Offers(cfg, d, fromRegion, to, dist, shortagesByRegion[to], t2out)
        end
    end
    local function worstFirst(a, b) if a.level ~= b.level then return a.level > b.level end return a.key < b.key end
    table.sort(out, worstFirst)
    while #out > d.maxOffers do out[#out] = nil end
    table.sort(t2out, worstFirst)
    local t2max = (t2cfg(cfg) or {}).maxOffers or 2
    for i = 1, math.min(#t2out, t2max) do out[#out + 1] = t2out[i] end
    return out
end

---Re-check an offer that came back through fh_quests (never trust it). @return boolean ok, string? err
function M.validateOffer(cfg, offer, isKnownRegion, regions)
    local d = defaults(cfg)
    if type(offer) ~= 'table' then return false, 'bad_offer' end
    local good = type(offer.item) == 'string' and cfg.goods[offer.item]
    if not good then return false, 'unknown_item' end
    if type(offer.from_region) ~= 'string' or type(offer.to_region) ~= 'string' then return false, 'bad_region' end
    if isKnownRegion and not (isKnownRegion(offer.from_region) and isKnownRegion(offer.to_region)) then return false, 'bad_region' end
    if offer.from_region == offer.to_region and not d.allowSameRegion then return false, 'same_region' end
    local dests = M.resolveDestinations(cfg, regions)
    local excluded = excludeSet(cfg.freight)
    if excluded[offer.from_region] or not dests[offer.to_region] then return false, 'no_destination' end
    if type(cfg.posts) == 'table' and not dests[offer.from_region] then return false, 'no_destination' end
    local tier = M.tierOf(offer)
    if tier ~= 1 and tier ~= 2 then return false, 'bad_tier' end
    local t = t2cfg(cfg)
    if tier == 2 and not t then return false, 'bad_tier' end
    if offer.key ~= M.offerKey(offer.from_region, offer.to_region, offer.item, tier) or #M.questId(offer.key) > 64 then return false, 'bad_key' end
    if tier == 1 then
        if not int(offer.qty) or offer.qty < d.minQty or offer.qty > d.maxQty then return false, 'bad_qty' end
        if d.minDistance > 0 then
            local dist = dist2d(dests[offer.from_region], dests[offer.to_region])
            if not dist or dist < d.minDistance then return false, 'bad_route' end
        end
    else
        if not finite(offer.level) or offer.level <= 0 or offer.level > 1 then return false, 'bad_level' end
        if not int(offer.qty) or offer.qty ~= t2Qty(t, good, offer.level) then return false, 'bad_qty' end
        local dist = dist2d(dests[offer.from_region], dests[offer.to_region])
        if not dist or dist < (t.minDistance or 0) then return false, 'bad_route' end
        if offer.deadline_s ~= M.t2Deadline(cfg, dist) then return false, 'bad_deadline' end
    end
    if tier == 1 then
        if not int(offer.reward) or offer.reward < 1 or offer.reward > offer.qty * good.base * d.rewardCap then return false, 'bad_reward' end
    else
        -- T2 reward scales from the matching T1 pay: at most payCapMultiple x (T1 qty x base x rewardCap).
        local q1 = t1Qty(d, offer.level)
        if not int(offer.reward) or offer.reward < 1 or offer.reward > math.floor((t.payCapMultiple or 4) * q1 * good.base * d.rewardCap) then return false, 'bad_reward' end
    end
    if not int(offer.deadline_s) or offer.deadline_s < 60 or offer.deadline_s > 86400 then return false, 'bad_deadline' end
    return true
end

---Can a wagon of fh_cargo tier row `tierRow` ({ tier, slots, maxWeight }, nil = unreadable) carry this contract?
---Checks the tier number against the contract tier's minimum, then capacity of an EMPTY wagon of that tier: slots
---(a stackable good takes one slot per stack) and qty * good.weight against maxWeight. fh_core canFit then checks the
---real current load. Unreadable tier: T1 passes (canFit still applies), T2 fails closed.
---@return boolean ok, string? err 'fh_freight_wagon_unknown'|'fh_freight_wagon_too_small'
function M.wagonFits(cfg, offer, tierRow)
    local tier = M.tierOf(offer)
    if type(tierRow) ~= 'table' or not int(tierRow.tier) then
        if tier == 1 then return true end
        return false, 'fh_freight_wagon_unknown'
    end
    if tierRow.tier < M.minWagonTier(cfg, tier) then return false, 'fh_freight_wagon_too_small' end
    local good = cfg.goods[offer.item] or {}
    local slots = good.stackable == false and offer.qty or 1
    if finite(tierRow.slots) and slots > tierRow.slots then return false, 'fh_freight_wagon_too_small' end
    if finite(tierRow.maxWeight) and finite(good.weight) and offer.qty * good.weight > tierRow.maxWeight then
        return false, 'fh_freight_wagon_too_small'
    end
    return true
end

---Fail-closed unlock gate (soft dep on fh_progression, fh_fence/fh_hands pcall pattern). `getState` =
---GetResourceState, `canUnlock` = function() returning exports.fh_progression:canUnlock(src, id).
---@return boolean ok, string? why  why = 'not_started'|'threw'|<canUnlock reason>|'denied' (callers refuse 'fh_locked')
function M.checkUnlock(getState, canUnlock)
    local okS, st = pcall(getState, 'fh_progression')
    if not okS or st ~= 'started' then return false, 'not_started' end
    local ok, res, why = pcall(canUnlock)
    if not ok then return false, 'threw' end
    if res ~= true then return false, type(why) == 'string' and why or 'denied' end
    return true
end

---Contract record created at accept.
function M.newContract(offer, citizenid, wagonId, now)
    return {
        key = offer.key, citizenid = citizenid, wagon = wagonId, from_region = offer.from_region, to_region = offer.to_region,
        item = offer.item, qty = offer.qty, reward = offer.reward, accepted_at = now, deadline = now + offer.deadline_s, miss = 0, seen = true, -- seen: its wagon was just used to accept
    }
end

-- RedM hands back vector3 userdata, not tables: read the fields through pcall (same as fh_cargo/shared/cargo_rules.lua).
local function xyz(v)
    if v == nil then return nil end
    local ok, x, y, z = pcall(function() return v.x, v.y, v.z end)
    if not ok or not finite(x) or not finite(y) then return nil end
    return x, y, finite(z) and z or 0
end

---Is `wagonCoords` (table or vector3) inside the destination reach circle?
function M.atTarget(dest, wagonCoords)
    local dx, dy, dz = xyz(dest)
    local wx, wy, wz = xyz(wagonCoords)
    if not dx or not wx then return false end
    local rad = 30.0
    local ok, r = pcall(function() return dest.radius end)
    if ok and finite(r) then rad = r end
    local ex, ey, ez = dx - wx, dy - wy, dz - wz
    return math.sqrt(ex * ex + ey * ey + ez * ez) <= rad
end

---Decide what a periodic check means. facts = { online = boolean, wagon = table|nil (getWagon result with coords),
---owner_ok?, cargoCount = number|nil (nil = unreadable, fail closed), atTarget = boolean }.
---Order: deadline first (always, even offline), then presence, then wagon gone, cargo short, delivery.
---Presence (restart/login safety): while the player is offline, or the wagon has not been seen spawned since the
---restart/login (`c.seen` false), only the deadline applies and the loss counter restarts from 0, so a restart never
---fails a contract by itself. After the wagon is seen, `graceChecks` consecutive "gone/short" reads are tolerated
---(wagon respawn, a moment in a chest) before they count.
---@return string|nil verdict 'delivered'|'timeout'|'wagon_lost'|'cargo_missing'; integer newMiss; boolean seen
function M.evaluate(c, facts, now, graceChecks)
    if not finite(now) or type(c) ~= 'table' or type(facts) ~= 'table' then return nil, c and c.miss or 0, c and c.seen == true end
    if now >= c.deadline then return 'timeout', c.miss or 0, c.seen == true end
    if facts.online ~= true then return nil, 0, false end
    local grace = graceChecks or 3
    local gone = facts.wagon == nil or facts.owner_ok == false
    if gone and c.seen ~= true then return nil, 0, false end -- not spawned since restart/login: wait for it
    local short = not gone and facts.cargoCount ~= nil and facts.cargoCount < c.qty
    if gone or short then
        local miss = (c.miss or 0) + 1
        if miss >= grace then return gone and 'wagon_lost' or 'cargo_missing', miss, true end
        return nil, miss, true
    end
    if facts.cargoCount == nil then return nil, c.miss or 0, true end -- unreadable: hold state
    if facts.atTarget then return 'delivered', 0, true end
    return nil, 0, true
end

---Quest key out of the fh_quests state copy: state.progress.job.key, else state.quest_id (state.id does not exist).
function M.keyOfState(state)
    if type(state) ~= 'table' then return nil end
    local job = type(state.progress) == 'table' and state.progress.job
    if type(job) == 'table' and type(job.key) == 'string' and job.key ~= '' then return job.key end
    return M.keyOf(state.quest_id)
end

---fh_quests onEvent hook mapping. Only our two events, and only for this quest (state.quest_id must equal
---job:freight:<payload.key>; fh_quests already filtered to events crediting the holder).
---@return string|nil 'complete'|'fail'|nil
function M.eventVerdict(name, payload, state)
    if type(payload) ~= 'table' or type(payload.key) ~= 'string' then return nil end
    if name ~= M.EVENT_DELIVERED and name ~= M.EVENT_FAILED then return nil end
    if type(state) ~= 'table' or state.quest_id ~= M.questId(payload.key) then return nil end
    return name == M.EVENT_DELIVERED and 'complete' or 'fail'
end

---Soft-dependency registration: only when fh_quests is started. `getState` = GetResourceState, `quests` = the
---fh_quests exports table, `hooks` = { offers, accept, onEvent, abandon }. @return boolean ok, string? err
function M.register(getState, quests, hooks)
    if type(getState) ~= 'function' or getState('fh_quests') ~= 'started' then return false, 'quests_not_started' end
    if type(quests) ~= 'table' then return false, 'no_exports' end
    local ok, a, b = pcall(function()
        return quests:registerJobType(M.JOB_TYPE, {
            offers = hooks.offers, accept = hooks.accept, onEvent = hooks.onEvent, abandon = hooks.abandon,
            events = { M.EVENT_DELIVERED, M.EVENT_FAILED },
        })
    end)
    if not ok then return false, tostring(a) end
    if a == false then return false, tostring(b) end
    return true
end

if GetCurrentResourceName then
    FhFreight = M
else
    return M
end
