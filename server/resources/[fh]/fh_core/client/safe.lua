-- Client pcall helpers (included by fh_core and every [fh] resource's client_scripts as '@fh_core/client/safe.lua').
-- FH.safe(fn, ...)  xpcall + report; FH.thread(fn)  CreateThread(safe); FH.onNet(name, fn)  RegisterNetEvent + safe;
-- FH.on(name, fn)  AddEventHandler + safe. On error, when the server-replicated convar fh_dev is 1
-- (`setr fh_dev 1` in server.cfg; read with GetConvarInt), sends fh:dev:clientError { resource, msg, traceback }.
-- The error is always printed locally and never rethrown (one bad handler must not kill the client script).
-- Cfx infra used: GetConvarInt, GetCurrentResourceName, TriggerServerEvent, CreateThread. Not runtime-tested.
FH = FH or {}

-- xpcall message handler: runs at the error site, so the traceback includes the failing frame.
local function handler(err)
    local msg = tostring(err)
    local tb = debug.traceback(msg, 2)
    local res = GetCurrentResourceName()
    print(('^1[%s] client error: %s^7'):format(res, msg))
    if GetConvarInt('fh_dev', 0) == 1 then
        TriggerServerEvent('fh:dev:clientError', { resource = res, msg = msg, traceback = tb })
    end
    return err
end

function FH.safe(fn, ...)
    return xpcall(fn, handler, ...)
end

function FH.thread(fn)
    CreateThread(function() FH.safe(fn) end)
end

function FH.on(name, fn)
    AddEventHandler(name, function(...) return select(2, FH.safe(fn, ...)) end)
end

function FH.onNet(name, fn)
    RegisterNetEvent(name, function(...) return select(2, FH.safe(fn, ...)) end)
end

-- fh_clienterr (server/dev_errors.lua) asks fh_core's client to fail on purpose.
if GetCurrentResourceName() == 'fh_core' then
    FH.onNet('fh:dev:throw', function()
        error('fh_clienterr: deliberate client error')
    end)
end
