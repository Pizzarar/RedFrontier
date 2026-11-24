-- fh_alife contracts (a-life-02 B3): register the alife_contract job type through fh_quests' public
-- registerJobType export only (no fh_quests edits). Offers and verdicts are pure in shared/contracts_rules.lua
-- (FhAlifeContracts); this file is I/O only — it reads the live sim state (FhAlifeServer from server/main.lua, loaded
-- first) to feed the offers hook, falling back to the KVP main.lua writes if that surface is missing.
--
-- Implemented A-Life — Thanks to S.T.A.L.K.E.R. A-Life by GSC Game World.
local rules = FhAlifeContracts
local alife = FhAlifeRules
local cfg = FhAlifeConfig
local regions = FhRegions

local live = FhAlifeServer
local ctx = (live and live.ctx) or alife.context(cfg, regions, FhZonesConfig.camps)
local KVP_KEY = 'fh_alife_state'

local function log(fmt, ...) print(('[fh_alife] ' .. fmt):format(...)) end

---Sim state from the KVP main.lua writes each tick / camp_clear / squad kill (fallback path only). A board collect must
---never error: any read/decode/deserialize failure falls back to a fresh state (all camps outlaw-held, no squads),
---which is exactly the boot-time state.
local function kvpState()
    local ok, st = pcall(function()
        local raw = GetResourceKvpString(KVP_KEY)
        if not raw or raw == '' then return alife.newState() end
        local t = json.decode(raw)
        if type(t) ~= 'table' then return alife.newState() end
        return alife.deserialize(t, ctx) or alife.newState()
    end)
    return ok and st or alife.newState()
end

---Live in-resource state via FhAlifeServer.getState (same table squads.lua mutates), else the KVP copy. Read-only:
---offers never mutate it.
local function currentState()
    if live and type(live.getState) == 'function' then
        local ok, st = pcall(live.getState)
        if ok and type(st) == 'table' then return st end
    end
    return kvpState()
end

---Register (or re-register) the job type once fh_quests is up. Soft dependency: fh_alife does not list fh_quests
---in dependencies, so fh_alife may start first; the onResourceStart handler below catches fh_quests starting later.
local function register()
    if GetResourceState('fh_quests') ~= 'started' then return end
    local called, res, err = pcall(function()
        return exports.fh_quests:registerJobType(rules.JOB_TYPE, {
            offers = function(region_id) return rules.offers(ctx, currentState(), region_id) end,
            onEvent = function(name, payload, state) return rules.verdict(rules.JOB_TYPE, name, payload, state) end,
            events = { rules.SQUAD_EVENT },
        })
    end)
    if not called then
        log('^1alife_contract not registered (fh_quests export threw): %s^7', tostring(res))
    elseif res ~= true then
        log('^1alife_contract not registered: %s^7', tostring(err))
    end
end

AddEventHandler('onResourceStart', function(res)
    if res == 'fh_quests' or res == GetCurrentResourceName() then register() end
end)

-- Also register on our own boot (fh_quests may already be running before fh_alife starts).
CreateThread(function()
    Wait(0)
    register()
end)
