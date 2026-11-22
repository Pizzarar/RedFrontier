-- FH.safe / FH.wrap / FH.on / FH.onNet with stubbed Cfx natives (fh_core/client/safe.lua).
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local case = T.it

local sent = {}
GetConvarInt = function() return 1 end
GetCurrentResourceName = function() return 'fh_test' end
TriggerServerEvent = function(name, p) sent[#sent + 1] = { name, p } end
CreateThread = function(f) f() end
AddEventHandler = function(_, f) return { cookie = 'h', f = f } end
RegisterNetEvent = function(_, f) return { cookie = 'n', f = f } end
local realPrint = print
print = function() end
dofile(here .. '../server/resources/[fh]/fh_core/client/safe.lua')
print = realPrint

case('safe: success passes results through', function()
    local ok, a, b = FH.safe(function(x) return x, 2 end, 1)
    assert(ok == true and a == 1 and b == 2)
end)
case('safe: failure returns false and nothing else, and reports', function()
    sent = {}
    local ok, extra = FH.safe(function() error('boom') end)
    assert(ok == false and extra == nil)
    assert(sent[1][1] == 'fh:dev:clientError' and sent[1][2].resource == 'fh_test')
    assert(sent[1][2].msg:find('boom'))
end)
case('wrap/on/onNet: nothing on failure, registrar cookie returned', function()
    assert(FH.wrap(function() error('x') end)() == nil)
    assert(FH.wrap(function(a) return a end)(7) == 7)
    local h = FH.on('e', function() end)
    local n = FH.onNet('e', function() end)
    assert(h.cookie == 'h' and n.cookie == 'n')
end)
T.finish()
