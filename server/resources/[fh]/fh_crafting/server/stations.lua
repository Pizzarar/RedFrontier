-- Station adapter (C1 stub; C2 fills it, C5 swaps to the real contract).
-- Real source = exports.fh_homestead:isNearStation(src, type, maxDist) when GetResourceState('fh_homestead')=='started'
-- and the export exists; fallback = Config.devStations (FhCraftingConfig) only when GetConvarInt('fh_dev',0)==1.
-- Workaround, replaced by C5.
FhCraftStations = {}

---@param src number
---@param stationType string 'gunsmith'|'reload'|'apothecary'
---@return boolean ok
---@return string|nil reason 'bad_type' | 'no_station'
function FhCraftStations.isNear(src, stationType)
    return false, 'not_implemented'
end
