-- Static check: fh client/shared code must not call unknown global natives by CamelCase name.
--
-- A "native-style" call is an identifier starting with an uppercase letter invoked as a bare global (not a method,
-- field, or table access). Every such call must be one of:
--   (a) a RDR3 native RedM exposes by name (NativeDB name -> CamelCase, leading underscore stripped;
--       e.g. GET_ENTITY_COORDS -> GetEntityCoords, _HAS_ENTITY_BEEN_DAMAGED_BY_WEAPON -> HasEntityBeenDamagedByWeapon),
--   (b) a CfxLua / CFX runtime builtin (CreateThread, Wait, RegisterNetEvent, exports, Entity, ...),
--   (c) defined locally in fh code (any `local`/`function` declaration).
--
-- Anything else is a global that is nil at runtime (e.g. GTA-V-only names such as ClearEntityLastWeaponDamage or
-- GiveWeaponToPed_2, whose RDR3 equivalents are _CLEAR_PED_LAST_WEAPON_DAMAGE and GIVE_WEAPON_TO_PED). Add a newly
-- used exposed native/builtin to ALLOW (keep it sorted); locals are detected automatically.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local case = T.it

local FH = here .. '../server/resources/[fh]/'

-- Checked-in allowlist of names fh client/shared code may call as a bare global (exposed natives + CFX builtins).
local ALLOW = {
    -- RDR3 natives exposed by name
    'AddRelationshipGroup', 'CreateObject', 'CreatePed', 'CreateVehicle', 'DeleteEntity', 'DeleteObject',
    'DisableAllControlActions', 'DisableControlAction', 'DoesAnimDictExist', 'DoesEntityExist',
    'EnableControlAction', 'FreezeEntityPosition', 'GetCloudTimeAsInt', 'GetCurrentPedWeapon',
    'GetEntityBoneIndexByName', 'GetEntityCoords', 'GetEntityHealth', 'GetEntityModel', 'GetGameTimer',
    'GetGroundZFor_3dCoord', 'GetHashKey', 'GetMount', 'GetPedBoneIndex', 'HasAnimDictLoaded', 'HasClipSetLoaded',
    'HasEntityBeenDamagedByWeapon', 'HasModelLoaded', 'IsControlJustReleased', 'IsDisabledControlJustReleased',
    'IsEntityDead', 'IsEntityInWater', 'IsModelInCdimage', 'IsModelValid', 'IsPauseMenuActive', 'IsPedAPlayer',
    'IsPedDeadOrDying', 'IsPedOnMount', 'IsThisModelAHorse', 'NetworkDoesNetworkIdExist',
    'NetworkGetEntityFromNetworkId', 'NetworkGetEntityIsNetworked', 'NetworkGetNetworkIdFromEntity',
    'PlaceObjectOnGroundProperly', 'PlayerId', 'PlayerPedId', 'RemoveAnimDict', 'RemoveBlip', 'RemoveWeaponFromPed',
    'RequestAnimDict', 'RequestClipSet', 'RequestCollisionAtCoord', 'RequestModel', 'SetBlipScale', 'SetBlipSprite',
    'SetBlockingOfNonTemporaryEvents', 'SetCurrentPedWeapon', 'SetEntityAsMissionEntity', 'SetEntityCollision',
    'SetEntityCoords',
    'SetEntityHeading',
    'SetEntityInvincible', 'SetModelAsNoLongerNeeded', 'SetPedCanRagdoll', 'SetPedCombatAttributes',
    'SetPedFleeAttributes', 'SetPedRelationshipGroupHash', 'SetRelationshipBetweenGroups',
    'TaskCombatHatedTargetsAroundPed', 'TaskPlayAnim', 'Wait',
    -- CfxLua / CFX runtime builtins
    'AddEventHandler', 'CreateThread', 'Entity', 'GetConvarInt', 'GetCurrentResourceName', 'GetGamePool',
    'GetResourceState', 'IsNuiFocused', 'RegisterCommand', 'RegisterNUICallback', 'RegisterNetEvent',
    'SendNUIMessage', 'SetNuiFocus', 'SetNuiFocusKeepInput', 'TriggerEvent', 'TriggerServerEvent',
}

