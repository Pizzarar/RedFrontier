-- spk_anim client: throwaway probe for the core-animations plan (A0). Every row is candidate, unproven.
--   /spk_anim list            print the rows
--   /spk_anim <n>             play row n twice: hash form (native), then string form (ox_lib progressBar)
--   /spk_anim <n> hash        hash form only
--   /spk_anim <n> string      string form only
--   /spk_anim stop            clear tasks and cancel any playing row
-- Scenario rows: hash form = TaskStartScenarioInPlaceHash(ped, joaat(name), 3000, true, 0, -1.0, false), the
-- pattern rsg-core/client/progress.lua:45 uses; string form = lib.progressBar{anim={scenario=name}}, which
-- ox_lib routes to TaskStartScenarioInPlace(ped, name, 0, ...) (ox_lib progress.lua:92).
-- Dict rows: hash form = RequestAnimDict + TaskPlayAnim + RemoveAnimDict (fh_inventory/client/main.lua:175 and
-- rsg-core/client/progress.lua:49); string form = lib.progressBar{anim={dict=,clip=}}.
-- Only the baseline row is proven in this repo (fh_inventory/client/main.lua:177). Every other name is a
-- well-known RDR3 name, NOT confirmed by repo usage: candidate, unproven.
-- No convar/flag gates this (see the plan Decided): always on, like the other spk_* spikes.

local N_TASK_PLAY_ANIM = 0xEA47FE3719165B94 -- TASK_PLAY_ANIM (called by name below)
local N_CLEAR_PED_TASKS = 0xE1EF3C1216AFF2CD -- CLEAR_PED_TASKS (called by name below)

local PLAY_MS = 3000

-- kind = 'scenario' (name) or 'dict' (dict + clip). All rows candidate, unproven except baseline.
local ROWS = {
    { key = 'skin',       kind = 'scenario', name = 'WORLD_HUMAN_CROUCH_INSPECT',        proven = false },
    { key = 'gather',     kind = 'scenario', name = 'WORLD_HUMAN_CROUCH_INSPECT',        proven = false },
    { key = 'eat',        kind = 'dict', dict = 'mech_inventory@eating@multi_bite', clip = 'quick_left_hand', proven = false },
    { key = 'drink',      kind = 'dict', dict = 'mech_inventory@drinking@multi_sip', clip = 'quick_left_hand', proven = false },
    { key = 'craft',      kind = 'scenario', name = 'WORLD_HUMAN_HAMMER_TABLE',          proven = false },
    { key = 'cook',       kind = 'scenario', name = 'WORLD_HUMAN_STIR_POT',              proven = false },
    { key = 'chest_open', kind = 'scenario', name = 'WORLD_HUMAN_CROUCH_INSPECT',        proven = false },
    { key = 'trough',     kind = 'scenario', name = 'WORLD_HUMAN_BUCKET_POUR_LOW',       proven = false },
    { key = 'plant',      kind = 'scenario', name = 'WORLD_HUMAN_FARMER_WEEDING',        proven = false },
    { key = 'refill',     kind = 'scenario', name = 'WORLD_HUMAN_WASH_FACE_BUCKET_GROUND', proven = false },
    { key = 'baseline',   kind = 'dict', dict = 'mech_inventory@item@fallbacks@tonic_potent@offhand', clip = 'use_quick', proven = true },
    -- dict alternates (candidate, unproven)
    { key = 'gather_alt', kind = 'dict', dict = 'amb_work@world_human_pickup@male_a@base', clip = 'base', proven = false },
    { key = 'craft_alt',  kind = 'dict', dict = 'amb_work@world_human_hammer@table@male_a@base', clip = 'base', proven = false },
}

local gen = 0 -- generation counter: every start/stop bumps it; stale threads see a mismatch and bail

local function say(msg)
    print('[spk_anim] ' .. msg)
    lib.notify({ title = 'spk_anim', description = msg, type = 'inform', duration = 6000 })
end

local function rowLabel(i, row)
    local what = row.kind == 'scenario' and row.name or (row.dict .. ' / ' .. row.clip)
    return ('%d %s [%s] %s%s'):format(i, row.key, row.kind, what, row.proven and '' or ' (candidate, unproven)')
end

-- Clear tasks and cancel any ox_lib progress bar. Safe to call when nothing plays.
local function stopAll()
    gen = gen + 1
    if lib.progressActive and lib.progressActive() then lib.cancelProgress() end
    ClearPedTasks(PlayerPedId())
end

-- Wait up to PLAY_MS, returning false early if a newer start/stop superseded generation g.
local function waitPlay(g)
    local t = GetGameTimer() + PLAY_MS
    while GetGameTimer() < t do
        if g ~= gen then return false end
        Wait(100)
    end
    return g == gen
end

local function playHash(g, i, row)
    local ped = PlayerPedId()
    say(('playing %s, hash form'):format(rowLabel(i, row)))
    if row.kind == 'scenario' then
        TaskStartScenarioInPlaceHash(ped, joaat(row.name), PLAY_MS, true, 0, -1.0, false)
    else
        RequestAnimDict(row.dict)
        local t = GetGameTimer() + 3000
        while not HasAnimDictLoaded(row.dict) and GetGameTimer() < t do Wait(50) end
        if not HasAnimDictLoaded(row.dict) then
            RemoveAnimDict(row.dict)
            say(('FAIL %s: dict did not load'):format(row.key))
            return false
        end
        TaskPlayAnim(ped, row.dict, row.clip, 3.0, 1.0, PLAY_MS, 49, 0, false, false, false)
        RemoveAnimDict(row.dict)
    end
    local ok = waitPlay(g)
    if ok then ClearPedTasks(PlayerPedId()) end
    return ok
end

local function playString(g, i, row)
    say(('playing %s, string form'):format(rowLabel(i, row)))
    local anim
    if row.kind == 'scenario' then
        anim = { scenario = row.name }
    else
        anim = { dict = row.dict, clip = row.clip }
    end
    lib.progressBar({
        duration = PLAY_MS,
        label = row.key .. ' (string form)',
        useWhileDead = false,
        canCancel = true,
        anim = anim,
    })
    if g == gen then ClearPedTasks(PlayerPedId()) end
    return g == gen
end

-- Start row i; form = 'hash' | 'string' | nil (both, hash first). Re-running mid-play cancels the old run.
local function startRow(i, form)
    local row = ROWS[i]
    if not row then
        say(('no row %s; /spk_anim list'):format(tostring(i)))
        return
    end
    stopAll()
    local g = gen
    CreateThread(function()
        if g ~= gen then return end
        if form ~= 'string' then
            if not playHash(g, i, row) then return end
        end
        if form ~= 'hash' then
            if form == nil then Wait(500) end
            if g ~= gen then return end
            playString(g, i, row)
        end
        if g == gen then say(('done %s'):format(row.key)) end
    end)
end

local function listRows()
    for i, row in ipairs(ROWS) do print('[spk_anim] ' .. rowLabel(i, row)) end
    say('rows printed to F8')
end

RegisterCommand('spk_anim', function(_, args)
    local a = args[1]
    if a == nil or a == 'list' then return listRows() end
    if a == 'stop' then
        stopAll()
        return say('stopped')
    end
    local form = args[2]
    if form ~= nil and form ~= 'hash' and form ~= 'string' then
        return say('form must be hash or string')
    end
    local i = tonumber(a)
    if not i then return say('usage: /spk_anim list | <n> [hash|string] | stop') end
    startRow(math.floor(i), form)
end, false)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then stopAll() end
end)
