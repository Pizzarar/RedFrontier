-- fh_hunting client (spec L8, H2). (1) Tracks huntable animals near the player while they are alive: last damage
-- bone and weapon hits; on death the record is kept by netId. (2) An rsg-target "Skin" option on dead carcasses of
-- the animal table sends fh:hunting:skin. The server re-reads the carcass and decides everything; the shot data is
-- only the quality hint (plan hunting-01-l8, Decided "Quality source").
-- Natives (fh_core/docs/natives.md, all UNVERIFIED in-game): GET_PED_LAST_DAMAGE_BONE, GET_PED_CAUSE_OF_DEATH,
-- _GET_PED_QUALITY, _GET_PED_DAMAGE_CLEANLINESS (by hash, from spk_pelt), GetPedBoneIndex, GetEntityBoneIndexByName,
-- HasEntityBeenDamagedByWeapon, ClearEntityLastWeaponDamage, GetGamePool, PlayerPedId, GetEntityCoords, GetEntityModel,
-- IsPedAPlayer, IsEntityDead, IsControlJustReleased (H3 trapper prompt, input 0xCEFD9220 = context key), DoesEntityExist, NetworkGetEntityIsNetworked, NetworkGetNetworkIdFromEntity, GetGameTimer.
local cfg, animals = FhHuntingConfig, FhHuntingAnimals

local N_LAST_DMG_BONE   = 0xD75960F6BD9EA49C -- GET_PED_LAST_DAMAGE_BONE(ped, int* outBone) -> BOOL
local N_CAUSE_OF_DEATH  = 0x16FFE42AB2D2DC59 -- GET_PED_CAUSE_OF_DEATH(ped) -> weapon hash
local N_GET_QUALITY     = 0x7BCC6087D130312A -- _GET_PED_QUALITY(ped) -> int
local N_GET_CLEANLINESS = 0x88EFFED5FE8B0B4A -- _GET_PED_DAMAGE_CLEANLINESS(ped) -> int

local alive = {} -- [ped] = { raw = bone id, bone = name|id, hits }
local dead = {}  -- [netId] = { bone, hits, explosive, at }
local explosive = {}
for _, w in ipairs(cfg.ExplosiveWeapons or {}) do explosive[joaat(w) & 0xFFFFFFFF] = true end

local function bool(v) return v == true or (type(v) == 'number' and v ~= 0) end

local function lastBone(ped)
    local ok, bone = Citizen.InvokeNative(N_LAST_DMG_BONE, ped, Citizen.PointerValueInt(), Citizen.ReturnResultAnyway())
    if bool(ok) and type(bone) == 'number' and bone ~= 0 then return bone end
    return nil
end

-- A configured bone name when the hit bone is one of them (same bone index on this ped), else the raw id: the
-- server maps unknown ids to DefaultZone. Avoids hard-coding bone ids nobody has verified.
local function boneName(ped, bone)
    local idx = GetPedBoneIndex(ped, bone)
    if type(idx) ~= 'number' or idx < 0 then return bone end
    for name in pairs(cfg.BoneZones) do
        if type(name) == 'string' and GetEntityBoneIndexByName(ped, name) == idx then return name end
    end
    return bone
end

local function readBone(ped, t)
    local b = lastBone(ped)
    if b and b ~= t.raw then t.raw, t.bone = b, boneName(ped, b) end
end

-- One weapon hit per sample where the weapon-damage flag is set; cleared after reading, so bleeding (no weapon)
-- does not count. Two hits inside one sample count once (lenient).
local function readHit(ped, t)
    if bool(HasEntityBeenDamagedByWeapon(ped, 0, 2)) then
        t.hits = t.hits + 1
        ClearEntityLastWeaponDamage(ped)
    end
end

