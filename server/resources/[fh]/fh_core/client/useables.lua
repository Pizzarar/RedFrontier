-- fh_core useables client half (core-08 P2): applies the effect the server already paid for with an item.
-- Health / stamina are fractions of the ped's max; clamped, and never lethal or revive a dead ped.
RegisterNetEvent('fh:core:useable:restore', function(eff)
    if type(eff) ~= 'table' then return end
    local ped = PlayerPedId()
    local hp, stamina = tonumber(eff.hp) or 0, tonumber(eff.stamina) or 0
    if hp > 0 then
        local cur, max = GetEntityHealth(ped), GetEntityMaxHealth(ped)
        if cur > 0 and max > 0 then SetEntityHealth(ped, math.min(max, math.floor(cur + max * math.min(hp, 1.0)))) end
    end
    if stamina > 0 then
        Citizen.InvokeNative(0x675680D089BFA21F, ped, math.min(stamina, 1.0) * 100.0) -- RESTORE_PLAYER_STAMINA (percent)
    end
end)
