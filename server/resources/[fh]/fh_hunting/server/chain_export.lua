-- Read-only chain progress for @quests: exports.fh_hunting:chainState(citizenid, chain_id) -> nil | step | 'complete'.
-- Own file (not main.lua / trappers_export.lua); all logic is FhHuntingChain.readState (shared/chain.lua).
local function chainState(citizenid, chainId)
    return FhHuntingChain.readState({
        byId = FhHuntingLegendaries.byId,
        query = function(cid, id)
            return MySQL.query.await(
                'SELECT step, completed FROM fh_hunting_chains WHERE citizenid = ? AND chain_id = ? LIMIT 1', { cid, id })
        end,
        log = function(m) print('^3[fh_hunting] ' .. m .. '^7') end,
    }, citizenid, chainId)
end

if exports then
    exports('chainState', chainState)
else
    return chainState
end
