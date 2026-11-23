-- fh_survival client actions (S3): refill / wash commands and notifications. The server decides everything.
-- In WaterCheck = 'native' mode the client reports IsEntityInWater; otherwise no water native is ever called.
-- Natives (UNVERIFIED in game, see fh_core/docs/natives.md): PlayerPedId, IsEntityInWater (native mode only).

local function pedInWater()
    if FhSurvivalItems.waterMode(FhSurvivalConfig.WaterCheck) ~= 'native' then return false end
    local ok, res = pcall(function() return IsEntityInWater(PlayerPedId()) end)
    return ok and res == true
end

FH.onNet('fh:survival:notify', function(msg)
    if type(msg) ~= 'string' then return end
    local ok = pcall(function() TriggerEvent('ox_lib:notify', { description = msg, type = 'inform' }) end)
    if not ok then print('[fh_survival] ' .. msg) end
end)

RegisterCommand('refill', FH.wrap(function() TriggerServerEvent('fh:survival:refill', pedInWater()) end), false)
RegisterCommand('wash', FH.wrap(function() TriggerServerEvent('fh:survival:wash', pedInWater()) end), false)
