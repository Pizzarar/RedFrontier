-- fh_survival client actions (S3): refill / wash commands and notifications. The server decides everything.
-- In WaterCheck = 'native' mode the client reports IsEntityInWater; otherwise the flag is ignored by the server.
-- Natives (UNVERIFIED in game, see fh_core/docs/natives.md): PlayerPedId, IsEntityInWater.

local function pedInWater()
    local ok, res = pcall(function() return IsEntityInWater(PlayerPedId()) end)
    return ok and res == true
end

RegisterNetEvent('fh:survival:notify', function(msg)
    if type(msg) ~= 'string' then return end
    local ok = pcall(function() TriggerEvent('ox_lib:notify', { description = msg, type = 'inform' }) end)
    if not ok then print('[fh_survival] ' .. msg) end
end)

RegisterCommand('refill', function() TriggerServerEvent('fh:survival:refill', pedInWater()) end, false)
RegisterCommand('wash', function() TriggerServerEvent('fh:survival:wash', pedInWater()) end, false)
