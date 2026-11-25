-- Legendary coats (hunting-03 C2). Pure: no natives. A completed legendary chain grants two fh_tailor wardrobe entries,
-- `coat_<legendary_id>_male` and `coat_<legendary_id>_female`, with source `hunting:<id minus 'legendary_'>`
-- (fh_tailor_owned.source is varchar(32): the longer 'hunting:legendary:<id>' form was refused as invalid_source).
-- fh_tailor.grant is idempotent and offline-safe; `wrong_sex` (the entry for the other sex) is the expected result of
-- one of the two calls and is ignored. Any other failure (unknown_entry, invalid_source, db_failed, not_ready...) is
-- logged once per (coat id, code) and never breaks chain completion. fh_tailor missing/stopped = silent no-op.
--
-- M.new({ grant = fn(citizenid, id, source) -> ok, code, available = fn() -> bool, log = fn(msg) })
local M = {}

M.SOURCE_PREFIX = 'hunting:'

local function validId(id) return type(id) == 'string' and id:match('^[%w_]+$') ~= nil end

---@return string|nil male, string|nil female   nil for an invalid legendary id
function M.ids(legendaryId)
    if not validId(legendaryId) then return nil end
    return 'coat_' .. legendaryId .. '_male', 'coat_' .. legendaryId .. '_female'
end

---Source string, e.g. 'hunting:cinderjaw_coyote'; matches ^[%w_:%-%.]+$ and fits fh_tailor's MAX_SOURCE (32).
function M.source(legendaryId)
    if not validId(legendaryId) then return nil end
    return M.SOURCE_PREFIX .. (legendaryId:gsub('^legendary_', ''))
end

function M.new(deps)
    local warned = {} -- [coat id .. '|' .. refusal code] = true once logged
    local C = {}

    ---Grant both coats for one legendary. Never throws. Returns the number of calls made (0 = fh_tailor unavailable).
    function C.grantFor(citizenid, legendaryId)
        local male, female = M.ids(legendaryId)
        if not male or type(citizenid) ~= 'string' or citizenid == '' then return 0 end
        if not deps.available() then return 0 end
        local src, n = M.source(legendaryId), 0
        for _, id in ipairs({ male, female }) do
            n = n + 1
            local ok, a, b = pcall(deps.grant, citizenid, id, src)
            local code
            if not ok then code = 'threw: ' .. tostring(a)
            elseif a == false then code = tostring(b) end
            if code and code ~= 'wrong_sex' then
                local key = id .. '|' .. code
                if not warned[key] then
                    warned[key] = true
                    deps.log(('coat grant %s refused (%s); skipped'):format(id, code))
                end
            end
        end
        return n
    end

    ---True when fh_tailor can take grants (callers skip their completed-chain query when false).
    function C.available() return deps.available() == true end

    ---Grant for each legendary id in `completedIds` (the caller's single completed-chains query). Returns the ids
    ---granted for (empty when fh_tailor is unavailable).
    function C.backfill(citizenid, completedIds)
        local done = {}
        for _, lid in ipairs(completedIds) do
            if C.grantFor(citizenid, lid) > 0 then done[#done + 1] = lid end
        end
        return done
    end

    ---Login backfill: `query()` returns the character's completed chain rows ({ chain_id = ... }); `known[chain_id]` gates
    ---which are legendaries. A query failure logs citizenid + error and grants nothing. Returns the ids granted for.
    function C.backfillFromQuery(citizenid, query, known)
        local ok, rows = pcall(query)
        if not ok or type(rows) ~= 'table' then
            deps.log(('coat backfill query failed for %s: %s'):format(tostring(citizenid), tostring(rows)))
            return {}
        end
        local ids = {}
        for _, r in ipairs(rows) do
            if type(r.chain_id) == 'string' and known[r.chain_id] then ids[#ids + 1] = r.chain_id end
        end
        if #ids == 0 then return {} end
        return C.backfill(citizenid, ids)
    end

    return C
end

if GetCurrentResourceName then
    FhHuntingCoats = M
else
    return M
end
