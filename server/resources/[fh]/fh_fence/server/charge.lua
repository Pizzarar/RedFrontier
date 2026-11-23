-- The ONLY place fh_fence debits money: exports.fh_economy:charge(src, amount, reason, region_id) (core B7)
-- -> ok, err. B7 errors pass through untouched (trade.lua drops the stage on any of them; nothing was taken):
-- fh_insufficient_funds, fh_charge_busy (fail fast, the player retries), ledger_failed, removemoney_refused,
-- no_player, player_changed, plus the validation codes (invalid_amount, amount_too_large, ...).
-- 'charge_unavailable' = the export call threw: kept because it can at runtime (a Lua error inside fh_economy, or
-- fh_economy mid-restart), and a throw must come back as a refusal so trade.lua's rollback runs (never retried).
FhFenceCharge = {}

function FhFenceCharge.charge(src, amount, reason, region_id)
    local called, ok, err = pcall(function() return exports.fh_economy:charge(src, amount, reason, region_id) end)
    if not called then return false, 'charge_unavailable' end
    if ok == true then return true end
    return false, type(err) == 'string' and err or 'charge_refused'
end
