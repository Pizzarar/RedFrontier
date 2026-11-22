-- spk_pelt client. Natives by hash (names from alloc8or rdr3 nativedb; see README).
local N_PLAYER_PED_ID    = 0x096275889B8E0EE0
local N_GET_COORDS       = 0xA86D5F069399F44D -- GET_ENTITY_COORDS(entity, alive, realCoords)
local N_GET_FORWARD      = 0x2412D9C05BB09B97 -- GET_ENTITY_FORWARD_VECTOR(entity)
local N_GET_HEADING      = 0xC230DD956E2F5507 -- GET_ENTITY_HEADING
local N_REQUEST_MODEL    = 0xFA28FE3A6246FC30
local N_HAS_MODEL_LOADED = 0x1283B8B89DD5D1B6
local N_CREATE_PED       = 0xD49F9B0955C367DE
local N_RANDOM_OUTFIT    = 0x283978A15512B2FE -- _SET_RANDOM_OUTFIT_VARIATION(ped, true)
local N_PLACE_GROUND    = 0x9587913B9E772D29 -- PLACE_ENTITY_ON_GROUND_PROPERLY(entity, p1)
local N_DOES_EXIST       = 0xD42BD6EB2E0F1677
local N_IS_DEAD          = 0x7D5B1F88E7504BBA -- IS_ENTITY_DEAD
local N_GET_HEALTH       = 0x82368787EA73C0F7
local N_LAST_DMG_BONE    = 0xD75960F6BD9EA49C -- GET_PED_LAST_DAMAGE_BONE(ped, int* outBone) -> BOOL
local N_CAUSE_OF_DEATH   = 0x16FFE42AB2D2DC59 -- GET_PED_CAUSE_OF_DEATH(ped) -> Hash
local N_SOURCE_OF_DEATH  = 0x93C8B64DEB84728C -- GET_PED_SOURCE_OF_DEATH(ped) -> Entity
local N_GET_QUALITY      = 0x7BCC6087D130312A -- _GET_PED_QUALITY(ped) -> int  (ePedQuality LOW/MED/HIGH)
local N_GET_CLEANLINESS  = 0x88EFFED5FE8B0B4A -- _GET_PED_DAMAGE_CLEANLINESS(ped) -> int (POOR/GOOD/PERFECT)
local N_IS_SKINNED       = 0x88A5564B19C15391 -- _IS_ANIMAL_SKINNED(ped)
local N_IS_FULLY_LOOTED  = 0x8DE41E9902E85756 -- _IS_ENTITY_FULLY_LOOTED(entity)
local N_CARRIABLE_PELT   = 0x255B6DB4E3AD3C3E -- _GET_IS_CARRIABLE_PELT(entity)
local N_CARCASS_FROM_PELT = 0x2A77EF9BEC8518F4 -- _GET_CARCASS_FROM_PELT(entity) -> Entity

local function bool(v) return v == true or (type(v) == 'number' and v ~= 0) end
local function say(msg)
    print('[spk_pelt] ' .. msg)
    lib.notify({ title = 'spk_pelt', description = msg, type = 'inform', duration = 8000 })
end
local function inv(h, ...) return Citizen.InvokeNative(h, ...) end

local function readInt(h, e) return inv(h, e, Citizen.ResultAsInteger()) end

-- snapshot of everything readable
local function snapshot(deer, label, lastBone)
    local ok, bone = inv(N_LAST_DMG_BONE, deer.ped, Citizen.PointerValueInt(), Citizen.ReturnResultAnyway())
    return ('%s %s: quality=%s cleanliness=%s lastBoneNow=%s(ok=%s) lastBoneSeenAlive=%s cause=0x%X source=%s(player=%s) health=%s skinned=%s fullyLooted=%s carriablePelt=%s carcassFromPelt=%s'):format(
        deer.name, label,
        tostring(readInt(N_GET_QUALITY, deer.ped)), tostring(readInt(N_GET_CLEANLINESS, deer.ped)),
        tostring(bone), tostring(bool(ok)), tostring(lastBone),
        (readInt(N_CAUSE_OF_DEATH, deer.ped) or 0) & 0xFFFFFFFF, tostring(readInt(N_SOURCE_OF_DEATH, deer.ped)), tostring(readInt(N_SOURCE_OF_DEATH, deer.ped) == inv(N_PLAYER_PED_ID, Citizen.ResultAsInteger())),
        tostring(readInt(N_GET_HEALTH, deer.ped)),
        tostring(bool(inv(N_IS_SKINNED, deer.ped))), tostring(bool(inv(N_IS_FULLY_LOOTED, deer.ped))),
        tostring(bool(inv(N_CARRIABLE_PELT, deer.ped))), tostring(readInt(N_CARCASS_FROM_PELT, deer.ped)))
end

local function spawnDeer(name, x, y, z, h)
    local model = GetHashKey('a_c_deer_01') -- cfx joaat
    inv(N_REQUEST_MODEL, model, false)
    local t = GetGameTimer()
    while not bool(inv(N_HAS_MODEL_LOADED, model)) and GetGameTimer() - t < 5000 do Wait(50) end
    if not bool(inv(N_HAS_MODEL_LOADED, model)) then return nil, 'model a_c_deer_01 did not load' end
    local ped = inv(N_CREATE_PED, model, x, y, z, h, true, false, false, false, Citizen.ResultAsInteger())
    if ped == 0 then return nil, 'CREATE_PED returned 0' end
    inv(N_RANDOM_OUTFIT, ped, true)
    inv(N_PLACE_GROUND, ped, true)
    return { ped = ped, name = name }
end

local function watch(deer)
    CreateThread(function()
        local lastBone, died = nil, false
        while bool(inv(N_DOES_EXIST, deer.ped)) do
            local dead = bool(inv(N_IS_DEAD, deer.ped))
            local ok, bone = inv(N_LAST_DMG_BONE, deer.ped, Citizen.PointerValueInt(), Citizen.ReturnResultAnyway())
            if bool(ok) and bone and bone ~= 0 then lastBone = bone end
            if dead and not died then
                died = true
                say(snapshot(deer, 'DEAD', lastBone))
            elseif died and bool(inv(N_IS_SKINNED, deer.ped)) then
                say(snapshot(deer, 'SKINNED', lastBone))
                return
            end
            Wait(100)
        end
        if died then say(deer.name .. ' entity gone (skinning usually removes carcass); last bone seen = ' .. tostring(lastBone)) end
    end)
end

RegisterNetEvent('spk_pelt:run', function()
    local ped = inv(N_PLAYER_PED_ID, Citizen.ResultAsInteger())
    local c = inv(N_GET_COORDS, ped, true, true, Citizen.ResultAsVector())
    local f = inv(N_GET_FORWARD, ped, Citizen.ResultAsVector())
    local h = inv(N_GET_HEADING, ped, Citizen.ResultAsFloat())
    local side = vector3(-f.y, f.x, 0.0) -- right-hand perpendicular
    for i, off in ipairs({ -1.5, 1.5 }) do
        local p = c + f * 20.0 + side * off
        local deer, err = spawnDeer(i == 1 and 'deerA(head?)' or 'deerB(body?)', p.x, p.y, p.z, (h + 180.0) % 360.0)
        if deer then
            watch(deer)
        else
            say('spawn failed: ' .. err)
        end
    end
    say('2 deer spawned ~20m ahead. Shoot A in the head, B in the body, then skin both. Results print here + F8.')
end)
