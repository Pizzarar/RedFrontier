-- spk_wear client. Natives by hash (names from alloc8or rdr3 nativedb; see README).
local N_PLAYER_PED_ID   = 0x096275889B8E0EE0
local N_GET_CUR_WEAPON  = 0x3A87E44BB9A01D54 -- GET_CURRENT_PED_WEAPON(ped, Hash* out, p2, attachPoint, p4) -> BOOL
local N_GET_WEAPON_ENT  = 0x3B390A939AF0B5FC -- GET_CURRENT_PED_WEAPON_ENTITY_INDEX(ped, attachPoint) -> Entity
local N_DOES_EXIST      = 0xD42BD6EB2E0F1677
local N_GET_DEGRADATION = 0x0D78E1097F89E637 -- GET_WEAPON_DEGRADATION(weaponObject) -> float
local N_GET_PERM_DEGRAD = 0xD56E5F336C675EFA -- GET_WEAPON_PERMANENT_DEGRADATION(weaponObject) -> float
local N_GET_DAMAGE      = 0x904103D5D2333977 -- _GET_WEAPON_DAMAGE(weaponObject) -> float
local N_GET_DIRT        = 0x810E8AE9AFEA7E54 -- _GET_WEAPON_DIRT(weaponObject) -> float
local N_GET_SOOT        = 0x4BF66F8878F67663 -- _GET_WEAPON_SOOT(weaponObject) -> float
local N_SET_DEGRADATION = 0xA7A57E89E965D839 -- _SET_WEAPON_DEGRADATION(weaponObject, level)

local function bool(v) return v == true or (type(v) == 'number' and v ~= 0) end
local function say(msg)
    print('[spk_wear] ' .. msg)
    lib.notify({ title = 'spk_wear', description = msg, type = 'inform', duration = 8000 })
end
local function f(h, obj) return Citizen.InvokeNative(h, obj, Citizen.ResultAsFloat()) end

local function weaponObject(ped)
    local _, hash = Citizen.InvokeNative(N_GET_CUR_WEAPON, ped, Citizen.PointerValueInt(), true, 0, false, Citizen.ReturnResultAnyway())
    local obj = Citizen.InvokeNative(N_GET_WEAPON_ENT, ped, 0, Citizen.ResultAsInteger())
    if obj == 0 or not bool(Citizen.InvokeNative(N_DOES_EXIST, obj)) then return nil, hash end
    return obj, hash
end

local function dump(obj, hash)
    return ('weapon=0x%X obj=%d degradation=%.3f permanentDegradation=%.3f damage=%.3f dirt=%.3f soot=%.3f'):format(
        (hash or 0) & 0xFFFFFFFF, obj, f(N_GET_DEGRADATION, obj), f(N_GET_PERM_DEGRAD, obj),
        f(N_GET_DAMAGE, obj), f(N_GET_DIRT, obj), f(N_GET_SOOT, obj))
end

RegisterNetEvent('spk_wear:run', function(action, value)
    local ped = Citizen.InvokeNative(N_PLAYER_PED_ID, Citizen.ResultAsInteger())
    local obj, hash = weaponObject(ped)
    if not obj then return say('no weapon entity in hand (draw a gun first). weaponHash=' .. tostring(hash)) end

    if action == 'get' then
        say(dump(obj, hash))
    elseif action == 'set' then
        if not value or value < 0.0 or value > 1.0 then return say('usage: /spk_wear set <0..1>') end
        say('before: ' .. dump(obj, hash))
        Citizen.InvokeNative(N_SET_DEGRADATION, obj, value + 0.0)
        Wait(300)
        say('after set ' .. value .. ': ' .. dump(obj, hash))
        say('Holster/redraw and run /spk_wear get: does the value persist per weapon?')
    else
        say('usage: /spk_wear get | /spk_wear set <0..1>')
    end
end)
