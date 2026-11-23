-- The ONLY place fh_hands debits wages: exports.fh_economy:charge(src, amount, reason, region_id) (core B7) -> ok, err.
-- B7 errors pass through untouched; FhHandsLogic.chargeOutcome classifies them: fh_charge_busy / ledger_failed (retry,
-- tick handed back, no strike), no_player / player_changed (owner gone, tick handed back), fh_insufficient_funds,
-- removemoney_refused and anything else (unpaid strike). The tick is claimed in the DB before this call, so a retry is
-- a new claim of a tick nobody was charged for: never a double charge.
-- 'charge_unavailable' = the export call threw: kept because fh_economy can be stopped/restarted at runtime; its outcome
-- is unknown, so chargeOutcome keeps the claim (never retried) and gives no strike ('skip').
FhHandsCharge = {}

function FhHandsCharge.charge(src, amount, reason, region_id)
    local called, ok, err = pcall(function() return exports.fh_economy:charge(src, amount, reason, region_id) end)
    if not called then return false, 'charge_unavailable' end
    if ok == true then return true end
    return false, type(err) == 'string' and err or 'charge_refused'
end
