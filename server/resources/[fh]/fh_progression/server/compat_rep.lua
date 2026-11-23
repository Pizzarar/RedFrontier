-- The ONLY place fh_progression reads rep.
-- FhProgressionRep.read(citizenid, region_id) -> number (0 when there is no row), or nil, err on a read error.
-- Uses exports.fh_economy:getRep(who, region_id) -> integer|nil, err (@core B7; `who` may be a citizenid string).
-- An export nil+err is returned as nil+err (never 0, never the fallback); see FhProgressionLogic.repExportResult.
-- Workaround: remove fallback when fh_economy exports getRep (idea-600).
FhProgressionRep = {}

local logic = FhProgressionLogic

function FhProgressionRep.read(citizenid, region_id)
    local kind, v = logic.repExportResult(pcall(function() return exports.fh_economy:getRep(citizenid, region_id) end))
    if kind == 'value' then return v end
    if kind == 'error' then return nil, v end
    -- Workaround: remove fallback when fh_economy exports getRep (idea-600). Read-only; only when the call failed.
    local rok, value = pcall(MySQL.scalar.await, 'SELECT `value` FROM fh_rep WHERE citizenid = ? AND region_id = ?',
        { citizenid, region_id })
    if not rok then return nil, 'db_error' end
    if value == nil then return 0 end -- no row: nothing earned yet
    if type(value) ~= 'number' then return nil, 'bad_value' end
    return value
end
