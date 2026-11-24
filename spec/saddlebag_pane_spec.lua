-- B6f: fh_inventory's backpack <-> saddlebag player pane, dark behind convar fh_saddlebag_pane (default false).
-- Loads fh_core's shared modules and fh_inventory's server scripts into a stubbed FXServer world (same approach as
-- spec/fh_inventory_smoke_spec.lua) and drives the net event handlers directly. exports.fh_core:saddlebagPane (the
-- B6e horse gate, server/saddlebag.lua) is a test double here: canAccess itself is specced in saddlebag_rules_spec.lua.
-- Not a substitute for a live boot (no msgpack, no natives).
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local R = here .. '../server/resources/[fh]/'
local function stub() return setmetatable({}, { __index = function() return stub() end, __call = function() return nil end }) end

local invoking, players, handlers, convars, sent = nil, {}, {}, {}, {}
local gate = {} -- [src] = { ok = bool, why = reason } (default: no horse)
local gateCalls = 0
local shared = {
  bread = { name = 'bread', label = 'Bread', weight = 100, unique = false, type = 'item', useable = true },
  saddle = { name = 'saddle', label = 'Saddle', weight = 5000, unique = true, type = 'item', size_class = 'bulky' },
  crate = { name = 'crate', label = 'Crate', weight = 9000, unique = true, type = 'item', size_class = 'cargo' },
}
local used = {}
local Core = { Shared = { Items = shared }, Functions = stub(), Commands = stub() }
Core.Functions.GetPlayer = function(src) return players[src] end
Core.Functions.GetRSGPlayers = function() return {} end
Core.Functions.AddPlayerMethod = function() end
Core.Functions.CanUseItem = function(name) return function(src, item) used[#used + 1] = { src = src, name = item.name } end end
local EXPORTED = {}
local fhCore = { saddlebagPane = function(_, src, netId)
  gateCalls = gateCalls + 1
  local g = gate[src]
  if type(netId) ~= 'number' or not g then return false, 'fh_no_horse' end
  if not g.ok then return false, g.why end
  return true, 'fh:saddle:C' .. src
end }
local exportsT = setmetatable({}, { __index = function(_, res)
  if res == 'fh_core' then return fhCore end
  return setmetatable({}, { __index = function(_, fn) return function() if fn == 'GetCoreObject' then return Core end end end })
end, __call = function(_, name, fn) EXPORTED[name] = fn end })
local Vec = {}
Vec.__index = Vec
local function vec(x, y, z) return setmetatable({ x = x, y = y, z = z }, Vec) end
Vec.__sub = function(a, b) return vec(a.x - b.x, a.y - b.y, a.z - b.z) end
Vec.__len = function(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end
local clock = 0
local env = setmetatable({
  exports = exportsT, GetCurrentResourceName = function() return 'fh_inventory' end,
  GetInvokingResource = function() return invoking end, locale = function(k) return k end,
  json = { decode = function() return {} end, encode = function() return '[]' end },
  vector3 = vec,
  GetPlayerPed = function(src) return players[src] and src or 0 end,
  GetEntityCoords = function() return vec(0, 0, 0) end,
  GetPlayers = function() local out = {} for src in pairs(players) do out[#out + 1] = tostring(src) end return out end,
  GetGameTimer = function() clock = clock + 10000 return clock end, -- every call is past every cooldown
  GetPlayerName = function() return 'p' end,
  GetConvar = function(name, def) local v = convars[name]; if v == nil then return def end return v end,
  TriggerClientEvent = function(name, src, ...) sent[#sent + 1] = { name = name, src = src, n = select('#', ...), args = { ... } } end,
  TriggerEvent = function() end,
  RegisterNetEvent = function(name, fn) if fn then handlers[name] = fn end end,
  AddEventHandler = function(name, fn) -- keep the first playerDropped (fh_inventory main.lua; shops.lua loads after)
    if name == 'playerDropped' and not handlers[name] then handlers[name] = fn end end,
  CreateThread = function() end,
  GetResourceState = function() return 'started' end,
}, { __index = function(_, k) local v = _G[k]; if v ~= nil then return v end return stub() end })
env._G = env
local function run(p) local fh = assert(io.open(p, 'rb')); local src = fh:read('a'):gsub('`[%w_]+`', '0'); fh:close()
  assert(load(src, '@' .. p, 't', env))() end
for _, p in ipairs({ R..'fh_core/config.lua', R..'fh_core/shared/items.lua', R..'fh_core/shared/containers.lua',
  R..'fh_core/shared/rules.lua', R..'fh_inventory/shared/config.lua', R..'fh_inventory/server/main.lua',
  R..'fh_inventory/server/shops.lua', R..'fh_inventory/server/compat.lua', R..'fh_inventory/server/fh_api.lua' }) do run(p) end
local I = env.InvCore

local function it(name, amount, slot) local s = shared[name]
  return { name = name, amount = amount, slot = slot, info = {}, weight = s.weight, unique = s.unique, label = s.label,
    type = 'item', useable = s.useable } end
local function mkPlayer(src, items)
  local P = { PlayerData = { source = src, items = items, slots = 25, weight = 35000, citizenid = 'C' .. src, charinfo = {} },
    Functions = {} }
  P.Functions.SetPlayerData = function(k, v) P.PlayerData[k] = v end
  players[src] = P
  return P
end
local function fire(name, src, ...) env.source = src; handlers[name](...) end
local function register(ref, opts) invoking = 'fh_core'; local ok, why = I.Fh.RegisterContainer(ref, opts); invoking = nil; return ok, why end
local function last(name, src)
  for i = #sent, 1, -1 do local e = sent[i]; if e.name == name and (src == nil or e.src == src) then return e end end
end
local function notified(src, key)
  local e = last('RSGCore:Client:Notify', src); return e ~= nil and e.args[1].description == key end
local function snap(items) local out = {}
  for s, x in pairs(items or {}) do out[#out + 1] = s .. '=' .. x.name .. 'x' .. x.amount end
  table.sort(out) return table.concat(out, ' ') end
local function case(name, fn) T.it(name, function()
  local ok, msg = fn(); assert(ok, name .. (msg ~= nil and (': ' .. tostring(msg)) or '')) end) end

-- World: player 1 (C1) with bread on the hotbar and in the backpack, player 2 next to them, a chest at 1 m (open),
-- player 1's saddlebag (registered by fh_core, as ensure() does on the gate).
local P1 = mkPlayer(1, { [1] = it('bread', 2, 1), [6] = it('bread', 5, 6) })
local P2 = mkPlayer(2, {})
local BAG = 'fh:saddle:C1'
local chestRef = { type = 'chest', id = 'fh:chest:pane' }
assert(register(chestRef, { coords = { x = 1, y = 0, z = 0 } }))
assert(register({ type = 'saddlebag', id = BAG }, { coords = { x = 2, y = 0, z = 0 }, label = 'Saddlebag' }))
local chest, bag = I.Inventories['fh:chest:pane'], I.Inventories[BAG]
local function reset()
  P1.PlayerData.items = { [1] = it('bread', 2, 1), [6] = it('bread', 5, 6) }
  P2.PlayerData.items = {}
  chest.items = { [1] = it('saddle', 1, 1), [2] = it('bread', 3, 2) }
  bag.items = { [1] = it('bread', 4, 1), [2] = it('saddle', 1, 2) }
  gate[1] = { ok = true }
  I.Pane[1] = nil
  I.OpenInv[1] = 'fh:chest:pane'
  used = {}
end
local function toggle(pane, netId) fire('rsg-inventory:server:pane', 1, { pane = pane, netId = netId or 7 }) end
local function move(from, to, fromSlot, toSlot, amount)
  fire('rsg-inventory:server:move', 1, { from = from, to = to, fromSlot = fromSlot, toSlot = toSlot, amount = amount }) end

T.describe('flag off (default): byte-for-byte the backpack pane', function()
  reset(); convars.fh_saddlebag_pane = nil
  case('toggle event ignored: no pane, no gate call', function()
    local g0 = gateCalls; toggle('saddlebag')
    return I.Pane[1] == nil and gateCalls == g0 end)
  case('open sends exactly (player, other): no third arg, no pane field', function()
    I.OpenFor(1, 'fh:chest:pane')
    local e = last('rsg-inventory:client:open', 1)
    return e and e.n == 2 and e.args[1].id == 1 and e.args[1].pane == nil, e and e.n end)
  case("'player' is the backpack: bulky chest -> player refused (fh_size_class)", function()
    move('fh:chest:pane', 'player', 1, 7)
    return chest.items[1] and chest.items[1].name == 'saddle' and P1.PlayerData.items[7] == nil and notified(1, 'fh_size_class') end)
  case("'player' is the backpack: bread chest -> player slot 8 ok", function()
    move('fh:chest:pane', 'player', 2, 8)
    return P1.PlayerData.items[8] and P1.PlayerData.items[8].amount == 3 and chest.items[2] == nil end)
  case('use works from the player slot (no gate call)', function()
    local g0 = gateCalls; fire('rsg-inventory:server:useItem', 1, 6)
    return #used == 1 and used[1].name == 'bread' and gateCalls == g0 end)
  case('the saddlebag id is not reachable by naming it', function()
    local before = snap(bag.items); move(BAG, 'player', 1, 9)
    return snap(bag.items) == before and P1.PlayerData.items[9] == nil end)
  case("convar 'false' is off too", function()
    convars.fh_saddlebag_pane = 'false'; toggle('saddlebag'); convars.fh_saddlebag_pane = nil
    return I.Pane[1] == nil end)
end)

T.describe('flag on: toggle and gate', function()
  convars.fh_saddlebag_pane = 'true'
  case('gate fail (out of reach): no pane, reason notified', function()
    reset(); gate[1] = { ok = false, why = 'fh_out_of_reach' }; toggle('saddlebag')
    return I.Pane[1] == nil and notified(1, 'fh_out_of_reach') end)
  case('gate fail (not a horse): no pane', function()
    reset(); gate[1] = { ok = false, why = 'fh_not_a_horse' }; toggle('saddlebag')
    return I.Pane[1] == nil and notified(1, 'fh_not_a_horse') end)
  case('no netId: no pane, fh_no_horse, gate never asked', function()
    reset(); local g0 = gateCalls
    fire('rsg-inventory:server:pane', 1, { pane = 'saddlebag' })
    return I.Pane[1] == nil and gateCalls == g0 and notified(1, 'fh_no_horse') end)
  case('client-named pane ids are not a thing: unknown pane value ignored', function()
    reset(); fire('rsg-inventory:server:pane', 1, { pane = BAG, netId = 7 })
    return I.Pane[1] == nil end)
  case('toggle on (mounted / near horse): pane = own saddlebag, refresh marks it', function()
    reset(); toggle('saddlebag')
    local e = last('rsg-inventory:client:refresh', 1)
    return I.Pane[1] and I.Pane[1].id == BAG and e and e.args[1].pane == 'saddlebag' and e.args[1].id == BAG end)
  case('open with the flag on: third arg { saddlebagPane = true }, pane kept', function()
    I.OpenFor(1, 'fh:chest:pane')
    local e = last('rsg-inventory:client:open', 1)
    return e and e.n == 3 and e.args[3].saddlebagPane == true and e.args[1].pane == 'saddlebag' end)
  case('IsOpenByAnyone counts the pane (no idle unload, no delete)', function()
    I.OpenInv[1] = 'fh:chest:pane'; return I.IsOpenByAnyone(BAG) == true end)
  case('toggle back to backpack: pane gone, refresh shows the player', function()
    toggle('backpack')
    local e = last('rsg-inventory:client:refresh', 1)
    return I.Pane[1] == nil and e and e.args[1].id == 1 and e.args[1].pane == nil end)
  case('cannot toggle while the saddlebag is the open (other) pane', function()
    reset(); I.OpenInv[1] = BAG; toggle('saddlebag')
    return I.Pane[1] == nil and notified(1, 'fh_same_container') end)
  case('opening the saddlebag as the other pane drops the player pane back', function()
    reset(); toggle('saddlebag'); I.OpenFor(1, BAG)
    local e = last('rsg-inventory:client:open', 1)
    return I.Pane[1] == nil and e.args[1].id == 1 end)
end)

T.describe('flag on: bulky only into the saddlebag', function()
  case('bulky chest -> player pane (saddlebag) ok', function()
    reset(); toggle('saddlebag'); move('fh:chest:pane', 'player', 1, 5)
    return bag.items[5] and bag.items[5].name == 'saddle' and chest.items[1] == nil and P1.PlayerData.items[5] == nil end)
  case('bulky chest -> player pane (backpack) refused', function()
    reset(); move('fh:chest:pane', 'player', 1, 7)
    return chest.items[1].name == 'saddle' and P1.PlayerData.items[7] == nil and notified(1, 'fh_size_class') end)
  case('cargo chest -> saddlebag pane still refused (saddlebag takes no cargo)', function()
    reset(); chest.items[3] = it('crate', 1, 3); toggle('saddlebag'); move('fh:chest:pane', 'player', 3, 5)
    return chest.items[3].name == 'crate' and bag.items[5] == nil and notified(1, 'fh_size_class') end)
  case('saddlebag pane -> chest: bulky back out ok', function()
    reset(); toggle('saddlebag'); move('player', 'fh:chest:pane', 2, 9)
    return chest.items[9] and chest.items[9].name == 'saddle' and bag.items[2] == nil end)
  case('split inside the saddlebag pane stays in the saddlebag', function()
    reset(); toggle('saddlebag'); move('player', 'player', 1, 6, 1)
    return bag.items[1].amount == 3 and bag.items[6].amount == 1 and P1.PlayerData.items[6].amount == 5 end)
  case('forged raw src id while the saddlebag pane is up: refused (backpack is not on screen)', function()
    reset(); toggle('saddlebag'); local b, p = snap(bag.items), snap(P1.PlayerData.items)
    fire('rsg-inventory:server:move', 1, { from = 'player', to = 1, fromSlot = 1, toSlot = 9 })
    fire('rsg-inventory:server:move', 1, { from = 1, to = 'player', fromSlot = 6, toSlot = 9 })
    return snap(bag.items) == b and snap(P1.PlayerData.items) == p end)
  case("another character's saddlebag is never reachable", function()
    reset(); toggle('saddlebag')
    assert(register({ type = 'saddlebag', id = 'fh:saddle:C2' }, { coords = { x = 2, y = 0, z = 0 } }))
    I.Inventories['fh:saddle:C2'].items = { [1] = it('bread', 9, 1) }
    move('fh:saddle:C2', 'player', 1, 9)
    return I.Inventories['fh:saddle:C2'].items[1].amount == 9 and bag.items[9] == nil end)
end)

-- Every routed handler: with the gate failing at the moment of the action, nothing changes, the pane snaps back
-- and the reason is shown. With the gate passing, the handler acts on the saddlebag, never on the backpack.
T.describe('flag on: server veto on every routed handler', function()
  local function vetoed(label, act)
    case(label .. ': gate fails -> nothing changes, snapped back', function()
      reset(); toggle('saddlebag'); gate[1] = { ok = false, why = 'fh_out_of_reach' }
      local b, p, c, q = snap(bag.items), snap(P1.PlayerData.items), snap(chest.items), snap(P2.PlayerData.items)
      act()
      return snap(bag.items) == b and snap(P1.PlayerData.items) == p and snap(chest.items) == c
        and snap(P2.PlayerData.items) == q and I.Pane[1] == nil and notified(1, 'fh_out_of_reach') end)
  end
  vetoed('move', function() move('player', 'fh:chest:pane', 1, 9) end)
  vetoed('split', function() move('player', 'player', 1, 6, 1) end)
  vetoed('sort', function() fire('rsg-inventory:server:sort', 1, 'player') end)
  vetoed('give', function() fire('rsg-inventory:server:give', 1, 2, 1, 1, 'bread') end)
  vetoed('trash', function() fire('rsg-inventory:server:trash', 1, 1, 1, 'bread') end)
  vetoed('drop', function() fire('rsg-inventory:server:drop', 1, 1, 1) end)
  case('a gate answering for a different bag is a failure too (fh_pane_changed)', function()
    reset(); toggle('saddlebag'); I.Pane[1].id = 'fh:saddle:C9'
    move('player', 'fh:chest:pane', 1, 9)
    return I.Pane[1] == nil and bag.items[1].amount == 4 and notified(1, 'fh_pane_changed') end)
  case('use refused on the saddlebag pane (slot is a saddlebag slot): nothing used', function()
    reset(); toggle('saddlebag'); fire('rsg-inventory:server:useItem', 1, 1)
    return #used == 0 and notified(1, 'fh_pane_use') end)
  case('shop buy/sell refused on the saddlebag pane', function()
    reset(); toggle('saddlebag')
    I.Inventories['shop-t'] = { id = 'shop-t', type = 'shop', label = 'S', slots = 5, maxWeight = 0, items = {},
      shopCoords = vec(0, 0, 0) }
    I.OpenInv[1] = 'shop-t'
    local sold, bought = 0, 0
    local s0, b0 = env.Shops.Sell, env.Shops.Buy
    env.Shops.Sell = function() sold = sold + 1 end; env.Shops.Buy = function() bought = bought + 1 end
    move('player', 'shop-t', 1, 1, 1); move('shop-t', 'player', 1, 3, 1)
    local vetoed = sold == 0 and bought == 0 and notified(1, 'fh_pane_shop')
    toggle('backpack'); I.OpenInv[1] = 'shop-t'; move('player', 'shop-t', 6, 1, 1) -- parity: backpack still sells
    env.Shops.Sell, env.Shops.Buy = s0, b0
    I.Inventories['shop-t'] = nil
    return vetoed and sold == 1 end)
  case('give routed: bread leaves the saddlebag, backpack untouched', function()
    reset(); toggle('saddlebag'); fire('rsg-inventory:server:give', 1, 2, 1, 2, 'bread')
    return bag.items[1].amount == 2 and P1.PlayerData.items[6].amount == 5 and P2.PlayerData.items[1]
      and P2.PlayerData.items[1].amount == 2 end)
  case('give routed: bulky to a player refused (their backpack takes no bulky)', function()
    reset(); toggle('saddlebag'); fire('rsg-inventory:server:give', 1, 2, 2, 1, 'saddle')
    return bag.items[2] and bag.items[2].name == 'saddle' and next(P2.PlayerData.items) == nil and notified(1, 'target_full') end)
  case('trash routed: from the saddlebag only', function()
    reset(); toggle('saddlebag'); fire('rsg-inventory:server:trash', 1, 1, 3, 'bread')
    return bag.items[1].amount == 1 and P1.PlayerData.items[1].amount == 2 and P1.PlayerData.items[6].amount == 5 end)
  case('drop routed: bulky from the saddlebag to a ground bag', function()
    reset(); toggle('saddlebag'); I.OpenInv[1] = nil
    fire('rsg-inventory:server:drop', 1, 2, 1)
    local dropId = I.OpenInv[1]
    local d = type(dropId) == 'string' and I.Inventories[dropId]
    return bag.items[2] == nil and d and d.type == 'drop' and d.items[1] and d.items[1].name == 'saddle' end)
  case('sort routed: the saddlebag sorts from slot 1, the hotbar is untouched', function()
    reset(); toggle('saddlebag'); bag.items = { [3] = it('bread', 1, 3), [5] = it('bread', 2, 5) }
    fire('rsg-inventory:server:sort', 1, 'player')
    return bag.items[1] and bag.items[1].amount == 3 and bag.items[3] == nil and P1.PlayerData.items[1].amount == 2 end)
end)

T.describe('flag on: snap-back', function()
  case('riding / walking away (periodic PaneCheck): back to backpack, refresh shows the player', function()
    reset(); toggle('saddlebag'); gate[1] = { ok = false, why = 'fh_out_of_reach' }
    local r = I.PaneCheck(1)
    local e = last('rsg-inventory:client:refresh', 1)
    return r == false and I.Pane[1] == nil and e.args[1].id == 1 and e.args[1].pane == nil end)
  case('gate still fine: PaneCheck keeps the pane', function()
    reset(); toggle('saddlebag'); return I.PaneCheck(1) == I.Pane[1] and I.Pane[1].id == BAG end)
  case('closing the inventory: next open starts on the backpack', function()
    reset(); toggle('saddlebag'); fire('rsg-inventory:server:close', 1)
    return I.Pane[1] == nil end)
  case('flag turned off live, next action first: refused (its slot is a saddlebag slot), refreshed to the backpack', function()
    reset(); toggle('saddlebag'); convars.fh_saddlebag_pane = 'false'
    local b, p = snap(bag.items), snap(P1.PlayerData.items)
    fire('rsg-inventory:server:trash', 1, 1, 1, 'bread')
    local e = last('rsg-inventory:client:refresh', 1)
    local refused = snap(bag.items) == b and snap(P1.PlayerData.items) == p and I.Pane[1] == nil
      and notified(1, 'fh_pane_disabled') and e.args[1].id == 1 and e.args[1].pane == nil
    fire('rsg-inventory:server:trash', 1, 6, 1, 'bread') -- now the client shows the backpack
    convars.fh_saddlebag_pane = 'true'
    return refused and P1.PlayerData.items[6].amount == 4 and bag.items[1].amount == 4 end)
  case('flag turned off live, use first: nothing used, refreshed to the backpack', function()
    reset(); toggle('saddlebag'); convars.fh_saddlebag_pane = 'false'
    fire('rsg-inventory:server:useItem', 1, 1)
    local e = last('rsg-inventory:client:refresh', 1)
    convars.fh_saddlebag_pane = 'true'
    return #used == 0 and I.Pane[1] == nil and notified(1, 'fh_pane_disabled') and e.args[1].id == 1 end)
  case('flag turned off live, nobody acts: the 1 s check refreshes the client to the backpack', function()
    reset(); toggle('saddlebag'); convars.fh_saddlebag_pane = 'false'
    local r = I.PaneCheck(1)
    local e = last('rsg-inventory:client:refresh', 1)
    convars.fh_saddlebag_pane = 'true'
    return r == false and I.Pane[1] == nil and e.args[1].id == 1 and e.args[1].pane == nil end)
  case('player leaves: pane state gone (a rejoin with the same id starts on the backpack)', function()
    reset(); toggle('saddlebag'); fire('playerDropped', 1)
    local gone = I.Pane[1] == nil
    I.OpenInv[1] = nil
    return gone end)
  case('use while the gate fails: nothing used, snapped back with the gate reason', function()
    reset(); toggle('saddlebag'); gate[1] = { ok = false, why = 'fh_out_of_reach' }
    fire('rsg-inventory:server:useItem', 1, 6)
    return #used == 0 and I.Pane[1] == nil and notified(1, 'fh_out_of_reach') end)
end)
convars.fh_saddlebag_pane = nil
T.finish()
