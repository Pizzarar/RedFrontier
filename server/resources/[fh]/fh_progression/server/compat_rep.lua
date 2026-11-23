-- The ONLY place fh_progression reads rep.
-- FhProgressionRep.read(citizenid, region_id) -> number (0 when there is no row), or nil, err on a read error.
-- Workaround: remove fallback when fh_economy exports getRep (idea-600).
FhProgressionRep = {}

function FhProgressionRep.read(citizenid, region_id)
    local ok, v = pcall(function() return exports.fh_economy:getRep(citizenid, region_id) end)
    if ok and type(v) == 'number' then return v end
    -- Workaround: remove fallback when fh_economy exports getRep (idea-600). Read-only.
    local rok, value = pcall(MySQL.scalar.await, 'SELECT `value` FROM fh_rep WHERE citizenid = ? AND region_id = ?',
        { citizenid, region_id })
    if not rok then return nil, 'db_error' end
    if value == nil then return 0 end -- no row: nothing earned yet
    if type(value) ~= 'number' then return nil, 'bad_value' end
    return value
end