-- Strip comments (--, --[[ ]], --[=[ ]=]) and string literals ('', "", [[ ]], [=[ ]=]) so they can't
-- produce false positives (or hide a call). Returns the stripped source.
local function strip(src)
    local out = {}
    local i, n = 1, #src
    local function longClose(eq) return ']' .. eq .. ']' end
    while i <= n do
        local c = src:sub(i, i)
        local cmtEq = src:match('^%-%-%[(=*)%[', i)
        if cmtEq then
            local close = longClose(cmtEq)
            local j = src:find(close, i + 2 + #cmtEq, true)
            out[#out + 1] = ' '
            i = j and (j + #close) or (n + 1)
        elseif src:sub(i, i + 1) == '--' then
            local j = src:find('\n', i + 2, true)
            out[#out + 1] = ' '
            i = j or (n + 1)
        elseif c == '"' or c == "'" then
            local q = c
            local j = i + 1
            while j <= n do
                if src:sub(j, j) == '\\' then j = j + 2
                elseif src:sub(j, j) == q then break
                else j = j + 1 end
            end
            out[#out + 1] = ' '
            i = j + 1
        elseif src:sub(i, i + 1) == '[[' or src:match('^%[(=*)%[', i) then
            local eq = src:match('^%[(=*)%[', i) or ''
            local close = longClose(eq)
            local j = src:find(close, i + 2 + #eq, true)
            out[#out + 1] = ' '
            i = j and (j + #close) or (n + 1)
        else
            out[#out + 1] = c
            i = i + 1
        end
    end
    return table.concat(out)
end

-- CamelCase globals invoked as a bare function: `Name(` not preceded by a word char, dot, or colon.
local function calls(s)
    local out = {}
    local pos = 1
    while true do
        local a, b, name = s:find('([A-Z][%w_]*)%s*%(', pos)
        if not a then break end
        local prev = (a > 1) and s:sub(a - 1, a - 1) or ''
        if not prev:match('[%w_.:]') then out[name] = true end
        pos = b + 1
    end
    return out
end

-- CamelCase names declared locally (any `local`/`function` form); table methods are not globals so only the
-- root is collected, which is enough to avoid flagging `local X = ...` then `X(`.
local function localDefs(s)
    local out = {}
    local function add(name)
        if name and name:match('^[A-Z]') then out[name] = true end
    end
    for name in s:gmatch('function%s+([%a_][%w_]*)') do add(name) end
    for name in s:gmatch('local%s+([%a_][%w_]*)%s*=%s*function') do add(name) end
    for name in s:gmatch('local%s+([%a_][%w_]*)') do add(name) end
    return out
end

local function listFiles()
    local tmp = os.tmpname()
    local cmd = "find '" .. FH .. "' \\( -path '*/client/*.lua' -o -path '*/shared/*.lua' -o -name 'config.lua' \\) -type f 2>/dev/null > '" .. tmp .. "'"
    os.execute(cmd)
    local files = {}
    local f = io.open(tmp, 'r')
    if f then
        for line in f:lines() do
            if line:match('%.lua$') then files[#files + 1] = line end
        end
        f:close()
    end
    os.remove(tmp)
    return files
end

case('fh client/shared code calls no unknown global native', function()
    local allow = {}
    for _, n in ipairs(ALLOW) do allow[n] = true end

    local files = listFiles()
    assert(#files > 0, 'no fh client/shared files found (find failed?)')

    -- Pass 1: read every file and collect locally-declared CamelCase names first, so a local defined in one file
    -- is allowed when called in another (shared modules).
    local sources = {}
    for _, path in ipairs(files) do
        local f = io.open(path, 'r')
        if f then
            sources[path] = strip(f:read('*a'))
            f:close()
            for name in pairs(localDefs(sources[path])) do allow[name] = true end
        end
    end

    -- Pass 2: flag any bare CamelCase call not in the allowlist / local set.
    local bad = {}
    for path, s in pairs(sources) do
        for name in pairs(calls(s)) do
            if not allow[name] then bad[name] = true end
        end
    end

    local names = {}
    for name in pairs(bad) do names[#names + 1] = name end
    table.sort(names)
    assert(#names == 0, 'unknown global native(s) in fh client/shared code: ' .. table.concat(names, ', '))
end)

case('fh:tp:snap is registered only when the resource is fh_core', function()
    -- fh_core/client/ground_snap.lua is @-included by fh_homestead and fh_zones too; an unguarded FH.onNet here would
    -- register the snap handler three times (three snap loops / SetEntityCoords per teleport). The guard must appear
    -- before the handler registration, as in fh_core/client/safe.lua.
    local f = assert(io.open(FH .. 'fh_core/client/ground_snap.lua', 'r'))
    local src = f:read('*a')
    f:close()
    local handler = src:find('fh:tp:snap', 1, true)
    assert(handler, 'fh:tp:snap handler missing')
    local guard = src:find("GetCurrentResourceName() == 'fh_core'", 1, true)
        or src:find('GetCurrentResourceName() == "fh_core"', 1, true)
    assert(guard, 'GetCurrentResourceName() == "fh_core" guard missing')
    assert(guard < handler, 'fh:tp:snap must be registered after (inside) the fh_core-only guard')
end)

T.finish()
