-- fh_quests jobs board rotation (Q1). Pure Lua, no natives, no math.random (own seeded PRNG).
-- rotate() picks 3-5 offers for a region, deterministically from (region_id, epoch, offer lists):
-- the same inputs always give the same board, in the same order, with the same offer ids.
--
-- offerLists = { [job_type] = { { key = '<stable template key>', title = '...', ... }, ... } }
--   (the server builds this from each registered job type's hooks.offers(region_id)).
-- Result: array of { id, job_type, key, title, region_id, epoch, expires_at?, offer = <the source offer> }.
-- id = '<region_id>:<epoch>:<job_type>:<key>': stable for the whole epoch, so acceptOffer(offer_id) keeps working
-- across board re-sends and server restarts inside the same epoch.
local M = {}

M.DEFAULTS = { min = 3, max = 5, rotate_min = 60 }

local MASK = 0xFFFFFFFF

---FNV-1a 32-bit hash of a string (stable across Lua builds; integer math only).
function M.hash(str)
    local h = 2166136261
    for i = 1, #str do
        h = ((h ~ str:byte(i)) * 16777619) & MASK
    end
    return h
end

---Seeded generator: returns next(n) -> integer in [1, n]. 32-bit LCG, upper bits used.
function M.rng(seed)
    local s = seed & MASK
    return function(n)
        s = (s * 1664525 + 1013904223) & MASK
        return ((s >> 8) % n) + 1
    end
end

---Rotation epoch for a unix time: floor(now / (rotate_min * 60)).
function M.epoch(now, rotate_min)
    rotate_min = rotate_min or M.DEFAULTS.rotate_min
    return math.floor(now / (rotate_min * 60))
end

local function shuffle(list, next)
    for i = #list, 2, -1 do
        local j = next(i)
        list[i], list[j] = list[j], list[i]
    end
    return list
end

local function sortedKeys(t)
    local keys = {}
    for k in pairs(t) do
        if type(k) == 'string' then keys[#keys + 1] = k end
    end
    table.sort(keys)
    return keys
end

---Pick this epoch's board for one region.
---opts = { min = 3, max = 5, rotate_min = 60 } (rotate_min only sets expires_at)
---@return table offers  fewer than min only when fewer valid offers exist; never more than max
function M.rotate(region_id, epoch, offerLists, opts)
    opts = opts or {}
    local lo = math.max(0, opts.min or M.DEFAULTS.min)
    local hi = math.max(lo, opts.max or M.DEFAULTS.max)
    assert(type(region_id) == 'string' and region_id ~= '', 'fh_quests board: region_id')
    assert(math.type(epoch) == 'integer' or (type(epoch) == 'number' and epoch == math.floor(epoch)),
        'fh_quests board: epoch must be whole')
    epoch = math.tointeger(epoch)
    local next = M.rng(M.hash(region_id .. ':' .. epoch))

    -- Per job type: valid offers sorted by key (input order never matters), duplicate keys dropped, then shuffled.
    local pools, types = {}, {}
    for _, jt in ipairs(sortedKeys(offerLists or {})) do
        local seen, pool = {}, {}
        for _, o in ipairs(offerLists[jt]) do
            if type(o) == 'table' and type(o.key) == 'string' and o.key ~= '' and not seen[o.key] then
                seen[o.key] = true
                pool[#pool + 1] = o
            end
        end
        table.sort(pool, function(a, b) return a.key < b.key end)
        if #pool > 0 then
            pools[jt] = shuffle(pool, next)
            types[#types + 1] = jt
        end
    end
    shuffle(types, next)

    local total = 0
    for _, jt in ipairs(types) do total = total + #pools[jt] end
    local want = math.min(total, lo + next(hi - lo + 1) - 1)

    -- Round-robin across job types so one type cannot fill the whole board.
    local out, round = {}, 1
    local expires = opts.rotate_min and ((epoch + 1) * opts.rotate_min * 60) or nil
    while #out < want do
        for _, jt in ipairs(types) do
            local o = pools[jt][round]
            if o and #out < want then
                out[#out + 1] = {
                    id = region_id .. ':' .. epoch .. ':' .. jt .. ':' .. o.key,
                    job_type = jt, key = o.key, title = o.title, region_id = region_id, epoch = epoch,
                    expires_at = expires, offer = o,
                }
            end
        end
        round = round + 1
    end
    return out
end

---Find an offer on a board by id (acceptOffer). nil when it rotated away.
function M.find(board, offer_id)
    for _, o in ipairs(board or {}) do
        if o.id == offer_id then return o end
    end
    return nil
end

if GetCurrentResourceName then
    FhQuestsBoard = M
else
    return M
end
