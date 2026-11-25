-- fh_ui client: shared cached fetcher for enabled-region trappers (`fh:ui:trappers` callback -> fh_hunting getTrappers).
-- Used by client/blips.lua and client/where.lua. Clears its cache and notifies listeners when fh_hunting stops so stale
-- per-region trappers fall back to FhHuntingConfig.Trapper, and refetches when fh_hunting starts again.
local M = {}

local cache = nil
local huntingDown = false
local listeners = {}
local startGen = 0
local START_TRIES, START_RETRY_MS = 3, 2000

local function notify(trappers)
    for _, fn in ipairs(listeners) do
        fn(trappers)
    end
end

---Fetch enabled-region trappers via `fh:ui:trappers`. Returns the cached table while fh_hunting is up; returns nil when
---fh_hunting is stopped or the callback is unavailable/fails (places.lua falls back to FhHuntingConfig.Trapper).
function M.fetch(force)
    if huntingDown then return nil end
    if not force and cache ~= nil then return cache end
    if not (lib and lib.callback) then return nil end
    local ok, list = pcall(function() return lib.callback.await('fh:ui:trappers', false) end)
    if ok and type(list) == 'table' and not huntingDown then
        cache = list
        return cache
    end
    return nil
end

---Clear the cached trapper list without querying the server.
function M.clear()
    cache = nil
end

---Register a listener fn(trappers) called with nil when fh_hunting stops and with the refetched list when it starts.
function M.onChange(fn)
    listeners[#listeners + 1] = fn
end

if FH and FH.on then
    FH.on('onResourceStart', function(res)
        if res ~= 'fh_hunting' then return end
        huntingDown = false
        cache = nil
        startGen = startGen + 1
        local gen = startGen
        FH.thread(function()
            -- fh_hunting's server side may not be ready yet: retry a few times, stopping on success or a newer start/stop.
            local list
            for attempt = 1, START_TRIES do
                list = M.fetch(true)
                if list ~= nil or gen ~= startGen or huntingDown then break end
                if attempt < START_TRIES then Wait(START_RETRY_MS) end
                if gen ~= startGen or huntingDown then return end
            end
            if gen == startGen and not huntingDown then notify(list) end
        end)
    end)

    FH.on('onResourceStop', function(res)
        if res == 'fh_hunting' then
            huntingDown = true
            startGen = startGen + 1 -- cancels any pending start retry
            cache = nil
            notify(nil)
        elseif GetCurrentResourceName and res == GetCurrentResourceName() then
            cache = nil
        end
    end)
end

FhUiTrappers = M
if not GetCurrentResourceName then return M end
