-- Legendary coats (hunting-03 C2). Pure: no natives. A completed legendary chain grants two fh_tailor wardrobe entries,
-- `coat_<legendary_id>_male` and `coat_<legendary_id>_female`, with source `hunting:legendary:<legendary_id>`.
-- fh_tailor.grant is idempotent and offline-safe; `wrong_sex` (the entry for the other sex) is the expected result of
-- one of the two calls and is ignored. `unknown_entry` (the catalog has no such coat yet) is logged once per id and
-- never breaks chain completion. fh_tailor missing/stopped = silent no-op.
--
-- M.new({ grant = fn(citizenid, id, source) -> ok, code, available = fn() -> bool, log = fn(msg) })
local M = {}

M.SOURCE_PREFIX = 'hunting:legendary:'

local function validId(id) return type(id) == 'string' and id:match('^[%w_]+$') ~= nil end

---@return string|nil male, string|nil female   nil for an invalid legendary id
function M.ids(legendaryId)
    if not validId(legendaryId) then return nil end
    return 'coat_' .. legendaryId .. '_male', 'coat_' .. legendaryId .. '_female'
end

---Source string; matches ^[%w_:%-%.]+$ (fh_tailor's validSource).
function M.source(legendaryId)
    if not validId(legendaryId) then return nil end
    return M.SOURCE_PREFIX .. legendaryId
end

function M.new(deps)
    local warned = {} -- [coat id] = true once logged
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
            local code = ok and (b ~= nil and b or a) or nil
            if not ok then
                if not warned[id] then warned[id] = true; deps.log(('coat grant %s threw: %s'):format(id, tostring(a))) end
            elseif code == 'unknown_entry' and not warned[id] then
                warned[id] = true
                deps.log(('coat %s is not in the fh_tailor catalog (unknown_entry); skipped'):format(id))
            end
            -- granted / already_owned / wrong_sex / other codes: nothing to do (idempotent, retried on next load)
        end
        return n
    end

    ---Grant for every legendary id in `ids` whose chain is completed. isCompleted(citizenid, id) -> bool.
    ---Returns the legendary ids granted for.
    function C.backfill(citizenid, ids, isCompleted)
        local done = {}
        for _, lid in ipairs(ids) do
            local okc, completed = pcall(isCompleted, citizenid, lid)
            if okc and completed == true and C.grantFor(citizenid, lid) > 0 then done[#done + 1] = lid end
        end
        return done
    end

    return C
end

if GetCurrentResourceName then
    FhHuntingCoats = M
else
    return M
end
