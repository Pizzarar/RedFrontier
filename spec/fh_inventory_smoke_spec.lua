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
-- vector3 with the two operations the server scripts use: a - b and #v
local Vec = {}
Vec.__index = Vec
local function vec(x, y, z) return setmetatable({ x = x, y = y, z = z }, Vec) end
Vec.__sub = function(a, b) return vec(a.x - b.x, a.y - b.y, a.z - b.z) end
Vec.__len = function(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end
local pedCoords = {} -- src -> vector3 (a connected player's ped is its src)
local env = setmetatable({
  exports = exportsT, GetCurrentResourceName = function() return 'fh_inventory' end,
  GetInvokingResource = function() return invoking end, locale = function(k) return k end,
  json = { decode = function() return {} end, encode = function() return '[]' end },
  vector3 = vec,
  GetPlayerPed = function(src) return players[src] and src or 0 end,
  GetEntityCoords = function(ped) return pedCoords[ped] or vec(0, 0, 0) end,
  GetPlayers = function() local out = {} for src in pairs(players) do out[#out + 1] = tostring(src) end return out end,
  GetGameTimer = function() return 0 end, GetPlayerName = function() return 'p' end,
  TriggerClientEvent = function() end, TriggerEvent = function() end,
  RegisterNetEvent = function() end, AddEventHandler = function() end, CreateThread = function() end,
  GetResourceState = function() return 'started' end,
}, { __index = function(_, k) local v = _G[k]; if v ~= nil then return v end return stub() end })
env._G = env
local function run(p, e) local fh = assert(io.open(p, 'rb')); local src = fh:read('a'):gsub('`[%w_]+`', '0'); fh:close()
  local f = assert(load(src, '@' .. p, 't', e or env)); f() end
for _, p in ipairs({ R..'fh_core/config.lua', R..'fh_core/shared/items.lua', R..'fh_core/shared/containers.lua',
  R..'fh_core/shared/rules.lua', R..'fh_inventory/shared/config.lua', R..'fh_inventory/server/main.lua',
  R..'fh_inventory/server/shops.lua', R..'fh_inventory/server/compat.lua', R..'fh_inventory/server/fh_api.lua' }) do run(p) end
-- fh_core's server API in its own env: its exports land in CORE, and exports.fh_inventory:FhX(...) calls fh_api's
-- export as fh_core would (GetInvokingResource() == 'fh_core'). Tables pass by reference here, where FXServer
-- msgpacks them, so table identity across the call is never something to rely on (it isn't in either world).
CORE, EVENTS = {}, {}
local coreExports = setmetatable({}, {
  __index = function(_, res)
    if res ~= 'fh_inventory' then return exportsT[res] end
    return setmetatable({}, { __index = function(_, fn) return function(_, ...)
      local prev = invoking; invoking = 'fh_core'
      local r = table.pack(pcall(EXPORTED[fn], ...)); invoking = prev
      if not r[1] then error(r[2], 0) end
      return table.unpack(r, 2, r.n) end end })
  end,
  __call = function(_, name, fn) CORE[name] = fn end })
local coreEnv = setmetatable({ exports = coreExports,
  TriggerEvent = function(name, payload) EVENTS[#EVENTS + 1] = { name = name, payload = payload } end },
  { __index = env })
run(R..'fh_core/server/inventory.lua', coreEnv)
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

-- Cases below run their body inside T.it, so a throw counts as a failure instead of aborting the spec.
local function case(name, fn) T.it(name, function()
  local ok, msg = fn(); assert(ok, name .. (msg ~= nil and (': ' .. tostring(msg)) or '')) end) end
local function drops() local n = 0 for _, c in pairs(I.Inventories) do if c.type == 'drop' then n = n + 1 end end return n end

T.describe('API.CreateDrop validates coords and vetoes items (H1)', function()
  local n0 = drops()
  case('nil coords refused, no drop created', function() return I.API.CreateDrop(nil, {}) == nil and drops() == n0 end)
  case('coords without z refused', function() return I.API.CreateDrop({ x = 1, y = 2 }, {}) == nil and drops() == n0 end)
  case('cargo item refused (drop_bag takes no cargo)', function()
    local id, why = I.API.CreateDrop(vec(1, 2, 3), { [1] = it('crate', 1, 1) })
    return id == nil and drops() == n0, why end)
  case('over the drop weight cap refused', function()
    local id, why = I.API.CreateDrop(vec(1, 2, 3), { [1] = it('bread', env.Config.Drop.MaxWeight // 100 + 1, 1) })
    return id == nil and why == 'fh_too_heavy' and drops() == n0, why end)
  case('caller-supplied weight 0 does not dodge the cap', function()
    local forged = it('bread', env.Config.Drop.MaxWeight // 100 + 1, 1); forged.weight = 0
    local id, why = I.API.CreateDrop(vec(1, 2, 3), { [1] = forged })
    return id == nil and drops() == n0, why end)
  case('bad slot refused', function() return I.API.CreateDrop(vec(1, 2, 3), { [99] = it('bread', 1, 99) }) == nil end)
  case('valid drop ok: drop_bag with the items, {x,y,z} coords', function()
    local id = I.API.CreateDrop({ x = 1, y = 2, z = 3 }, { [1] = it('bread', 2, 1) })
    local d = id and I.Inventories[id]
    return d and d.fhType == 'drop_bag' and d.items[1].amount == 2 and d.items[1].weight == 100 and d.coords.z == 3
  end)
  case('fh_core createDropBag: cargo-only bag refused, nothing left behind', function()
    return CORE.createDropBag({ x = 1, y = 2, z = 3 }, { { name = 'crate', amount = 1 } }) == nil and drops() == n0 + 1 end)
end)

T.describe('fh_core move: one player equipped <-> backpack (H2)', function()
  -- 3 kg equipped + 30 kg backpack of a 35 kg cap: neither section's maxWeight has room for the move unless the
  -- grams leaving the sibling section are credited
  local P2 = mkPlayer(2, { [1] = it('bread', 30, 1), [6] = it('bread', 300, 6) })
  local eq, bp = { type = 'equipped', id = 2 }, { type = 'backpack', id = 2 }
  case('equipped -> backpack ok', function()
    local ok, why = CORE.move(eq, bp, 1, 7)
    return ok == true and P2.PlayerData.items[1] == nil and P2.PlayerData.items[7].amount == 30, why end)
  case('backpack -> equipped ok', function()
    local ok, why = CORE.move(bp, eq, 7, 1)
    return ok == true and P2.PlayerData.items[7] == nil and P2.PlayerData.items[1].amount == 30, why end)
  case('moved event emitted', function() return EVENTS[#EVENTS].name == 'fh:inventory:moved' end)
  case('over the equipped 8 kg cap still refused', function()
    local ok, why = CORE.move(bp, eq, 6, 2, 60)
    return ok == false and why == 'fh_too_heavy' and P2.PlayerData.items[6].amount == 300, why end)
  case('bulky backpack -> equipped still refused', function()
    P2.PlayerData.items[8] = it('saddle', 1, 8)
    local ok, why = CORE.move(bp, eq, 8, 2)
    return ok == false and why == 'fh_size_class' and P2.PlayerData.items[8].name == 'saddle', why end)
  case('refused event emitted', function() return EVENTS[#EVENTS].name == 'fh:inventory:refused' end)
  P2.PlayerData.items[8] = nil
  case('another player is not a sibling: their backpack -> my equipped is a plain move', function()
    mkPlayer(3, { [6] = it('bread', 1, 6) })
    local ok, why = CORE.move({ type = 'backpack', id = 3 }, eq, 6, 2)
    return ok == true and players[3].PlayerData.items[6] == nil, why end)
end)

T.describe('SetInventory slot keys (M3)', function()
  local P4 = mkPlayer(4, { [1] = it('bread', 1, 1) })
  local before = P4.PlayerData.items
  local SI = EXPORTED.SetInventory
  case('fractional slot refused (cargo would hide there)', function()
    local ok, why = SI(4, { [1.5] = it('crate', 1, 1.5) })
    return ok == false and why == 'fh_bad_slot' and P4.PlayerData.items == before, why end)
  case('slot 0 refused', function() return SI(4, { [0] = it('bread', 1, 0) }) == false and P4.PlayerData.items == before end)
  case('slot past the end refused', function() return SI(4, { [26] = it('bread', 1, 26) }) == false end)
  case('integer slots still ok', function() return SI(4, { [2] = it('bread', 3, 2) }) == true end)
end)

T.describe('Fh.Open / Fh.SetCoords on drop bags (L4) and OpenFor reach', function()
  mkPlayer(5, {}); pedCoords[5] = vec(100, 100, 10)
  local id = CORE.createDropBag({ x = 101, y = 100, z = 10 }, { { name = 'bread', amount = 1 } })
  local ref = { type = 'drop_bag', id = id }
  case('drop bag created', function() return type(id) == 'string' end)
  case('fh_core open drop bag in reach', function()
    local ok, why = CORE.open(5, ref) return ok == true and I.OpenInv[5] == id, why end)
  case('setContainerCoords moves a drop bag', function()
    local ok, why = CORE.setContainerCoords(ref, { x = 200, y = 200, z = 10 })
    return ok == true and I.Inventories[id].coords.x == 200, why end)
  case('moved drop bag is out of reach', function()
    local ok, why = CORE.open(5, ref) return ok == false and why == 'fh_out_of_reach', why end)
  case('drop bag coords cannot be cleared', function()
    invoking = 'fh_core'; local ok = I.Fh.SetCoords(ref, nil); invoking = nil
    return ok == false and I.Inventories[id].coords.x == 200 end)
  case('drop bag under the wrong type refused', function() return CORE.open(5, { type = 'chest', id = id }) == false end)
  -- chest reach: fh_core's check, then OpenFor's own InReach
  CORE.registerContainer({ type = 'chest', id = 'fh:chest:5' }, { coords = { x = 100, y = 102, z = 10 } })
  local chest = { type = 'chest', id = 'fh:chest:5' }
  case('chest in reach opens', function()
    local ok, why = CORE.open(5, chest) return ok == true and I.OpenInv[5] == 'fh:chest:5', why end)
  case('chest out of reach refused by fh_core', function()
    pedCoords[5] = vec(100, 110, 10)
    local ok, why = CORE.open(5, chest) return ok == false and why == 'fh_out_of_reach', why end)
  case('OpenFor itself refuses out of reach', function() return I.OpenFor(5, 'fh:chest:5') == false end)
  case('OpenFor refuses a chest with no coords', function()
    pedCoords[5] = vec(100, 102, 10)
    invoking = 'fh_core'; I.Fh.SetCoords(chest, nil); invoking = nil
    return I.OpenFor(5, 'fh:chest:5') == false end)
  case('registerContainer without coords refused', function()
    local ok, why = CORE.registerContainer({ type = 'chest', id = 'fh:chest:6' }, {})
    return ok == false and why == 'fh_no_coords', why end)
end)

T.describe('fh_death hookup (B6c): backpack -> registered drop_bag stash, then deleteContainer', function()
  -- slot 1 = equipped (hotbar), 6+ = backpack. Count bread everywhere before and after: no dupe, no loss.
  local P = mkPlayer(7, { [1] = it('bread', 2, 1), [6] = it('bread', 5, 6), [9] = it('bread', 3, 9) })
  pedCoords[7] = vec(300, 300, 10)
  local function count(items) local n = 0 for _, x in pairs(items or {}) do if x.name == 'bread' then n = n + x.amount end end return n end
  local bagId = 'fh:dropbag:C7:1-1'
  local bag = { type = 'drop_bag', id = bagId }
  local total = count(P.PlayerData.items)
  case('register drop_bag stash', function()
    return CORE.registerContainer(bag, { coords = { x = 300, y = 300, z = 10 }, slots = 30, maxWeight = 1000000 }) == true end)
  local ok, moved, left = CORE.transferAll({ type = 'backpack', id = 7 }, bag, 7)
  case('transferAll backpack -> bag ok, no leftovers', function() return ok == true and #moved == 2 and #left == 0 end)
  case('equipped stays (slot 1 untouched)', function() return P.PlayerData.items[1] and P.PlayerData.items[1].amount == 2 end)
  case('backpack empty', function() for s in pairs(P.PlayerData.items) do if s >= 6 then return false end end return true end)
  case('no dupe, no loss', function() return count(P.PlayerData.items) + count(I.Inventories[bagId].items) == total end)
  case('equipped is never a source for the bag', function()
    return select(2, CORE.transferAll({ type = 'backpack', id = 7 }, bag, 7)) and P.PlayerData.items[1].amount == 2 end)
  case('deleteContainer refused while open', function()
    I.OpenInv[99] = bagId
    local d, why = CORE.deleteContainer(bag); I.OpenInv[99] = nil
    return d == false and why == 'fh_in_use' and I.Inventories[bagId] ~= nil, why end)
  case('deleteContainer returns what it held, then the bag is gone', function()
    local d, items = CORE.deleteContainer(bag)
    return d == true and count(items) == 5 + 3 and I.Inventories[bagId] == nil and I.FhMeta[bagId] == nil end)
  case('deleteContainer twice refused', function() return CORE.deleteContainer(bag) == false end)
  case('deleteContainer refuses carried refs and ground drops', function()
    local dropId = CORE.createDropBag({ x = 300, y = 300, z = 10 }, { { name = 'bread', amount = 1 } })
    return CORE.deleteContainer({ type = 'backpack', id = 7 }) == false
      and CORE.deleteContainer({ type = 'drop_bag', id = dropId }) == false and I.Inventories[dropId] ~= nil end)
end)

T.describe('fh_core.removeItem all-or-nothing (B7)', function()
  local id = 'fh:chest:b7:1'
  local ref = { type = 'chest', id = id }
  local function bread() local n = 0 for _, x in pairs(I.Inventories[id] and I.Inventories[id].items or {}) do
    if x.name == 'bread' then n = n + x.amount end end return n end
  case('register chest', function() return CORE.registerContainer(ref, { coords = { x = 400, y = 400, z = 10 } }) == true end)
  case('seed 3 + 4 bread in two stacks', function()
    return CORE.addItem(ref, 'bread', 3) == true and CORE.addItem(ref, 'bread', 4) == true and bread() == 7, bread() end)
  case('exact across stacks: remove 7 leaves 0', function()
    I.Inventories[id].items = { [1] = it('bread', 3, 1), [2] = it('bread', 4, 2) }
    local ok, why = CORE.removeItem(ref, 'bread', 7)
    return ok == true and bread() == 0 and next(I.Inventories[id].items) == nil, why end)
  case('partial amount spans stacks: remove 5 of 3+4 leaves 2', function()
    I.Inventories[id].items = { [1] = it('bread', 3, 1), [2] = it('bread', 4, 2) }
    local ok, why = CORE.removeItem(ref, 'bread', 5)
    return ok == true and bread() == 2, why end)
  case('short: fh_not_enough and NOTHING removed (no partial)', function()
    I.Inventories[id].items = { [1] = it('bread', 3, 1), [2] = it('bread', 4, 2) }
    local ok, why = CORE.removeItem(ref, 'bread', 8)
    local items = I.Inventories[id].items
    return ok == false and why == 'fh_not_enough' and bread() == 7 and items[1].amount == 3 and items[2].amount == 4, why end)
  case('fh_inventory RemoveItem itself is all-or-nothing (short -> false, untouched)', function()
    return EXPORTED.RemoveItem(id, 'bread', 8) == false and bread() == 7 end)
  case('stale pre-count (taken meanwhile): RemoveItem refuses, fh_not_enough, nothing removed', function()
    local real = EXPORTED.GetItemCount
    local calls = 0
    EXPORTED.GetItemCount = function(...) calls = calls + 1; if calls == 1 then return 99 end return real(...) end
    local ok, why = CORE.removeItem(ref, 'bread', 8)
    EXPORTED.GetItemCount = real
    return ok == false and why == 'fh_not_enough' and bread() == 7 and calls == 2, why end)
  case('item not held: fh_not_enough', function()
    local ok, why = CORE.removeItem(ref, 'saddle', 1) return ok == false and why == 'fh_not_enough', why end)
  case('default amount is 1', function()
    local ok, why = CORE.removeItem(ref, 'bread') return ok == true and bread() == 6, why end)
  case('bad amounts refused, nothing removed', function()
    for _, a in ipairs({ 0, -1, 1.5, 0/0, math.huge, '2' }) do
      local ok, why = CORE.removeItem(ref, 'bread', a)
      if ok ~= false or why ~= 'fh_bad_amount' then return false, tostring(a) .. ' ' .. tostring(why) end
    end
    return bread() == 6 end)
  case('2.0 is an integer amount', function() return CORE.removeItem(ref, 'bread', 2.0) == true and bread() == 4 end)
  case('bad item name refused', function() return select(2, CORE.removeItem(ref, '', 1)) == 'fh_bad_item_name' end)
  case('unregistered world container refused', function()
    return select(2, CORE.removeItem({ type = 'chest', id = 'fh:chest:b7:nope' }, 'bread', 1)) == 'fh_unknown_container' end)
  case('carried refs refused (players use rsg RemoveItem)', function()
    mkPlayer(8, { [1] = it('bread', 5, 1) })
    local ok, why = CORE.removeItem({ type = 'backpack', id = 8 }, 'bread', 1)
    return ok == false and why == 'fh_not_registrable' and players[8].PlayerData.items[1].amount == 5, why end)
  case('unknown container type refused', function()
    return select(2, CORE.removeItem({ type = 'nope', id = id }, 'bread', 1)) == 'fh_unknown_container' end)
end)

T.describe('fh_core.registerItems wiring (B7)', function()
  case('base rsg item name refused as duplicate (read from RSGCore.Shared.Items)', function()
    local ok, err, bad = CORE.registerItems({ bread = { label = 'B', weight = 1 } })
    return ok == false and err == 'fh_duplicate_item' and bad == 'bread', err end)
  case('schema refused before anything is applied', function()
    local ok, err, bad = CORE.registerItems({ b7_tool = { label = 'T', weight = 1, size_class = 'huge' } })
    return ok == false and err == 'fh_bad_size_class' and bad == 'b7_tool' and env.FhItems.definition('b7_tool') == nil, err end)
  case('an fh-defined shared entry (pushed before an fh_core restart) is not a base item', function()
    shared.b7_crate = { name = 'b7_crate', label = 'C', weight = 1, fh_defined = true }
    local _, err = CORE.registerItems({ b7_crate = { label = 'C', weight = 1 } })
    shared.b7_crate = nil
    return err ~= 'fh_duplicate_item', err end)
end)

T.finish()
