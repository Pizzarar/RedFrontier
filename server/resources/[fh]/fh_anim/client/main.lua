-- fh_anim client: cosmetic named animations. Never errors on unknown key / flag off (returns false).
-- Scenarios start via the hash form (rsg-core/client/progress.lua:45), NOT ox_lib anim.scenario.
local Logic, Tbl = FhAnimLogic, FhAnimTable
local active, seq = nil, 0 -- active = { key, id, scenario, dict, clip }

local function pedState(ped)
    return {
        mounted = IsPedOnMount(ped) and true or false,
        inVehicle = IsPedInAnyVehicle(ped, false) and true or false,
        swimming = IsPedSwimming(ped) and true or false,
        dead = IsEntityDead(ped) and true or false,
        ragdoll = IsPedRagdoll(ped) and true or false,
        inScenario = IsPedActiveInScenario(ped) and true or false,
    }
end

local function stillPlaying(ped, a)
    if a.scenario then return IsPedActiveInScenario(ped) and true or false end
    return IsEntityPlayingAnim(ped, a.dict, a.clip, 3) and true or false
end

local function clearIfOurs(token, key)
    local a = active
    if not a or (token and not Logic.isOurs(a, token)) then return end
    if Logic.shouldClear(a, key, stillPlaying(PlayerPedId(), a)) then
        ClearPedTasks(PlayerPedId())
        active = nil
    elseif key == nil or a.key == key then
        active = nil -- ours, but already ended on its own
    end
end

local function begin(key)
    local e = Logic.lookup(Tbl, Config.Enabled, key)
    if not e then return false end
    local ped = PlayerPedId()
    if active then clearIfOurs(nil, nil) end
    if not Logic.guard(pedState(ped)) then return false end
    seq = seq + 1
    local token = { key = key, id = seq, scenario = e.scenario, dict = e.dict, clip = e.clip }
    if e.scenario then
        TaskStartScenarioInPlaceHash(ped, joaat(e.scenario), -1, true, false, false, false)
    else
        local ok = pcall(lib.requestAnimDict, e.dict)
        if not ok then return false end
        lib.playAnim(ped, e.dict, e.clip, 8.0, -8.0, e.ms or -1, e.flag or 49, 0.0, false, false, false)
    end
    active = token
    return token, e
end

local function play(key)
    local ok, token, e = pcall(begin, key)
    if not ok or not token then return false end
    CreateThread(function()
        Wait(e.ms or 2000)
        clearIfOurs(token, token.key)
    end)
    return true
end

local function start(key)
    local ok, token = pcall(begin, key)
    return ok and token ~= false and token ~= nil
end

local function stop(key)
    if not active then return false end
    clearIfOurs(nil, key)
    return true
end

exports('play', play)
exports('start', start)
exports('stop', stop)

RegisterNetEvent('fh:anim:play', function(key) play(key) end)