local function onDeath(ped, t)
    readBone(ped, t) -- the killing shot
    readHit(ped, t)
    if NetworkGetEntityIsNetworked(ped) then
        local cause = Citizen.InvokeNative(N_CAUSE_OF_DEATH, ped, Citizen.ResultAsInteger()) or 0
        dead[NetworkGetNetworkIdFromEntity(ped)] = {
            bone = t.bone, hits = math.max(t.hits, 1), explosive = explosive[cause & 0xFFFFFFFF] == true,
            at = GetGameTimer(),
        }
    end
end

FH.thread(function()
    while true do
        Wait(cfg.TrackIntervalMs)
        local me = PlayerPedId()
        local here = GetEntityCoords(me)
        local seen = {}
        for _, ped in ipairs(GetGamePool('CPed')) do
            if ped ~= me and not IsPedAPlayer(ped) and animals.get(GetEntityModel(ped))
                and #(GetEntityCoords(ped) - here) <= cfg.TrackRadius then
                local t = alive[ped]
                if not IsEntityDead(ped) then
                    if not t then
                        t = { hits = 0 }
                        alive[ped] = t
                        ClearEntityLastWeaponDamage(ped) -- count only hits from now on
                    end
                    seen[ped] = true
                    readBone(ped, t)
                    readHit(ped, t)
                elseif t then
                    onDeath(ped, t) -- not marked seen: dropped from `alive` below
                end
            end
        end
        for ped in pairs(alive) do
            if not seen[ped] then alive[ped] = nil end
        end
        local cutoff = GetGameTimer() - cfg.DeadCacheSeconds * 1000
        for netId, d in pairs(dead) do
            if d.at < cutoff then dead[netId] = nil end
        end
    end
end)

-- ---------------------------------------------------------------- Skin prompt

local busy = false

local function skin(entity)
    if busy or not DoesEntityExist(entity) or not IsEntityDead(entity) then return end
    if not NetworkGetEntityIsNetworked(entity) then
        return lib.notify({ title = 'Hunting', description = 'This carcass cannot be skinned.', type = 'error' })
    end
    local netId = NetworkGetNetworkIdFromEntity(entity)
    busy = true
    -- pcall: if the progress bar throws, `busy` must still reset or the Skin option stays locked forever.
    local ok, done = pcall(lib.progressBar, {
        duration = cfg.SkinDurationMs, label = 'Skinning...', canCancel = true,
        disable = { move = true, car = true, combat = true },
    })
    busy = false
    if not ok or not done then return end
    local d = dead[netId] or {}
    local payload = { netId = netId, bone = d.bone, hits = d.hits, explosive = d.explosive == true }
    if cfg.PeltQualitySource == 'native' and DoesEntityExist(entity) then
        payload.nativeQuality = Citizen.InvokeNative(N_GET_QUALITY, entity, Citizen.ResultAsInteger())
        payload.cleanliness = Citizen.InvokeNative(N_GET_CLEANLINESS, entity, Citizen.ResultAsInteger())
    end
    TriggerServerEvent('fh:hunting:skin', payload)
end

