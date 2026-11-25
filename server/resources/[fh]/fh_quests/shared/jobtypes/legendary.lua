-- legendary offers (quests-04 L2): one-shot tier-3 regional legendary hunt commissions, paying out on
-- fh_hunting's per-region `fh:hunting:chain_complete`. Pure Lua, no natives.
-- Data: data/regions/<region_id>.lua `legendaries = { { chain_id, legendary, money, rep, min_tier = 3 } }`.
-- Verdicts: shared/jobtypes.lua (default on/where matching).
local JT = FhQuestsJobTypes -- the global (in-game: set by shared/jobtypes.lua; specs: set by its spec loader)

local function humanize(id)
    return (id:gsub('_', ' '):gsub('(%a)([%w]*)', function(a, b) return a:upper() .. b end))
end

local function isNonNegInt(n)
    return type(n) == 'number' and n == n and n >= 0 and n == math.floor(n) and n < math.huge
end

local function isPosInt(n)
    return type(n) == 'number' and n == n and n > 0 and n == math.floor(n) and n < math.huge
end

JT.registerBuilder('legendary', function(region_id, d)
    local out = {}
    for _, e in ipairs(d.legendaries or {}) do
        if type(e) == 'table'
            and type(e.chain_id) == 'string' and e.chain_id ~= ''
            and type(e.legendary) == 'string' and e.legendary ~= ''
            and isNonNegInt(e.money)
            and isPosInt(e.rep)
        then
            local label = type(e.label) == 'string' and e.label ~= '' and e.label or humanize(e.legendary)
            out[#out + 1] = {
                key = e.chain_id,
                title = 'Legendary commission: ' .. label,
                text = 'Track and bring down the ' .. label .. '.',
                on = 'fh:hunting:chain_complete',
                where = { chain_id = { eq = e.chain_id }, region_id = { eq = region_id } },
                rewards = JT.rewards(region_id, e.money, e.rep),
                region_id = region_id,
                chain_id = e.chain_id,
                legendary = e.legendary,
                min_tier = JT.minTier(e.min_tier),
            }
        end
    end
    return out
end)

-- TODO(quests-04 L0): @hunting L0 adds exports.fh_hunting:chainState(citizenid, chain_id) -> nil | step(1..3) | 'complete'.
-- Until L0 lands, chainState is absent and lockedFor returns nil (offer shown). Once L0 lands, this guard picks it up
-- automatically and hides completed chains with { reason = 'legendary_done' } with no quests change needed.
---Pure per-player lock check for a legendary commission offer.
---deps = {
---  citizenidOf = function(src) -> citizenid|nil,
---  huntingStarted = function() -> boolean,
---  chainState = function(cid, chain_id) -> nil | number | 'complete' (optional; nil when L0 not landed),
---}
---@return table|nil lock  { reason = 'legendary_done' } when complete, else nil
function JT.legendaryLockedFor(offer, src, deps)
    if type(offer) ~= 'table' or type(offer.chain_id) ~= 'string' or offer.chain_id == '' then return nil end
    if type(deps) ~= 'table' or type(deps.citizenidOf) ~= 'function' then return nil end
    if type(deps.huntingStarted) == 'function' and not deps.huntingStarted() then return nil end
    if type(deps.chainState) ~= 'function' then return nil end
    local okCid, cid = pcall(deps.citizenidOf, src)
    if not okCid or type(cid) ~= 'string' or cid == '' then return nil end
    local ok, state = pcall(deps.chainState, cid, offer.chain_id)
    if not ok then return nil end
    if state == 'complete' then return { reason = 'legendary_done' } end
    return nil
end
