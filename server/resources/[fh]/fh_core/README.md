# fh_core

Core lane contracts for RedFrontier: the item registry (spec §4.1), the container rules and the one
server-side container API (spec §4.2). Other lanes never touch inventory tables; they call `exports.fh_core`.

Start order in `server.cfg`: `rsg-core`, then `fh_core`, then `fh_inventory`.

## Files

| File | Global (FXServer) | Purpose |
|---|---|---|
| `config.lua` | `FhConfig` | Tuning: container slots/weights, reach, item definitions and overrides |
| `shared/items.lua` | `FhItems` | Item definitions: validate, define, resolve, instance fields |
| `shared/containers.lua` | `FhContainers` | Size-class allow-list per container, coords rule, reach check |
| `shared/rules.lua` | `FhRules` | The veto: `canFit`, `getWeight`, `playerViews`, `planMove`, `planTransferAll` |
| `shared/util.lua` | `FhUtil` | Small helpers |
| `server/inventory.lua` | - | The exports below |
| `shared/spawn_rules.lua` | `FhSpawnRules` | Spawn-request state machine, spawner pick, adopt validation (pure) |
| `server/spawn.lua` | `FhSpawn` | Spawn-request exports and net events (natives) |
| `client/spawn.lua` | - | Creates the networked entity a spawn request asks for |

The shared modules are pure Lua (no natives). Under FXServer they set their global; under busted they `return`
the module. They look each other up at call time, so load order inside `shared/*.lua` does not matter.
`FhConfig` is never named `Config`: fh_inventory's vendored code owns `Config`.

fh_inventory loads the same files so both resources run the same rules:

```lua
shared_scripts { '@fh_core/config.lua', '@fh_core/shared/items.lua', '@fh_core/shared/containers.lua', '@fh_core/shared/rules.lua' }
```

## Items (§4.1)

Resolved definition: `{ name, label, weight, size_class, stackable, value_base, illicit, fast_travel }`.

- Existing rsg items get their fh fields from `FhConfig.ItemOverrides[name]` (`size_class`, `value_base`,
  `illicit`, `stackable`); anything unlisted is `pocket`, value 0, legal, stackable unless rsg says `unique`.
- New items go in `FhConfig.Items` or `exports.fh_core:registerItems`. fh_core pushes both, plus the overrides,
  into `RSGCore.Shared.Items` with `exports['rsg-core']:SetItems` on start (and again if rsg-core restarts).
