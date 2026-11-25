-- Pure homestead trough rules (H20a). No natives; specced under lupa. Numbers live in config.lua (FhHomesteadConfig.trough).
-- The trough container 'fh:trough:<plot>' accepts the feedbag only. canRefill is the server gate for the mount refill:
-- owner, inside the plot radius, at least 1 feedbag in the trough, cooldown elapsed. Every bad input fails closed.
-- An optional trailing cfg is the trough config table; if it is not a table the global FhHomesteadConfig.trough is used.
local M = {}

local function troughCfg(cfg)
    if type((cfg)) == 'table' then return cfg end
    local g = rawget(_G, 'FhHomesteadConfig')
    if type((g)) == 'table' and type((g.trough)) == 'table' then return g.trough end
    return nil
end

local function num(v) return type(v) == 'number' and v == v and v > -math.huge and v < math.huge end

---True only for the configured trough item (feedbag).
function M.accepts(itemName, cfg)
    local c = troughCfg(cfg)
    if not c or type(c.item) ~= 'string' or c.item == '' then return false end
    return type(itemName) == 'string' and itemName == c.item
end

---Container id for a plot's trough. nil for a bad plot id.
function M.containerId(plotId)
    if type(plotId) ~= 'string' or plotId == '' then return nil end
    return 'fh:trough:' .. plotId
end

---When the next refill is allowed (epoch seconds). lastRefillAt nil = never refilled = 0 (allowed now).
---Returns nil on bad input or missing/invalid cooldown config.
function M.nextRefillAt(lastRefillAt, cfg)
    local c = troughCfg(cfg)
    if not c or not num(c.cooldownSeconds) or c.cooldownSeconds < 0 then return nil end
    if lastRefillAt == nil then return 0 end
    if not num(lastRefillAt) then return nil end
    return lastRefillAt + c.cooldownSeconds
end

---state = { isOwner, inRadius, feedbags, lastRefillAt, now }
---@return boolean ok, string|nil reason  fh_not_owner | fh_out_of_range | fh_trough_empty | fh_cooldown
function M.canRefill(state, cfg)
    if type((state)) ~= 'table' then return false, 'fh_not_owner' end
    if state.isOwner ~= true then return false, 'fh_not_owner' end
    if state.inRadius ~= true then return false, 'fh_out_of_range' end
    local fb = state.feedbags
    if not num(fb) or fb < 1 then return false, 'fh_trough_empty' end
    if not num(state.now) then return false, 'fh_cooldown' end
    local nxt = M.nextRefillAt(state.lastRefillAt, cfg)
    if nxt == nil then return false, 'fh_cooldown' end
    if state.now < nxt then return false, 'fh_cooldown' end
    return true, nil
end

return M
