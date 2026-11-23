-- The ONLY place fh_hands debits wages. FhHandsCharge.charge(src, amount, reason, region_id) -> ok, err
-- Workaround: until fh_economy exports charge (idea-600), this returns false, 'charge_unavailable'
-- (hands then go unpaid and idle; nothing is debited). Remove the pcall guard when charge ships.
-- Errors are passed through untouched (core B7 contract): fh_charge_busy / ledger_failed (retry later, no strike),
-- no_player / player_changed (owner gone, no strike), fh_insufficient_funds (strike). See FhHandsLogic.chargeOutcome.
FhHandsCharge = {}

function FhHandsCharge.charge(src, amount, reason, region_id)
    local called, ok, err = pcall(function() return exports.fh_economy:charge(src, amount, reason, region_id) end)
    if not called then return false, 'charge_unavailable' end -- export missing (or fh_economy down)
    if ok == true then return true end
    return false, type(err) == 'string' and err or 'charge_refused'
end
