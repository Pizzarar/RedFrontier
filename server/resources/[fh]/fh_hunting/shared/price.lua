-- fh_hunting pelt price (spec L8). Pure Lua. The amount handed to fh_economy.pay.
local M = {}

---price = base * QualityMult[stars] * (legendary and LegendaryMult or 1), rounded to a whole number.
---@return number|nil amount, string|nil err
function M.price(itemBase, stars, isLegendary, cfg)
    cfg = cfg or FhHuntingConfig
    if type(itemBase) ~= 'number' or itemBase ~= itemBase or itemBase < 0 then return nil, 'fh_bad_base' end
    local mult = cfg.QualityMult[stars]
    if not mult then return nil, 'fh_bad_stars' end
    if isLegendary then mult = mult * cfg.LegendaryMult end
    return math.floor(itemBase * mult + 0.5)
end

if GetCurrentResourceName then
    FhHuntingPrice = M
else
    return M
end
