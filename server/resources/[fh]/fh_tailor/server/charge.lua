-- The ONLY place fh_tailor debits money: exports.fh_economy:charge(src, amount, reason, region_id) (core B7) -> ok, err.
-- B7 errors pass through untouched (nothing was taken for any of them): fh_insufficient_funds, fh_charge_busy (FhTailorCore
-- retries it, bounded), ledger_failed, removemoney_refused, no_player, player_changed, plus the validation codes
-- (invalid_amount, amount_too_large, invalid_reason, unknown_region). FhTailorLogic.messages has text for each.
-- 'charge_unavailable' = the export call threw (a Lua error inside fh_economy, or fh_economy mid-restart): the outcome is
-- unknown, so FhTailorCore keeps the ownership claim (never charged twice) and logs an ALERT (same rule as fh_hands).
FhTailorCharge = {}

function FhTailorCharge.charge(src, amount, reason, region_id)
    local called, ok, err = pcall(function() return exports.fh_economy:charge(src, amount, reason, region_id) end)
    if not called then return false, 'charge_unavailable' end
    if ok == true then return true end
    return false, type(err) == 'string' and err or 'charge_refused'
end
