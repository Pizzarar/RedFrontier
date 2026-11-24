-- Edge cases for fh_core server/inventory.lua (core-07 S1): carried refs with an offline/dropped src, the bulky
-- backpack veto, setItemInfo expectName mismatch / swap race, and fh_inventory failure shapes. Loads the real
-- server/inventory.lua against a fake fh_inventory (exports captured in-process) and a fake rsg-core.
-- The fake mirrors fh_inventory's documented contract (fh_api.lua FhSetItemInfo / FhAddItem); it is not the real fork.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local SRC = here .. '../server/resources/[fh]/fh_core/server/inventory.lua'

local FhItems, FhContainers, FhRules, FhConfig = require('items'), require('containers'), require('rules'), require('config')

-- world state ---------------------------------------------------------------------------------------------------
local online = {}            -- src -> citizenid (a loaded character)
local peds = {}              -- src -> ped handle (0 = player gone)
local invState = 'started'
local exported, calls, events, prints = {}, {}, {}, {}
local slots = {}             -- ref key -> { [slot] = item }; fake containers behind FhSetItemInfo / FhView
local throwNext = false

local function key(ref) return ref.type .. '|' .. tostring(ref.id) end

local invApi = {}
local function rec(name, ...) calls[#calls + 1] = { name = name, args = table.pack(...) } end
function invApi:FhAddItem(ref, name, amount, info, reason)
    rec('FhAddItem', ref, name, amount, info, reason)
    if throwNext then throwNext = false; error('boom') end
    -- same veto fh_inventory re-runs: container rules decide, not fh_core
    local sh = { weight = 1000, size_class = name == 'bulky_thing' and 'bulky' or 'pocket' }
    local ok, why = FhRules.canFit({ type = ref.type, items = {}, slots = 10, maxWeight = 50000 },
        { name = name, weight = sh.weight, size_class = sh.size_class, info = {} }, amount)
    if not ok then return false, why end
    return true
end
function invApi:FhRemoveItem(ref, name, amount, reason) rec('FhRemoveItem', ref, name, amount, reason); return false, 'fh_not_enough' end
function invApi:FhSetItemInfo(ref, slot, info, expectName)
    rec('FhSetItemInfo', ref, slot, info, expectName)
    local c = slots[key(ref)]
    if not c then return false, 'fh_unknown_container' end
    local v = invApi.FhView(self, ref) -- as the real InView: the slot must lie in ref's own section
    local first, last = 1, v.slots
    if v.slotRange then first, last = v.slotRange[1], v.slotRange[2] end
    if type(slot) ~= 'number' or slot < first or slot > last then return false, 'fh_bad_slot' end
    local item = c[slot]
    if not item then return false, 'fh_empty_slot' end
    if expectName ~= nil and item.name ~= expectName:lower() then return false, 'fh_wrong_item' end
    item.info = info
    return true
end
function invApi:FhView(ref)
    local c = slots[key(ref)]
    if not c then return nil, 'fh_unknown_container' end
    local eq, bp = FhRules.playerViews(c, 50000, 20)
    if ref.type == 'backpack' then return bp elseif ref.type == 'equipped' then return eq end
    return { type = ref.type, items = c, slots = 10, maxWeight = 50000 }
end
function invApi:FhSnapshot(ref) return slots[key(ref)] end
function invApi:GetItemCount() return 0 end

local rsg = { Shared = { Items = { bread = { weight = 100 }, bulky_thing = { weight = 1000, size_class = 'bulky' } } },
    Functions = { GetPlayer = function(src) return online[src] and { PlayerData = { citizenid = online[src] } } or nil end } }

local exportsT = setmetatable({}, {
    __index = function(_, res)
        if res == 'fh_inventory' then return invApi end
        if res == 'rsg-core' then return { GetCoreObject = function() return rsg end } end
        error('unexpected export ' .. tostring(res))
    end,
    __call = function(_, name, fn) exported[name] = fn end,
})
local env = setmetatable({
    exports = exportsT, FhItems = FhItems, FhContainers = FhContainers, FhRules = FhRules, FhConfig = FhConfig,
    GetResourceState = function(r) if r == 'fh_inventory' then return invState end return 'started' end,
    GetPlayerPed = function(src) return peds[src] or 0 end,
    GetEntityCoords = function() return { x = 0, y = 0, z = 0 } end,
    GetInvokingResource = function() return 'spec' end, GetCurrentResourceName = function() return 'fh_core' end,
    AddEventHandler = function() end, TriggerEvent = function(n, p) events[#events + 1] = { n, p } end,
    print = function(...) prints[#prints + 1] = table.concat({ ... }, ' ') end,
}, { __index = _G })
env._G = env
local fh = assert(io.open(SRC, 'rb')); local code = fh:read('a'); fh:close()
assert(load(code, '@' .. SRC, 't', env))()

local addItem, removeItem, setItemInfo, canFit = exported.addItem, exported.removeItem, exported.setItemInfo, exported.canFit
local function joined(src) online[src] = 'CID' .. src; peds[src] = 100 + src end
local function reset() calls, events, prints = {}, {}, {}; invState = 'started'; throwNext = false end

T.describe('carried refs with an offline / dropped src', function()
    T.it('never loaded a character: fh_player_offline on add/remove/setItemInfo, fh_inventory not called', function()
        reset()
        for _, t in ipairs({ 'backpack', 'equipped' }) do
            local ref = { type = t, id = 9 }
            T.same({ false, 'fh_player_offline' }, { addItem(ref, 'bread', 1) })
            T.same({ false, 'fh_player_offline' }, { removeItem(ref, 'bread', 1) })
            T.same({ false, 'fh_player_offline' }, { setItemInfo(ref, 1, {}) })
        end
        T.eq(0, #calls)
    end)
    T.it('ped is gone (dropped mid-flight) even though rsg-core still has the Player: offline', function()
        reset(); joined(3); peds[3] = 0
        T.same({ false, 'fh_player_offline' }, { addItem({ type = 'backpack', id = 3 }, 'bread', 1) })
        T.eq(0, #calls)
    end)
    T.it('ped exists but the character is unloaded (rsg-core has no Player): offline', function()
        reset(); joined(4); online[4] = nil
        T.same({ false, 'fh_player_offline' }, { removeItem({ type = 'equipped', id = 4 }, 'bread', 1) })
        T.eq(0, #calls)
    end)
    T.it('src is not a number (string / missing / table): fh_bad_ref (never reaches the player lookup)', function()
        reset()
        T.same({ false, 'fh_bad_ref' }, { addItem({ type = 'backpack', id = '3' }, 'bread', 1) })
        T.same({ false, 'fh_bad_ref' }, { addItem({ type = 'backpack' }, 'bread', 1) })
        T.same({ false, 'fh_bad_ref' }, { setItemInfo({ type = 'equipped', id = {} }, 1, {}) })
        T.eq(0, #calls)
    end)
    T.it('fractional src (1.5) passes the type check but has no ped: fh_player_offline, fh_inventory not called', function()
        reset()
        T.same({ false, 'fh_player_offline' }, { addItem({ type = 'backpack', id = 1.5 }, 'bread', 1) })
        T.eq(0, #calls)
    end)
    T.it('online player: the same call reaches fh_inventory with the carried ref and a caller tag', function()
        reset(); joined(5)
        T.eq(true, addItem({ type = 'backpack', id = 5 }, 'bread', 2))
        T.eq('FhAddItem', calls[1].name); T.eq(5, calls[1].args[1].id)
        assert(calls[1].args[5]:find('fh_core.addItem', 1, true))
    end)
    T.it('world ref that was never registered is fh_unknown_container, not offline', function()
        reset()
        T.same({ false, 'fh_unknown_container' }, { addItem({ type = 'chest', id = 'fh:chest:x:1' }, 'bread', 1) })
        T.same({ false, 'fh_unknown_container' }, { setItemInfo({ type = 'chest', id = 'fh:chest:x:1' }, 1, {}) })
    end)
end)

T.describe('bulky item -> backpack veto', function()
    T.it('addItem(backpack, bulky) returns the container veto reason and adds nothing', function()
        reset(); joined(6)
        local ok, why = addItem({ type = 'backpack', id = 6 }, 'bulky_thing', 1)
        T.eq(false, ok); T.eq('fh_size_class', why)
    end)
    T.it('canFit(backpack|equipped, bulky) is refused with fh_size_class; a pocket item fits', function()
        reset(); joined(6); slots['backpack|6'] = {}; slots['equipped|6'] = {}
        for _, t in ipairs({ 'backpack', 'equipped' }) do
            T.same({ false, 'fh_size_class' }, { canFit({ type = t, id = 6 }, 'bulky_thing', 1) })
            T.eq(true, (canFit({ type = t, id = 6 }, 'bread', 1)))
        end
    end)
    T.it('canFit on a carried ref whose view is gone surfaces the reason, no throw', function()
        reset()
        local ok, why = canFit({ type = 'backpack', id = 77 }, 'bread', 1)
        T.eq(false, ok); T.eq('fh_unknown_container', why)
    end)
end)

T.describe('setItemInfo expectName / swap race', function()
    T.it('expectName matches: info replaced', function()
        reset(); joined(7); slots['backpack|7'] = { [8] = { name = 'bread', amount = 1, info = {} } }
        T.eq(true, setItemInfo({ type = 'backpack', id = 7 }, 8, { q = 1 }, 'bread'))
        T.eq(1, slots['backpack|7'][8].info.q)
    end)
    T.it('item swapped between read and write: fh_wrong_item and the new item keeps its info', function()
        reset(); joined(7); slots['backpack|7'] = { [8] = { name = 'bread', amount = 1, info = {} } }
        local read = slots['backpack|7'][8].name -- caller reads 'bread'...
        slots['backpack|7'][8] = { name = 'water', amount = 1, info = { keep = true } } -- ...slot swapped before the write
        T.same({ false, 'fh_wrong_item' }, { setItemInfo({ type = 'backpack', id = 7 }, 8, { q = 9 }, read) })
        T.same({ keep = true }, slots['backpack|7'][8].info)
    end)
    T.it('item removed between read and write: fh_empty_slot', function()
        reset(); joined(7); slots['backpack|7'] = {}
        T.same({ false, 'fh_empty_slot' }, { setItemInfo({ type = 'backpack', id = 7 }, 8, {}, 'bread') })
    end)
    T.it('expectName is case-insensitive on the item side, and invalid expectName never reaches fh_inventory', function()
        reset(); joined(7); slots['backpack|7'] = { [8] = { name = 'bread', info = {} } }
        T.eq(true, setItemInfo({ type = 'backpack', id = 7 }, 8, {}, 'BREAD'))
        reset()
        T.same({ false, 'fh_bad_item_name' }, { setItemInfo({ type = 'backpack', id = 7 }, 8, {}, '') })
        T.same({ false, 'fh_bad_item_name' }, { setItemInfo({ type = 'backpack', id = 7 }, 8, {}, 5) })
        T.eq(0, #calls)
    end)
    T.it('bad slot / bad info are refused locally (2.5, NaN, string, nil, non-table info)', function()
        reset(); joined(7)
        local ref = { type = 'backpack', id = 7 }
        T.eq('fh_bad_slot', select(2, setItemInfo(ref, 2.5, {})))
        T.eq('fh_bad_slot', select(2, setItemInfo(ref, 0 / 0, {})))
        T.eq('fh_bad_slot', select(2, setItemInfo(ref, '1', {})))
        T.eq('fh_bad_slot', select(2, setItemInfo(ref, nil, {})))
        T.eq('fh_bad_info', select(2, setItemInfo(ref, 1, 'x')))
        T.eq(0, #calls)
    end)
    T.it('integer-valued float slot (8.0) is accepted and sent as an integer', function()
        reset(); joined(7); slots['backpack|7'] = { [8] = { name = 'bread', info = {} } }
        T.eq(true, setItemInfo({ type = 'backpack', id = 7 }, 8.0, {}, 'bread'))
        T.eq('integer', math.type(calls[1].args[2]))
    end)
end)

T.describe('fh_inventory failure shapes', function()
    T.it('fh_inventory stopped: fh_inventory_down for add/remove/setItemInfo, nothing thrown', function()
        reset(); joined(8); invState = 'stopped'
        T.same({ false, 'fh_inventory_down' }, { addItem({ type = 'backpack', id = 8 }, 'bread', 1) })
        T.same({ false, 'fh_inventory_down' }, { removeItem({ type = 'backpack', id = 8 }, 'bread', 1) })
        T.same({ false, 'fh_inventory_down' }, { setItemInfo({ type = 'backpack', id = 8 }, 1, {}) })
    end)
    T.it('fh_inventory throws: fh_inventory_error and a logged line, caller survives', function()
        reset(); joined(8); throwNext = true
        T.same({ false, 'fh_inventory_error' }, { addItem({ type = 'backpack', id = 8 }, 'bread', 1) })
        assert(#prints == 1 and prints[1]:find('FhAddItem', 1, true), prints[1])
    end)
    T.it('amount edge cases: 0, -1, 2.5, NaN, "2" refused; nil -> 1; 2.0 -> 2', function()
        reset(); joined(8)
        local ref = { type = 'backpack', id = 8 }
        for _, a in ipairs({ 0, -1, 2.5, 0 / 0, math.huge, '2' }) do
            T.eq('fh_bad_amount', select(2, addItem(ref, 'bread', a)), tostring(a))
        end
        T.eq(0, #calls)
        T.eq(true, addItem(ref, 'bread')); T.eq(1, calls[1].args[3])
        T.eq(true, addItem(ref, 'bread', 2.0)); T.eq(2, calls[2].args[3])
    end)
end)

T.finish()
