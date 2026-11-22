local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
-- Smoke spec: loads fh_core's shared modules and fh_inventory's server scripts into a stubbed FXServer world
-- (natives, MySQL, rsg-core are no-op stubs) and drives the fh veto paths end to end. Not a substitute for a
-- live boot: exports here are captured in-process, not msgpack'd between resources.
EXPORTED = {}
local R = here .. '../server/resources/[fh]/'
local function stub() return setmetatable({}, { __index = function(t, k) return stub() end, __call = function() return nil end }) end
local invoking = nil
local players = {}
local shared = {
  bread = { name = 'bread', label = 'Bread', weight = 100, unique = false, type = 'item' },
  crate = { name = 'crate', label = 'Crate', weight = 9000, unique = true, type = 'item', size_class = 'cargo' },
  saddle = { name = 'saddle', label = 'Saddle', weight = 5000, unique = true, type = 'item', size_class = 'bulky' },
}
local Core = { Shared = { Items = shared }, Functions = stub(), Commands = stub() }
Core.Functions.GetPlayer = function(src) return players[src] end
Core.Functions.GetRSGPlayers = function() return {} end
Core.Functions.AddPlayerMethod = function() end
local exportsT = setmetatable({}, { __index = function(_, res) return setmetatable({}, { __index = function(_, fn)
  return function() if fn == 'GetCoreObject' then return Core end end end }) end,
  __call = function(_, name, fn) EXPORTED[name] = fn end })
local env = setmetatable({
  exports = exportsT, GetCurrentResourceName = function() return 'fh_inventory' end,
  GetInvokingResource = function() return invoking end, locale = function(k) return k end,
  json = { decode = function() return {} end, encode = function() return '[]' end },
  vector3 = function(x, y, z) return { x = x, y = y, z = z } end,
  GetGameTimer = function() return 0 end, GetPlayerName = function() return 'p' end,
  TriggerClientEvent = function() end, TriggerEvent = function() end,
  RegisterNetEvent = function() end, AddEventHandler = function() end, CreateThread = function() end,
  GetResourceState = function() return 'started' end,
}, { __index = function(_, k) local v = _G[k]; if v ~= nil then return v end return stub() end })
env._G = env
local function run(p) local fh = assert(io.open(p, 'rb')); local src = fh:read('a'):gsub('`[%w_]+`', '0'); fh:close()
  local f = assert(load(src, '@' .. p, 't', env)); f() end
for _, p in ipairs({ R..'fh_core/config.lua', R..'fh_core/shared/items.lua', R..'fh_core/shared/containers.lua',
  R..'fh_core/shared/rules.lua', R..'fh_inventory/shared/config.lua', R..'fh_inventory/server/main.lua',
  R..'fh_inventory/server/shops.lua', R..'fh_inventory/server/compat.lua', R..'fh_inventory/server/fh_api.lua' }) do run(p) end
local I = env.InvCore
local function mkPlayer(src, items)
  local P = { PlayerData = { source = src, items = items, slots = 25, weight = 35000, citizenid = 'C'..src, charinfo = {} },
    Functions = {} }
  P.Functions.SetPlayerData = function(k, v) P.PlayerData[k] = v end
  players[src] = P
  return P
end
local function it(name, amount, slot) local s = shared[name]
  return { name = name, amount = amount, slot = slot, info = {}, weight = s.weight, unique = s.unique, label = s.label, type = 'item' } end
local function check(name, cond) T.it(name, function() assert(cond, name) end) end

T.describe('fh_inventory veto paths (stubbed server)', function()
local P = mkPlayer(1, { [1] = it('bread', 2, 1) })
check('HotbarSlots comes from FhConfig equipped', env.Config.HotbarSlots == env.FhConfig.Containers.equipped.slots)
check('crate resolves cargo via sharedLookup', env.FhItems.resolve('crate').size_class == 'cargo')
check('AddItem bread ok', I.API.AddItem(1, 'bread', 3) == true)
check('AddItem crate refused', not I.API.AddItem(1, 'crate', 1))
check('AddItem saddle refused (bulky)', not I.API.AddItem(1, 'saddle', 1))
check('CanCarry crate false', not I.API.CanCarry(1, 'crate', 1))
-- fh chest via fh_api as fh_core
invoking = 'fh_core'
check('register chest', I.Fh.RegisterContainer({ type = 'chest', id = 'fh:chest:1' }, { coords = { x = 0, y = 0, z = 0 }, slots = 10, maxWeight = 100000 }))
local chest = I.Inventories['fh:chest:1']
check('chest fhType', chest and chest.fhType == 'chest')
chest.items[1] = it('crate', 1, 1)
local ok, why = I.Fh.Move({ type = 'chest', id = 'fh:chest:1' }, { type = 'backpack', id = 1 }, 1, 10, 1)
check('crate chest->backpack refused (' .. tostring(why) .. ')', ok == false and why == 'fh_size_class')
check('crate still in chest', chest.items[1] and chest.items[1].name == 'crate')
ok, why = I.Fh.Move({ type = 'backpack', id = 1 }, { type = 'chest', id = 'fh:chest:1' }, 1, 2, 1)
check('bread slot1 is equipped, so backpack ref refused (' .. tostring(why) .. ')', ok == false and why == 'fh_bad_slot')
ok, why = I.Fh.Move({ type = 'equipped', id = 1 }, { type = 'chest', id = 'fh:chest:1' }, 1, 2, 1)
check('bread equipped->chest ok (' .. tostring(why) .. ')', ok == true and chest.items[2] and chest.items[2].amount == 1)
check('view type mismatch refused', I.Fh.View({ type = 'wagon', id = 'fh:chest:1' }) == nil)
check('unknown id refused, not created', I.Fh.View({ type = 'chest', id = 'nope' }) == nil and I.Inventories['nope'] == nil)
local v = I.Fh.View({ type = 'backpack', id = 1 })
check('backpack view range', v and v.slotRange[1] == 6)
local okT, moved, left = I.Fh.TransferAll({ type = 'chest', id = 'fh:chest:1' }, { type = 'backpack', id = 1 })
check('transferAll: bread moved, crate leftover', okT and #moved == 1 and #left == 1 and left[1].name == 'crate')
invoking = 'some_script'
check('non-core caller refused', select(2, I.Fh.Move({ type = 'chest', id = 'fh:chest:1' }, { type = 'backpack', id = 1 }, 1, 10)) == 'not_fh_core')
-- SetInventory
-- non-fh stash fails closed
I.API.RegisterStash('plain_stash', {})
check('AddItem into non-fh stash refused', not I.API.AddItem('plain_stash', 'bread', 1))
local SI = EXPORTED.SetInventory
local before = P.PlayerData.items
local okA, whyA = SI(1, { [7] = it('crate', 1, 7) })
check('SetInventory with crate in backpack refused (' .. tostring(whyA) .. ')', okA == false and P.PlayerData.items == before)
okA, whyA = SI(1, { [1] = it('bread', 99, 1) })
check('SetInventory equipped over 8kg refused (' .. tostring(whyA) .. ')', okA == false)
okA = SI(1, { [1] = it('bread', 2, 1), [8] = it('bread', 5, 8) })
check('SetInventory valid layout ok', okA == true and P.PlayerData.items[8].amount == 5)
check('SetItemData amount refused', not EXPORTED.SetItemData(1, 'bread', 'amount', 50))
end)

T.finish()
