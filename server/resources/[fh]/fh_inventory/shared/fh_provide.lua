-- FH: legacy export name. Loaded first on server and client.
-- `provide 'rsg-inventory'` (fxmanifest) covers GetResourceState and dependency checks, but exports
-- resolve only by the event name `__cfx_export_<resource>_<fn>`. So every exports(name, fn) in this
-- resource also registers the rsg-inventory event name, the same way rsg-core does for
-- 'rsg-multijob' (rsg-core server/multijob/server.lua) and oxmysql does for 'mysql-async'.
local LEGACY = 'rsg-inventory'

if GetCurrentResourceName() ~= LEGACY then
    local real = exports
    exports = setmetatable({}, {
        __index = function(_, k) return real[k] end,
        __newindex = function(_, k, v) real[k] = v end,
        __call = function(_, name, fn)
            real(name, fn)
            AddEventHandler(('__cfx_export_%s_%s'):format(LEGACY, name), function(setCB) setCB(fn) end)
        end,
    })
end
