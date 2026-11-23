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

---Stable per template: same (from, to, item) = same key. fh_quests ids are <= 64 chars of [A-Za-z0-9_.:-].
function M.offerKey(from, to, item) return (('%s>%s>%s'):format(from, to, item):gsub('>', '.')) end

local function defaults(cfg)
    local f = cfg.freight or {}
    return {
        minQty = f.minQty or 1, maxQty = f.maxQty or 20, qtyPerLevel = f.qtyPerLevel or 20,
        premium = f.premium or 1.25, repDelta = f.repDelta or 2, deadlineSeconds = f.deadlineSeconds or 1800,
        maxOffers = f.maxOffers or 3, rewardCap = f.rewardCapMultiple or 4,
        allowSameRegion = f.allowSameRegion == true, destinations = f.destinations or {},
    }
end

local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end

---Offers for a board at `fromRegion`, one per shortage in the OTHER regions that have a destination.
---`shortagesByRegion[region] = fh_trade shortages list { item, level, multiplier, price }`. Pure; worst shortage first.
---@return table[] offers { key, title, text, from_region, to_region, item, qty, reward, rewards, deadline_s, level, region_id }
function M.generate(cfg, fromRegion, shortagesByRegion)
    local d, out = defaults(cfg), {}
    if type(fromRegion) ~= 'string' or fromRegion == '' then return out end
    local regions = {}
    for r in pairs(shortagesByRegion or {}) do regions[#regions + 1] = r end
    table.sort(regions)
    for _, to in ipairs(regions) do
        if (to ~= fromRegion or d.allowSameRegion) and d.destinations[to] then
            for _, s in ipairs(shortagesByRegion[to]) do
                local good = cfg.goods[s.item]
                if good and finite(s.level) and finite(s.price) then
                    local qty = clamp(math.ceil(s.level * d.qtyPerLevel), d.minQty, d.maxQty)
                    local reward = math.floor(qty * s.price * d.premium)
                    if reward >= 1 then
                        local label = good.label or s.item
                        out[#out + 1] = {
                            key = M.offerKey(fromRegion, to, s.item),
                            title = ('Freight: %dx %s to %s'):format(qty, label, to),
                            text = ('Haul %dx %s from %s to %s before time runs out.'):format(qty, label, fromRegion, to),
                            region_id = fromRegion, from_region = fromRegion, to_region = to,
                            item = s.item, qty = qty, reward = reward, level = s.level, deadline_s = d.deadlineSeconds,
                            rewards = { money = reward, rep = { region_id = to, delta = d.repDelta } },
                        }
                    end
                end
            end
        end
    end
    table.sort(out, function(a, b) if a.level ~= b.level then return a.level > b.level end return a.key < b.key end)
    while #out > d.maxOffers do out[#out] = nil end
    return out
end

---Re-check an offer that came back through fh_quests (never trust it). @return boolean ok, string? err
function M.validateOffer(cfg, offer, isKnownRegion)
    local d = defaults(cfg)
    if type(offer) ~= 'table' then return false, 'bad_offer' end
    local good = type(offer.item) == 'string' and cfg.goods[offer.item]
    if not good then return false, 'unknown_item' end
    if type(offer.from_region) ~= 'string' or type(offer.to_region) ~= 'string' then return false, 'bad_region' end
    if isKnownRegion and not (isKnownRegion(offer.from_region) and isKnownRegion(offer.to_region)) then return false, 'bad_region' end
    if offer.from_region == offer.to_region and not d.allowSameRegion then return false, 'same_region' end
    if not d.destinations[offer.to_region] then return false, 'no_destination' end
    if offer.key ~= M.offerKey(offer.from_region, offer.to_region, offer.item) or #M.questId(offer.key) > 64 then return false, 'bad_key' end
    if not int(offer.qty) or offer.qty < d.minQty or offer.qty > d.maxQty then return false, 'bad_qty' end
    if not int(offer.reward) or offer.reward < 1 or offer.reward > offer.qty * good.base * d.rewardCap then return false, 'bad_reward' end
    if not int(offer.deadline_s) or offer.deadline_s < 60 or offer.deadline_s > 86400 then return false, 'bad_deadline' end
    return true
end

---Contract record created at accept.
function M.newContract(offer, citizenid, wagonId, now)
    return {
        key = offer.key, citizenid = citizenid, wagon = wagonId, from_region = offer.from_region, to_region = offer.to_region,
        item = offer.item, qty = offer.qty, reward = offer.reward, accepted_at = now, deadline = now + offer.deadline_s, miss = 0,
    }
end

local function dist3(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, (a.z or 0) - (b.z or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

---Is `wagonCoords` inside the destination reach circle?
function M.atTarget(dest, wagonCoords)
    if type(dest) ~= 'table' or type(wagonCoords) ~= 'table' or not finite(wagonCoords.x) or not finite(wagonCoords.y) then return false end
    return dist3(dest, wagonCoords) <= (dest.radius or 30.0)
end

---Decide what a periodic check means. facts = { wagon = table|nil (getWagon result), coordsKnown?, owner_ok?,
---cargoCount = number|nil (nil = unreadable, fail closed: neither delivered nor lost), atTarget = boolean }.
---Order: deadline first, then wagon gone, then cargo short, then delivery.
---`graceChecks` consecutive "gone/short" reads are tolerated (wagon respawn, a moment in a chest) before it counts.
---@return string|nil verdict 'delivered'|'timeout'|'wagon_lost'|'cargo_missing'; integer newMiss
function M.evaluate(c, facts, now, graceChecks)
    if not finite(now) or type(c) ~= 'table' or type(facts) ~= 'table' then return nil, c and c.miss or 0 end
    if now >= c.deadline then return 'timeout', c.miss end
    local grace = graceChecks or 3
    local gone = facts.wagon == nil or facts.owner_ok == false
    local short = not gone and facts.cargoCount ~= nil and facts.cargoCount < c.qty
    if gone or short then
        local miss = (c.miss or 0) + 1
        if miss >= grace then return gone and 'wagon_lost' or 'cargo_missing', miss end
        return nil, miss
    end
    if facts.cargoCount == nil then return nil, c.miss or 0 end -- unreadable: hold state
    if facts.atTarget then return 'delivered', 0 end
    return nil, 0
end

---fh_quests onEvent hook mapping. Only our two events; must be the player's own contract.
---`state` is whatever fh_quests passes: quest id read from state.quest_id / state.id when present.
---@return string|nil 'complete'|'fail'|nil
function M.eventVerdict(name, payload, state)
    if type(payload) ~= 'table' or type(payload.key) ~= 'string' then return nil end
    if name ~= M.EVENT_DELIVERED and name ~= M.EVENT_FAILED then return nil end
    local qid = type(state) == 'table' and (state.quest_id or state.id) or nil
    if qid ~= nil and qid ~= M.questId(payload.key) then return nil end
    if name == M.EVENT_DELIVERED then return 'complete' end
    return 'fail'
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
