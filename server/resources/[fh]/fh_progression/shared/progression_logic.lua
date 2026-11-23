-- Rep -> tier and unlock checks (M7). Pure Lua, no FiveM globals; unit-tested.
-- cfg = { tiers = { [region_id] = { t2 = n, t3 = n } }, unlocks = { [id] = { region_id, min_tier } } }
local logic = {}

---Tier (1..3) for a rep value in a region. Unknown region or non-number value -> 1 plus a reason.
---@return integer tier, string? reason
function logic.tierForRep(cfg, region, value)
    local t = type(cfg) == 'table' and type(cfg.tiers) == 'table' and cfg.tiers[region] or nil
    if type(t) ~= 'table' then return 1, 'unknown_region' end
    if type(value) ~= 'number' or value ~= value then return 1, 'bad_value' end
    if t.t3 and value >= t.t3 then return 3 end
    if t.t2 and value >= t.t2 then return 2 end
    return 1
end

---Tier crossing between two rep values. An unknown old value (nil / not a number), a bad new value or an unknown
---region never counts as a crossing.
---@return boolean changed, integer oldTier, integer newTier
function logic.crossing(cfg, region, oldValue, newValue)
    local newTier, newWhy = logic.tierForRep(cfg, region, newValue)
    if newWhy then return false, newTier, newTier end
    if type(oldValue) ~= 'number' or oldValue ~= oldValue then return false, newTier, newTier end
    local oldTier = logic.tierForRep(cfg, region, oldValue)
    return oldTier ~= newTier, oldTier, newTier
end

---@param repByRegion table<string, number>|nil
---@return boolean ok, string? reason
function logic.canUnlock(cfg, repByRegion, unlock_id)
    local u = type(cfg) == 'table' and type(cfg.unlocks) == 'table' and cfg.unlocks[unlock_id] or nil
    if type(u) ~= 'table' then return false, 'unknown_unlock' end
    if type(cfg.tiers) ~= 'table' or type(cfg.tiers[u.region_id]) ~= 'table' then return false, 'unknown_region' end
    local value = type(repByRegion) == 'table' and repByRegion[u.region_id] or 0
    local tier, why = logic.tierForRep(cfg, u.region_id, value)
    if why then return false, why end
    if tier < u.min_tier then return false, 'tier_too_low' end
    return true
end

---Interprets `pcall(exports.fh_economy.getRep, citizenid, region_id)`. Contract (@core B7):
---`getRep(who, region_id) -> integer|nil, err` with err in unknown_region / no_player / ledger_failed.
---Every failure is an error, never read as 0: a nil from the export passes its err through; a failed call (the
---export threw: fh_economy stopped or restarting) is 'economy_unavailable'.
---@return string kind 'value'|'error', number|string v
function logic.repExportResult(callOk, v, err)
    if not callOk then return 'error', 'economy_unavailable' end
    if v == nil then return 'error', type(err) == 'string' and err or 'read_failed' end
    if type(v) ~= 'number' or v ~= v or v == math.huge or v == -math.huge then return 'error', 'bad_value' end
    return 'value', v
end

---Admin `fh_rep_region <serverId> <region> <delta>` argument parsing. Whole numbers only, region must be known,
---|delta| <= maxDelta (fh_economy re-validates against its own cap). @return table|nil { target, region_id, delta }, string? err
function logic.parseRepCmd(args, isKnownRegion, maxDelta)
    args = type(args) == 'table' and args or {}
    local function fin(n) return type(n) == 'number' and n == n and n ~= math.huge and n ~= -math.huge end
    local target, delta = tonumber(args[1]), tonumber(args[3])
    if not (fin(target) and target > 0 and target % 1 == 0) then return nil, 'fh_bad_target' end
    if type(args[2]) ~= 'string' or not isKnownRegion(args[2]) then return nil, 'unknown_region' end
    if not (fin(delta) and delta ~= 0 and delta % 1 == 0) then return nil, 'invalid_delta' end
    if maxDelta and math.abs(delta) > maxDelta then return nil, 'delta_too_large' end
    return { target = target, region_id = args[2], delta = delta }
end

if _G.GetCurrentResourceName then _G.FhProgressionLogic = logic end
return logic
