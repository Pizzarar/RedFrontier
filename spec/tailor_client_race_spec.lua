-- fh_tailor/client/main.lua revertLook race (T4b review L1): a previewLook / apply that lands while revertLook waits on the
-- server must not be clobbered. Loads the real client file with stubbed globals (no natives).
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local case, eq = T.it, T.eq
local base = here .. '../server/resources/[fh]/fh_tailor/'
local Logic = dofile(base .. 'shared/tailor_logic.lua')
local Preview = dofile(base .. 'client/preview.lua')

local function rig(flag)
    local r = { presets = {}, exp = {}, onAwait = nil, worn = { outfit = 'saved', items = {} } }
    local cfg = { FittedOutfits = flag, catalog = {
        saved = { kind = 'outfit', preset = 1 }, other = { kind = 'outfit', preset = 2 }, pv = { kind = 'outfit', preset = 3 } } }
    local netHandlers = {}
    local env = setmetatable({
        FhTailorConfig = cfg, FhTailorLogic = Logic, FhTailorPreview = Preview,
        FH = { on = function() end, onNet = function(n, f) netHandlers[n] = f end, thread = function() end, wrap = function(f) return f end },
        lib = { callback = { await = function()
            if r.onAwait then r.onAwait() end
            return r.worn
        end }, points = { new = function() return {} end }, showTextUI = function() end, hideTextUI = function() end },
        exports = setmetatable({}, { __call = function(_, name, fn) r.exp[name] = fn end }),
        PlayerPedId = function() return 1 end, DoesEntityExist = function() return true end, IsEntityDead = function() return false end,
        SetPedOutfitPreset = function(_, preset) r.presets[#r.presets + 1] = preset end,
        Citizen = { InvokeNative = function() end }, joaat = function() return 1 end,
        AddEventHandler = function() end, TriggerEvent = function() end, TriggerServerEvent = function() end,
        GetResourceState = function() return 'stopped' end, GetCurrentResourceName = function() return 'fh_tailor' end,
        vector3 = function() end, Wait = function() end, IsControlJustReleased = function() return false end,
    }, { __index = _G })
    env._G = env
    local chunk = assert(loadfile(base .. 'client/main.lua', 't', env))
    chunk()
    r.net = netHandlers
    return r
end

case('revertLook: a previewLook that lands during the server wait is not clobbered', function()
    local r = rig(true)
    eq(true, r.exp.previewLook({ outfit = 'pv', items = {} })); T.same({ 3 }, r.presets)
    r.onAwait = function() eq(true, r.exp.previewLook({ outfit = 'other', items = {} })) end
    eq(false, r.exp.revertLook())
    T.same({ 3, 2 }, r.presets) -- the saved look (1) was never re-applied over the newer preview
end)
case('revertLook: a repeated previewLook during the wait wins too', function()
    local r = rig(true)
    r.exp.previewLook({ outfit = 'pv', items = {} })
    r.onAwait = function() r.exp.previewLook({ outfit = 'pv', items = {} }) end
    eq(false, r.exp.revertLook())
    T.same({ 3, 3 }, r.presets)
end)
case('revertLook: no race -> saved look re-applied', function()
    local r = rig(true)
    r.exp.previewLook({ outfit = 'pv', items = {} })
    eq(true, r.exp.revertLook()); T.same({ 3, 1 }, r.presets)
end)

T.finish()
