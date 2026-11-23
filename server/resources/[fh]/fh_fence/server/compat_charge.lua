-- The ONLY place fh_fence debits money. FhFenceCharge.charge(src, amount, reason, region_id) -> ok, err
-- Workaround: until fh_economy exports charge (idea-600). Without it a buy is refused cleanly ('charge_unavailable').
FhFenceCharge = {}

function FhFenceCharge.charge(src, amount, reason, region_id)
    local ok, present = pcall(function() return exports.fh_economy.charge ~= nil end)
    if not ok or not present then return false, 'charge_unavailable' end
    local cok, res, err = pcall(function() return exports.fh_economy:charge(src, amount, reason, region_id) end)
    if not cok then return false, 'charge_unavailable' end
    if res == true then return true end
    return false, err or 'charge_refused'
end
