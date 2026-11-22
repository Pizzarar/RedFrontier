-- Client pcall helpers (included by fh_core and every [fh] resource's client_scripts as '@fh_core/client/safe.lua').
-- FH.safe(fn, ...)  xpcall + report (returns true, results... or just false); FH.thread(fn)  CreateThread(safe); FH.onNet(name, fn)  RegisterNetEvent + safe;
-- FH.on(name, fn)  AddEventHandler + safe. On error, when the server-replicated convar fh_dev is 1
-- (`setr fh_dev 1` in server.cfg; read with GetConvarInt), sends fh:dev:clientError { resource, msg, traceback }.
-- The error is always printed locally and never rethrown (one bad handler must not kill the client script).
-- Cfx infra used: GetConvarInt, GetCurrentResourceName, TriggerServerEvent, CreateThread. Not runtime-tested.
--
-- EXCEPTION: fh_inventory (fork of rsg-inventory) is deliberately NOT wrapped: we keep its diff from upstream minimal
-- (docs/decisions/inventory.md). Its client errors appear only in the RedM client log (like RSG resources).
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
end

function FH.safe(fn, ...)
    return xpcall(fn, handler, ...)
end

function FH.thread(fn)
    CreateThread(function() FH.safe(fn) end)
end

-- FH.wrap(fn) -> function that runs fn under FH.safe and returns fn's results (nothing on failure).
-- Use for callbacks passed to other APIs (lib.points onEnter/onExit/nearby, lib.callback, NUI handlers).
function FH.wrap(fn)
    return function(...) return select(2, FH.safe(fn, ...)) end
end

-- Both return the AddEventHandler / RegisterNetEvent cookie so callers can RemoveEventHandler.
function FH.on(name, fn)
    return AddEventHandler(name, FH.wrap(fn))
end

function FH.onNet(name, fn)
    return RegisterNetEvent(name, FH.wrap(fn))
end

-- fh_clienterr (server/dev_errors.lua) asks fh_core's client to fail on purpose.
if GetCurrentResourceName() == 'fh_core' then
    FH.onNet('fh:dev:throw', function()
        error('fh_clienterr: deliberate client error')
    end)
end
