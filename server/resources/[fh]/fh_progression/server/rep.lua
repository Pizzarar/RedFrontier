-- The ONLY place fh_progression reads rep: exports.fh_economy:getRep(who, region_id) -> integer|nil, err (core B7;
-- `who` = the citizenid string, so offline reads work). FhProgressionRep.read(citizenid, region_id) -> number, or
-- nil, err. Every failure is an error (never 0): an export nil+err is passed through; a throw (Lua error inside
-- fh_economy, or fh_economy mid-restart) is 'economy_unavailable'. See FhProgressionLogic.repExportResult.
FhProgressionRep = {}

local logic = FhProgressionLogic

function FhProgressionRep.read(citizenid, region_id)
    local kind, v = logic.repExportResult(pcall(function() return exports.fh_economy:getRep(citizenid, region_id) end))
    if kind == 'value' then return v end
    return nil, v
end