- Per-instance data lives in `item.info`, because rsg-inventory persists only `{name, amount, info, slot}`:
  `info.condition` (nullable 0-100) and `info.stars` (nullable 1-3, the spec's "quality"; `info.quality` is
  already rsg's 0-100 freshness). Read them with `FhItems.condition(item)` / `FhItems.stars(item)`: items saved
  before the fields existed return `nil`, never an error.
- `cargo` items have `fast_travel = false`.

## Containers (§4.2)

| Type | Accepts | Coords | Default slots / weight (g) |
|---|---|---|---|
| `equipped` | pocket | carried | 5 / 8 000 (first player slots = hotbar) |
| `backpack` | pocket | carried | rest of the player slots / total carry minus equipped |
| `saddlebag` | pocket, bulky | required | 20 / 60 000 |
| `wagon` | pocket, bulky, cargo | required (reach 5.0 m) | 60 / 500 000 |
| `chest` | pocket, bulky, cargo | required | 50 / 1 000 000 |
| `drop_bag` | pocket, bulky | required | 30 / 1 000 000 |
| `fence_stash` | pocket, bulky | required | 20 / 200 000 |

`drop_bag` and `fence_stash` are not in the spec table; they take pocket and bulky, never cargo.
Default reach is `FhConfig.Access.InteractDistance` (3.5 m). A world container without coords is refused.

The player's total carry weight stays with rsg-inventory. `FhRules.playerViews` splits it: each section's cap is
`min(own cap, total - the other section's weight)`, so equipped has its own 8 kg sub-cap and the backpack gets
whatever the total leaves.

### Views (what `FhRules` works on)

```lua
view = {
  type = 'chest', items = { [slot] = item }, slots = 50, maxWeight = 1000000,
  slotRange = { first, last } | nil, coords = vector3 | nil,
  -- optional, set by playerViews: ownMaxWeight, group (shared by equipped + backpack), id
}
```

Items are rsg runtime items (`name, amount, weight` per unit, `unique, info, slot`). Only slots inside the view's
range count.

### FhRules

| Function | Returns |
|---|---|
| `FhRules.canFit(view, item, amount, opts)` | `ok, reason, slot`; `opts = { slot, replacing, freed, siblingFreed }` |
| `FhRules.getWeight(view)` | grams |
| `FhRules.playerViews(playerItems, totalCap, totalSlots?)` | `equippedView, backpackView` |
| `FhRules.planMove(fromView, toView, fromSlot, toSlot, amount)` | `plan` or `nil, reason` |
| `FhRules.planTransferAll(fromView, toView)` | `plan, leftovers` |

- `item` may be an item name. `amount` defaults to `item.amount`.
- `replacing`: an item leaving the view in the same operation (its slot is free, its weight removed).
  `freed`: grams leaving this view. `siblingFreed`: grams leaving the sibling section (equipped/backpack).
- `planMove` plan: `{ kind = 'move'|'stack'|'swap', name, fromSlot, toSlot, amount, fromType, toType,
  swapName, swapAmount }`. A swap needs the whole source stack. Both legs of a swap are checked.
- `planTransferAll` plan: an array of `{ kind = 'move'|'stack', name, fromSlot, toSlot, amount, fromType, toType }`;
  leftovers: `{ slot, name, amount, reason }`. Stackables move partially when only part fits; non-stackables
  move whole or not at all.
- Nothing in `FhRules` mutates its arguments.

## Server API

A container ref is `{ type = <container type>, id = <id> }`: `id` is the player server id for `equipped` and
`backpack`, otherwise the fh_inventory stash/drop id (`fh:saddle:<horse>`, `fh:wagon:<wagon>`,
`fh:chest:<homestead>:<n>`, `fh:fence:<citizenid>:<fence>`, `fh:dropbag:<n>`).

| Export | Returns |
|---|---|
| `move(fromRef, toRef, fromSlot, toSlot, amount?, src?)` | `ok, reason` |
| `canFit(ref, item, amount, opts?)` | `ok, reason` (`item` may be a name; rsg shared items are looked up) |
| `getWeight(ref)` | `grams` or `nil, reason` |
| `snapshot(ref)` | deep copy `{ [slot] = item }` or `nil, reason` |
| `transferAll(fromRef, toRef, src?)` | `true, moved, leftovers` or `false, reason` |
| `registerContainer(ref, { coords, slots?, maxWeight?, label? })` | `ok, reason` |
| `setContainerCoords(ref, coords)` | `ok, reason` |
| `open(src, ref)` | `ok, reason` (reach checked from the server-side ped position) |
| `createDropBag(coords, items, { owner?, label? })` | `id` or `nil, reason` |
| `registerItems({ [name] = def })` | `ok, err, badName` (validates every entry before applying any) |

- `registerContainer` refuses `equipped`/`backpack` (`fh_not_registrable`) and any world container without
  valid coords (`fh_no_coords`). Registrations are kept and re-sent when fh_inventory restarts, so register once
  from your resource's start; it is fine to call before fh_inventory is up.
- `move` from server code is trusted: no reach check. `open` is the player-facing path and checks reach.
- If fh_inventory is not running, calls fail with `fh_inventory_down`.

### fh_inventory adapter (what fh_core calls)

fh_inventory exports these; only fh_core may call them. They re-check with `FhRules` under fh_inventory's own
state before mutating.

| Export | Returns |
|---|---|
| `FhView(ref)` | `view` (player refs via `FhRules.playerViews`) or `nil, reason` |
| `FhSnapshot(ref)` | deep-copied items or `nil, reason` |
| `FhMove(fromRef, toRef, fromSlot, toSlot, amount?)` | `ok, reason` |
| `FhTransferAll(fromRef, toRef)` | `true, moved, leftovers` or `false, reason` |
| `FhRegisterContainer(ref, { slots, maxWeight, coords, label })` | `ok, reason` |
| `FhSetCoords(ref, coords)` | `ok, reason` |
| `FhOpen(src, ref)` | `ok, reason` |
| `FhCreateDropBag(coords, items, opts)` | `id` or `nil, reason` |

### Reason codes

Locale keys (fh_inventory's `en.json` carries the text): `fh_unknown_container`, `fh_unknown_item`,
`fh_bad_size_class`, `fh_size_class`, `fh_bad_amount`, `fh_bad_slot`, `fh_too_heavy`, `fh_slot_taken`,
`fh_no_slot`, `fh_no_item`, `fh_same_slot`, `fh_no_coords`, `fh_no_player_coords`, `fh_out_of_reach`,
`fh_bad_ref`, `fh_not_registrable`, `fh_no_player`, `fh_no_container`, `fh_refused`, `fh_inventory_down`,
`fh_inventory_error`. Item validation: `fh_item_not_table`, `fh_bad_item_name`, `fh_bad_label`, `fh_bad_weight`,
`fh_bad_value_base`, `fh_bad_illicit`, `fh_bad_stackable`.

## Events

Emitted (server-local `TriggerEvent`, one table, see `docs/events.md`):

| Event | When | Payload |
|---|---|---|
| `fh:inventory:moved` | `move` succeeded | `{ src, citizenid, from, to, item, count }` |
| `fh:inventory:refused` | `move` refused | `{ src, citizenid, from, to, item, count, reason }` |
| `fh:inventory:transferred` | `transferAll` ran | `{ src, citizenid, from, to, moved, leftovers }` |

`from`/`to` are container refs. `src` is the acting player (the `src` argument, else the player side of the
move); it may be nil for container-to-container moves. Moves the player makes by dragging in the inventory UI
are checked inside fh_inventory and do not go through these events.

Consumed: `onResourceStart` (fh_core, rsg-core, fh_inventory), `RSGCore:Server:UpdateObject`.

## Spawn contract

Server CREATE_PED / CREATE_OBJECT_NO_OFFSET / CREATE_AUTOMOBILE / CREATE_VEHICLE_SERVER_SETTER are compiled out on
RDR3. So **the server owns the decision and the state, a chosen client creates the networked entity, and the server
adopts it by netId.** Every `[fh]` spawn (admin commands, camps, drop bags) goes through this.

```lua
local id, err = exports.fh_core:requestSpawn({
    kind = 'ped',            -- 'ped' | 'object' | 'horse' (no vehicles/wagons until M4)
    model = 'g_m_m_unibanditos_01', -- name or hash
    coords = vector4(x, y, z, h),   -- vec3/vec4 or { x, y, z }; heading = spec.heading or coords.w or 0
    owner = { kind = 'camp', id = 'camp_1' }, tag = 'camp_1:outlaw:1',
}, {
    near = coords,           -- where to look for a spawner (default spec.coords)
    timeoutMs = 10000, retries = 3,
    onReady = function(netId, requestId) end,   -- may fire again with a new netId after a re-request
    onFailed = function(reason, requestId) end, -- retries used up; the request is gone
})
exports.fh_core:despawn(id)      -- true | false, reason
exports.fh_core:getSpawn(id)     -- { state, netId, tag, owner, kind, attempts } | nil
```

- **Spawner pick:** nearest ready player within `FhConfig.Spawn.Range` of `near`; players not yet tried this cycle
  first; else (if `FallbackAnyPlayer`) the nearest ready player anywhere; else park as `pending_no_client` and retry
  every tick (a player joins or comes in range).
- **States:** `pending -> dispatched -> verifying -> adopted`; `dispatched` times out after `timeoutMs` and retries
  with the next candidate; after `retries` extra attempts -> `failed` (`onFailed`). Spawner drop mid-dispatch ->
  retry. `despawned` and `failed` are terminal.
- **Adopt:** `fh:spawn:created` counts only from the chosen spawner with the current per-attempt token while
  `dispatched`, with a positive-integer netId. The server then waits up to `AdoptWaitMs` for the netId and checks
  the entity exists, is network-owned by the spawner, is held by no other request, is not a player ped, its model
  hash matches and it is within `AdoptMaxDistance` of the requested coords. A mismatch asks the spawner to delete
  it and retries. `verifying` has its own deadline (`AdoptWaitMs` + 2 s), so it can't wedge.
- **Exactly-once:** one live entity per requestId. A second `created` (duplicate), one from an earlier attempt
  (stale), or one for a despawned/failed request is answered with `fh:spawn:delete` naming that extra netId; the
  client deletes only an entity it made for that token with that netId, so neither a forged message nor a
  duplicate can delete the adopted entity or anything else. When an attempt is retired mid-verify (spawner drop,
  verify timeout, despawn), the server deletes its reported entity itself if it saw it owned by that spawner, the
  model matches and no other request holds it (OneSync may have migrated it; otherwise there would be two).
- **Owner drop** depends on `fh_spike_gated`: see `docs/spike-gated.md`. Gated (default): despawn and re-request.
- **Cleanup:** requests are despawned when the resource that made them stops, and all of them when fh_core stops.
- **Admin:** `fh_spawn_horse [model]`, `fh_spawn_ped [model]` (2 m in front of you), `fh_despawn <requestId>`;
  `group.admin`.
- Pure part specced in `spec/spawn_rules_spec.lua`; the natives side is **not runtime-tested** (no Cfx key yet).

## Natives

See `docs/natives.md`.

## Tests

`spec/*_spec.lua` (repo root). Run `tools/test.ps1`, which calls `tools/run-specs.py`: embedded Lua 5.4
through Python `lupa` 2.x (`pip install lupa`), one fresh Lua state per spec, exit code 0 when green.
`python tools/run-specs.py --syntax <dir>` compile-checks every `.lua` under a folder. The specs stay
runner-agnostic through `spec/support/fh_prelude.lua`: they also run under busted (`.busted`) or plain
`lua spec/rules_spec.lua`. The server API is not covered by specs; it was smoke-tested against stubbed
natives and fh_inventory exports only.
