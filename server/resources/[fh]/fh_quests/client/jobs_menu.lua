-- WORKAROUND (plan quests-01 Q3): ox_lib context-menu jobs board. `/jobs` (dev/player command) and an rsg-target
-- sphere zone at each board spot open it. It is replaced by the @ui jobs-board screen that renders the
-- fh:quests:sync schema from the README; delete this file, server/menu.lua and the fxmanifest lines then.
-- No NUI. Board spot coordinates and the prop model are guesses: TODO-verify-in-game.
local BOARDS = {
    { region_id = 'heartlands', label = 'Jobs board', coords = vector3(-297.0, 795.0, 118.0),
        model = 'p_notice_board01x' }, -- model unverified; if invalid only the target zone is made
}
local DEFAULT_REGION = 'heartlands'
local MENU = 'fh_quests_jobs'

local ERR = {
    fh_offer_gone = 'That job is no longer on the board.',
    fh_bounty_taken = 'Somebody is already after that one.',
    fh_busy = 'Try again in a moment.',
}

local function notify(description, kind)
    lib.notify({ title = 'Jobs', description = description, type = kind or 'inform' })
end

local function reward(r)
    if type(r) ~= 'table' then return '' end
    local bits = {}
    if r.money then bits[#bits + 1] = ('$%d'):format(r.money) end
    if r.rep then bits[#bits + 1] = ('%+d rep'):format(r.rep.delta) end
    return table.concat(bits, ', ')
end

local openMenu

local function showActive(region_id)
    local jobs = lib.callback.await('fh:quests:menu:active', false) or {}
    if #jobs == 0 then
        notify('You have no active job.')
        return openMenu(region_id)
    end
    local options = {}
    for _, j in ipairs(jobs) do
        options[#options + 1] = {
            title = j.title, description = (j.step_text or '') .. ((j.need or 1) > 1 and (' (%d/%d)'):format(j.count or 0, j.need) or ''),
            icon = 'xmark', metadata = { { label = 'Reward', value = reward(j.rewards) } },
            onSelect = function()
                if lib.alertDialog({ header = 'Abandon job?', content = j.title, centered = true, cancel = true }) == 'confirm' then
                    local ok, err = lib.callback.await('fh:quests:menu:abandon', false, j.quest_id)
                    notify(ok and 'Job abandoned.' or (ERR[err] or tostring(err)), ok and 'success' or 'error')
                end
                openMenu(region_id)
            end,
        }
    end
    lib.registerContext({ id = MENU .. '_active', title = 'Active jobs', menu = MENU, options = options })
    lib.showContext(MENU .. '_active')
end

function openMenu(region_id)
    local board, err = lib.callback.await('fh:quests:menu:board', false, region_id)
    if not board then return notify(ERR[err] or ('Board unavailable: ' .. tostring(err)), 'error') end
    local options = {}
    for _, o in ipairs(board.offers or {}) do
        options[#options + 1] = {
            title = o.title, description = o.text, disabled = o.accepted,
            icon = o.accepted and 'check' or 'briefcase',
            metadata = { { label = 'Reward', value = reward(o.rewards) } },
            onSelect = function()
                local ok, why = lib.callback.await('fh:quests:menu:accept', false, o.id)
                notify(ok and ('Accepted: ' .. o.title) or (ERR[why] or tostring(why)), ok and 'success' or 'error')
                openMenu(region_id)
            end,
        }
    end
    if #options == 0 then options[1] = { title = 'No jobs on the board right now', disabled = true } end
    options[#options + 1] = { title = 'My active jobs', icon = 'list', onSelect = function() showActive(region_id) end }
    lib.registerContext({ id = MENU, title = 'Jobs board', options = options })
    lib.showContext(MENU)
end

RegisterCommand('jobs', function() openMenu(DEFAULT_REGION) end, false)

-- Board spots (rsg-target is optional: without it only /jobs works).
CreateThread(function()
    if GetResourceState('rsg-target') ~= 'started' then return end
    for _, b in ipairs(BOARDS) do
        exports['rsg-target']:addSphereZone({
            coords = b.coords, radius = 1.5, debug = false,
            options = { { label = b.label, icon = 'fa-solid fa-clipboard-list', distance = 2.0,
                onSelect = function() openMenu(b.region_id) end } },
        })
        local hash = joaat(b.model)
        if IsModelValid(hash) then -- unverified model: skip the prop when RedM does not know it
            RequestModel(hash)
            local t = GetGameTimer() + 3000
            while not HasModelLoaded(hash) and GetGameTimer() < t do Wait(50) end
            if HasModelLoaded(hash) then
                local prop = CreateObject(hash, b.coords.x, b.coords.y, b.coords.z, false, false, false)
                PlaceObjectOnGroundProperly(prop)
                FreezeEntityPosition(prop, true)
                SetModelAsNoLongerNeeded(hash)
            end
        end
    end
end)

-- The jobs board's bounty target (spawned by the server via fh_core): make it hostile like fh_zones camp peds.
-- Tag format: fh_quests:bounty:<region>:<key>. Natives as in fh_zones/client/main.lua (unverified in-game).
FH.on('fh:spawn:adopted', function(d)
    if type(d) ~= 'table' or d.kind ~= 'ped' or type(d.tag) ~= 'string' or d.tag:sub(1, 17) ~= 'fh_quests:bounty:' then return end
    local ped = d.entity
    if not ped or not DoesEntityExist(ped) then return end
    AddRelationshipGroup('FH_BOUNTY')
    local group = joaat('FH_BOUNTY')
    SetPedRelationshipGroupHash(ped, group)
    SetRelationshipBetweenGroups(5, group, joaat('PLAYER'))
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCombatAttributes(ped, 46, true)
    TaskCombatHatedTargetsAroundPed(ped, 60.0, 0)
end)