local models = {}
for _, a in ipairs(animals.list) do
    if not a.legendary then models[#models + 1] = a.model end
end

local OPTION = 'fh_hunting:skin'

FH.thread(function()
    exports['rsg-target']:addModel(models, {
        {
            name = OPTION, label = 'Skin', icon = 'fa-solid fa-paw', distance = cfg.SkinPromptDistance,
            canInteract = function(entity)
                return not busy and IsEntityDead(entity) and not Entity(entity).state.fhSkinned
            end,
            onSelect = function(data) FH.thread(function() skin(data.entity) end) end,
        },
    })
end)

FH.on('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    exports['rsg-target']:removeModel(models, OPTION)
end)

-- ---------------------------------------------------------------- H3 trapper

-- Sell prompt at the trapper (cfg.Trapper). The server re-checks range, container, item and price; the rows below
-- are only what it sent us for display.
local CONTEXT_KEY = 0xCEFD9220 -- INPUT_CONTEXT (E). UNVERIFIED
local tp = cfg.Trapper

-- ---------------------------------------------------------------- H4 legendary bear chain

local lb = cfg.LegendaryBear
local chainStep = 0 -- 1 rumour -> 2 track -> 3 carcass -> 4 spawned -> 5 complete (server tells us)

-- Shared TextUI: track the currently-shown string so a chain-step change can re-render (or hide) the active prompt
-- immediately, instead of waiting for the player to leave and re-enter the point.
local shownText = nil
local function showText(text)
    if text ~= shownText then
        shownText = text
        lib.showTextUI(text)
    end
end
local function hideText()
    if shownText then shownText = nil; lib.hideTextUI() end
end

FH.onNet('fh:hunting:chain_state', function(state)
    if type(state) == 'table' and type(state.step) == 'number' then chainStep = state.step end
end)

-- Ask the server for the current step once the character is loaded (the server needs a citizenid), and again on every
-- load/reload. Every action pushes a fresh state back too.
FH.thread(function() TriggerServerEvent('fh:hunting:chain_status') end)
AddEventHandler('RSGCore:Client:OnPlayerLoaded', function() TriggerServerEvent('fh:hunting:chain_status') end)

-- Inspectable clue markers (steps 2 and 3). The server gates which step is allowed; the prompt only shows on the
-- marker that belongs to the current step.
if lb then
    for step, m in pairs(lb.markers) do
        FH.thread(function()
            local point = lib.points.new({
                coords = vec3(m.coords.x, m.coords.y, m.coords.z), distance = m.radius,
            })
            function point:onEnter() point:render() end
            function point:onExit() hideText() end
            function point:render()
                if chainStep == step then showText('[E] Inspect ' .. m.label) else hideText() end
            end
            function point:nearby()
                point:render() -- keep the prompt in sync with chainStep
                if chainStep == step and IsControlJustReleased(0, CONTEXT_KEY) then
                    TriggerServerEvent('fh:hunting:chain_inspect', { marker = m.id })
                end
            end
        end)
    end
end

local function stars(n) return string.rep('*', n) end

FH.onNet('fh:hunting:sell_rows', function(rows)
    if type(rows) ~= 'table' or #rows == 0 then
        return lib.notify({ title = 'Trapper', description = 'You have no pelts to sell here.', type = 'inform' })
    end
    local options = {}
    for _, r in ipairs(rows) do
        options[#options + 1] = {
            title = ('%s %s%s'):format(r.label, stars(r.stars), r.legendary and ' (Legendary)' or ''),
            description = ('$%d, from your %s'):format(r.price, r.container),
            onSelect = function()
                TriggerServerEvent('fh:hunting:sell', { container = r.container, slot = r.slot, item = r.item })
            end,
        }
    end
    lib.registerContext({ id = 'fh_hunting_trapper', title = tp.label, options = options })
    lib.showContext('fh_hunting_trapper')
end)

local trapperPoint
FH.thread(function()
    trapperPoint = lib.points.new({
        coords = vec3(tp.coords.x, tp.coords.y, tp.coords.z), distance = tp.PromptDistance,
    })
    function trapperPoint:onEnter() trapperPoint:render() end
    function trapperPoint:onExit() hideText() end
    function trapperPoint:render()
        -- Step 1: the trapper has a rumour to sell. Afterwards (and for everyone past step 1) E sells pelts.
        showText(chainStep == 1 and '[E] Ask about the legendary bear' or '[E] Sell pelts')
    end
    function trapperPoint:nearby()
        trapperPoint:render() -- keep the prompt in sync with chainStep
        if IsControlJustReleased(0, CONTEXT_KEY) then
            if chainStep == 1 then TriggerServerEvent('fh:hunting:chain_rumour') else TriggerServerEvent('fh:hunting:sell_open') end
        end
    end
end)

FH.on('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    hideText()
    if trapperPoint then trapperPoint:remove(); trapperPoint = nil end
end)
