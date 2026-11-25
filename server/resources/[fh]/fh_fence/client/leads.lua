-- fh_fence client: treasure leads (progression-02 G2). For each lead the player carries: the hint as a notify (once
-- per lead, and again whenever the item is used) and an AREA blip (the server offsets its centre, so it never marks
-- the spot). Inside an area, E asks the server to dig; the server checks the real distance, the lead and the room,
-- and pays out. No new fh_ui screen. Not runtime-tested.
-- Natives (unverified in game, fh_core/docs/natives.md has no radius-blip entry yet):
--   BLIP_ADD_FOR_RADIUS 0x45F13B7E0A15C880 (STYLE hash, x, y, z, radius) -> blip   style -1282792512 = area style
--   used by common RedM scripts; _SET_BLIP_NAME 0x9CB1A1623062F402 (blip, name) as in fh_ui/client/where.lua.
local INPUT_CONTEXT = 0xCEFD9220 -- E (unverified), same as client/main.lua
local BLIP_ADD_FOR_RADIUS = 0x45F13B7E0A15C880
local BLIP_STYLE_AREA = -1282792512
local _SET_BLIP_NAME = 0x9CB1A1623062F402

local logic = FhFenceLeadsLogic
local shown = {}   -- key -> { blip, point }
local hinted = {}  -- key -> true once the hint was shown this session
local digging = false

local function notify(msg, kind) lib.notify({ title = 'Treasure lead', description = msg, type = kind or 'inform' }) end

local function dig()
    if digging then return end
    digging = true
    FH.safe(function()
        local ok, res = lib.callback.await('fh:fence:dig', false)
        notify(logic.notice(ok, res), ok and 'success' or 'error')
    end)
    digging = false
end

local function drop(key)
    local s = shown[key]
    if not s then return end
    if s.blip then RemoveBlip(s.blip) end
    if s.point then s.point:remove() end
    shown[key] = nil
    lib.hideTextUI()
end

local function add(l)
    local a = l.area
    local blip = Citizen.InvokeNative(BLIP_ADD_FOR_RADIUS, BLIP_STYLE_AREA, a.x + 0.0, a.y + 0.0, a.z + 0.0,
        l.radius + 0.0)
    if blip and blip ~= 0 then Citizen.InvokeNative(_SET_BLIP_NAME, blip, 'Treasure lead') end
    local point = lib.points.new({
        coords = vec3(a.x, a.y, a.z), distance = l.radius,
        onEnter = FH.wrap(function() lib.showTextUI('[E] Dig for the cache') end),
        onExit = FH.wrap(function() lib.hideTextUI() end),
        nearby = FH.wrap(function()
            if IsControlJustReleased(0, INPUT_CONTEXT) then dig() end
        end),
    })
    shown[l.key] = { blip = blip, point = point }
end

local function hint(l)
    notify(l.hint ~= '' and l.hint or 'Somewhere inside the marked area.')
    hinted[l.key] = true
end

local function refresh()
    local list = lib.callback.await('fh:fence:leads', false) or {}
    local keep = {}
    for _, l in ipairs(list) do
        keep[l.key] = true
        if not shown[l.key] then add(l) end
        if not hinted[l.key] then hint(l) end
    end
    for key in pairs(shown) do
        if not keep[key] then drop(key) end
    end
end

FH.thread(function()
    while true do
        FH.safe(refresh) -- one failed poll must not end the loop
        Wait(15000)
    end
end)

-- The server sends this when the lead item is used: show its hint again and make sure its area is on the map.
FH.onNet('fh:fence:lead_used', function(l)
    if type(l) ~= 'table' or type(l.area) ~= 'table' or type(l.key) ~= 'string' then return end
    if not shown[l.key] then add(l) end
    hint(l)
end)

FH.on('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for key in pairs(shown) do drop(key) end
end)
