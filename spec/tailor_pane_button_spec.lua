-- fh_tailor client: saddlebag pane button (ui-saddlebag-pane). Loads the real client/main.lua with stubbed globals.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local case, eq = T.it, T.eq
local base = here .. '../server/resources/[fh]/fh_tailor/'
local Logic = dofile(base .. 'shared/tailor_logic.lua')
local Preview = dofile(base .. 'client/preview.lua')

local function rig(invUp)
    local r = { regs = {}, sent = {}, handlers = {}, invUp = invUp ~= false }
    local fh_inventory = { registerPaneButton = function(_, def)
        if not r.invUp then error('resource not started') end
        r.regs[#r.regs + 1] = def
        return true
    end }
    local env = setmetatable({
        FhTailorConfig = { FittedOutfits = false, catalog = {}, shops = {} }, FhTailorLogic = Logic, FhTailorPreview = Preview,
        FH = {
            on = function(n, f) r.handlers[n] = f end, onNet = function() end, thread = function() end, wrap = function(f) return f end,
        },
        lib = { callback = { await = function() return nil end }, points = { new = function() return {} end },
            showTextUI = function() end, hideTextUI = function() end },
        exports = setmetatable({ fh_inventory = fh_inventory }, { __call = function() end }),
        PlayerPedId = function() return 1 end, DoesEntityExist = function() return true end, IsEntityDead = function() return false end,
        SetPedOutfitPreset = function() end, Citizen = { InvokeNative = function() end }, joaat = function() return 1 end,
        AddEventHandler = function() end, TriggerEvent = function() end,
        TriggerServerEvent = function(n, ...) r.sent[#r.sent + 1] = n end,
        GetResourceState = function() return 'stopped' end, GetCurrentResourceName = function() return 'fh_tailor' end,
        vector3 = function() end, Wait = function() end, IsControlJustReleased = function() return false end,
    }, { __index = _G })
    env._G = env
    assert(loadfile(base .. 'client/main.lua', 't', env))()
    return r
end

case('registers a saddlebag Wardrobe button on client start', function()
    local r = rig(true)
    eq(1, #r.regs)
    eq('fh_tailor_wardrobe', r.regs[1].id); eq('Wardrobe', r.regs[1].label); eq('saddlebag', r.regs[1].pane)
end)
case('fh_inventory not up at load: no error, registers when it starts', function()
    local r = rig(false)
    eq(0, #r.regs)
    r.invUp = true
    r.handlers['onClientResourceStart']('fh_inventory')
    eq(1, #r.regs)
end)
case('re-registers after fh_inventory restarts; other resources ignored', function()
    local r = rig(true)
    r.handlers['onClientResourceStart']('fh_ui')
    eq(1, #r.regs)
    r.handlers['onClientResourceStart']('fh_inventory')
    eq(2, #r.regs); eq('fh_tailor_wardrobe', r.regs[2].id)
end)
case('click on our id asks the server to open the wardrobe', function()
    local r = rig(true)
    r.handlers['fh_inventory:paneButton']({ id = 'fh_tailor_wardrobe', pane = 'saddlebag' })
    T.same({ 'fh:tailor:open_wardrobe' }, r.sent)
end)
case('other ids and malformed payloads are ignored', function()
    local r = rig(true)
    r.handlers['fh_inventory:paneButton']({ id = 'someone_else', pane = 'saddlebag' })
    r.handlers['fh_inventory:paneButton']({})
    r.handlers['fh_inventory:paneButton'](nil)
    r.handlers['fh_inventory:paneButton']('fh_tailor_wardrobe')
    eq(0, #r.sent)
end)

T.finish()
