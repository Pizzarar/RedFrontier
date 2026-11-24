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
| `shared/access_rules.lua` | `FhAccessRules` | Auto-admin and allowlist rules (pure) |
| `server/access.lua` | - | First-joiner auto-admin, allowlist reject line, `fh_allow` |

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
- `registerItems` rules (B7): names are lowercase letters, digits and `_` (`fh_bad_item_name`; rsg-inventory
  lowercases names when it counts/removes). A name already taken by `FhConfig.Items`, a base rsg item or another
  resource's registration is refused with `fh_duplicate_item`; the same resource re-registering its own names is fine
  (e.g. after it restarts). The whole batch is checked first; on any refusal nothing is applied.

### For sibling lanes

- Register your items from **your own resource** (on its start) with `exports.fh_core:registerItems({ ... })`; check
  the `ok, err, badName` result. Never edit fh_core's `config.lua` (`FhConfig.Items` / `ItemOverrides`) for them.
- If your feature has a conservative path behind `fh_spike_gated`, you may append rows to `docs/spike-gated.md`.

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

## Saddlebag (B6e)

One `saddlebag` container per character, stash id `fh:saddle:<citizenid>` (shared/saddlebag_rules.lua `stashId`).
Capacity and size classes come from `FhConfig.Containers.saddlebag` (20 slots / 60 000 g; pocket + bulky, cargo refused).
It is a world container, so fh_core registers it lazily (first open, or when fh_death reads it) and moves its coords
to the horse (open) or the player (death). Contents persist in fh_inventory by stash id, like the plot chest.

- **Open:** `/saddlebag` (client/saddlebag.lua) takes the horse you ride, else the nearest horse within 4 m, and sends
  `fh:saddlebag:open { netId }` (rate limited per source, `FhConfig.Saddlebag.OpenCooldownMs`, 500 ms).
- **Access rule (server-authoritative, `FhSaddlebagRules.canAccess`):** the netId must resolve to an existing entity
  with `GetEntityType == 1` (ped), not a player ped, whose `GetEntityModel` (normalized to u32) is on
  `FhConfig.Saddlebag.HorseModels` (includes the `fh_spawn_horse` default; names are guesses, **unverified in-game**),
  and lie within `FhContainers.interactDistance('saddlebag')` (3.5 m) of the server-side player ped. `IsThisModelAHorse`
  is client-only and is never called on the server. Mounted = distance ~0, so one check covers "on a horse" and
  "next to one". Reasons: `fh_no_character`, `fh_no_horse`, `fh_not_a_horse`, `fh_no_player_coords`,
  `fh_out_of_reach`. `fh_core.open` then re-checks reach against the horse coords.
- **Transfer (bulky stash <-> saddlebag):** fh_inventory's open pane pairs a world container with the backpack/equipped,
  which refuse bulky, so a bulky item could not move chest -> saddlebag. `/saddlebag in|out <slot> [amount]` sends
  `fh:saddlebag:transfer { netId, dir, slot, amount }`. The server (never the client) names the container: it is the pane
  `FhOpenRef(src)` says the player has open. `FhSaddlebagRules.planTransfer` checks the horse rule, reach to the open
  container from its own coords, the direction, slot and amount, and picks the destination slot (existing stack, else
  first free); then ONE `exports.fh_core:move` re-plans under the rules veto (size class, weight, slot) and fh_inventory
  re-checks and applies it atomically: an item moves once or not at all. Reasons add `fh_nothing_open`,
  `fh_same_container`, `fh_bad_dir`, `fh_bad_slot`, `fh_bad_amount`, `fh_no_item`, `fh_no_slot`, `fh_no_coords`.
  Design choice: a toggle that swaps the player pane to the saddlebag was NOT built (the fork's move/use/drop/trash/give/
  sort handlers and the refresh all assume the "player" side is the player's own inventory; follow-up if wanted).
  Pane refresh: no new code. A successful move goes through fh_inventory's `MoveBetween`, which already calls `Refresh` on
  both containers, and `Refresh` pushes the new contents to every player who has that container open, so the open
  chest/camp pane should update by itself (the saddlebag has no open pane). **Unverified in-game**; if the pane does
  not update, reopening the container (E) shows the truth.
- **Export:** `exports.fh_core:saddlebagOf(src)` returns the stash id (registered at the player's position) for fh_death.
- **Test horse:** the existing admin command `fh_spawn_horse [model]` (B4c spawn contract), no new command.
- **TODO(horse milestone):** there is no horse ownership: any horse opens anyone's saddlebag, and the bag does not
  follow a specific horse. The horse lane replaces this with `fh:saddle:<horse_id>` and an ownership check.
- Pure rule specced in `spec/saddlebag_rules_spec.lua`; the natives side is **not runtime-tested** (no Cfx key).

## Server API

A container ref is `{ type = <container type>, id = <id> }`: `id` is the player server id for `equipped` and
`backpack`, otherwise the fh_inventory stash/drop id (`fh:saddle:<horse>`, `fh:wagon:<wagon>`,
`fh:chest:<homestead>:<n>`, `fh:fence:<citizenid>:<fence>`, `fh:dropbag:<n>`).

A carried ref (`{ type = 'equipped', id = src }` or `{ type = 'backpack', id = src }`) is one section of an online
player's inventory: `equipped` = the hotbar (`FhConfig.Containers.equipped`: first 5 slots, 8 kg own cap), `backpack` = the rest. `addItem`/`removeItem`
on a carried ref act on that section only, never the other one. `src` must be an online player with a loaded
character (rsg-core has a Player for it), else `fh_player_offline`; a non-number id is `fh_bad_ref`.

| Export | Returns |
|---|---|
| `move(fromRef, toRef, fromSlot, toSlot, amount?, src?)` | `ok, reason` |
| `canFit(ref, item, amount, opts?)` | `ok, reason` (`item` may be a name; rsg shared items are looked up) |
| `getWeight(ref)` | `grams` or `nil, reason` |
| `snapshot(ref)` | deep copy `{ [slot] = item }` or `nil, reason` |
| `view(ref)` | read-only `{ items, slots, maxWeight, coords, ... }` or `nil, reason` |
| `openRef(src)` | the container ref the player has open (`{ type, id }`) or `nil, reason` (calls `FhOpenRef`) |
| `saddlebagOf(src)` | the player's saddlebag stash id (registered at their position) or `nil`; used by fh_death |
| `transferAll(fromRef, toRef, src?)` | `true, moved, leftovers` or `false, reason` |
| `registerContainer(ref, { coords, slots?, maxWeight?, label? })` | `ok, reason` |
| `setContainerCoords(ref, coords)` | `ok, reason` |
| `open(src, ref)` | `ok, reason` (reach checked from the server-side ped position) |
| `createDropBag(coords, items, { owner?, label? })` | `id` or `nil, reason` |
| `addItem(ref, name, amount?, info?)` | `true` or `false, reason`; adds `amount` (default 1, integer >= 1) to a registered world container or a carried ref (C3a), all-or-nothing: the rules veto runs first and nothing is added on a refusal (`fh_size_class`: bulky never enters the backpack; `fh_too_heavy`, `fh_no_slot`: not all of it fits) |
| `setItemInfo(ref, slot, info, expectName?)` | `true` or `false, reason`; replaces the `info` table of the item in `slot` of a registered world container or a carried ref (C3b). The caller merges: read the item (`snapshot`/`view`), build the whole new table, pass it. `slot` is the container's own slot number and must be inside the ref's section (`fh_bad_slot`). `fh_empty_slot`: nothing there. `expectName`: refused with `fh_wrong_item` unless the slot still holds that item (closes a swap between your read and this write). Name, amount, weight and the other item fields are never changed |
| `clearContainer(ref)` | `true` or `false, reason`; empties a registered world container (only fh_core may wipe one in fh_inventory) |
| `deleteContainer(ref)` | `true, items` (what it still held) or `false, reason`; registered world stashes only, `fh_in_use` while anyone has it open |
| `registerItems({ [name] = def })` | `true` or `false, err, badName` (validates every entry before applying any; see Items for the duplicate rules) |
| `removeItem(ref, name, amount?)` | `true` or `false, reason`; takes exactly `amount` (default 1, integer >= 1) from a registered world container (B7) or a carried ref's section (C3a), all-or-nothing (`fh_not_enough`: the container or section holds fewer, nothing removed) |

- `addItem`/`removeItem` argument errors, checked before anything changes: `fh_bad_item_name` (not a non-empty
  string), `fh_bad_amount` (not an integer >= 1; `2.0` is fine, `2.5` / `'2'` are not), `fh_bad_info` (info not a
  table), `fh_unknown_item` (carried add of a name rsg-core does not know), `fh_unknown_container` (world ref not
  registered here). Carried calls are logged by fh_inventory like any add/remove on a player (`rsg-log`
  `AddItem` / `RemoveItem`: the player as actor, the section, and `<calling resource> via fh_core.<export>`) and show
  the player the add/remove item box; world calls pass the same tag as fh_inventory's reason (it logs player targets
  only). Neither world nor carried calls emit an `fh:inventory:*` event (those are for `move` / `transferAll`).
- `setItemInfo` checks, in order: the ref (`fh_unknown_container`, `fh_bad_ref`, `fh_player_offline`), `slot` an
  integer (`fh_bad_slot`), `info` a table (`fh_bad_info`), `expectName` nil or a non-empty string
  (`fh_bad_item_name`); then fh_inventory reads, checks and writes the slot with no yield in between (`fh_bad_slot`,
  `fh_empty_slot`, `fh_wrong_item`). It emits no event.
- `clearContainer`, `deleteContainer`, `registerContainer` and `setContainerCoords` refuse carried refs
  (`fh_not_registrable`): they are destructive or world-only.
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
| `FhOpenRef(src)` | `{ type, id }` of the fh container the player has open, or `nil, reason` |
| `FhCreateDropBag(coords, items, opts)` | `id` or `nil, reason` |
| `FhDeleteContainer(ref)` | `true, items` or `false, reason` (deletes memory, FhMeta and the `inventories` row; refused while open) |
| `FhAddItem(ref, name, amount, info?, reason?)` | `true` or `false, reason`; carried refs only: the veto runs against that section alone (`AddTo` with `onlyType`), nothing is added on refusal |
| `FhSetItemInfo(ref, slot, info, expectName?)` | `true` or `false, reason`; any ref `Resolve` accepts: slot inside the ref's section, item present, name check, then `info` (deep copy) replaces the slot's info and the container is committed and refreshed. fh_inventory's `SetItemInfo(target, slot, info)` / `SetItemData(src, name, key, val)` are not used: they are not section-scoped and have no name check |
| `FhRemoveItem(ref, name, amount, reason?)` | `true` or `false, reason`; carried refs only: counts that section, then removes lowest slot first with no yield in between (`fh_not_enough`: nothing removed) |

### Reason codes

Locale keys (fh_inventory's `en.json` carries the text): `fh_unknown_container`, `fh_unknown_item`,
`fh_bad_size_class`, `fh_size_class`, `fh_bad_amount`, `fh_bad_slot`, `fh_too_heavy`, `fh_slot_taken`,
`fh_no_slot`, `fh_no_item`, `fh_same_slot`, `fh_no_coords`, `fh_no_player_coords`, `fh_out_of_reach`,
`fh_bad_ref`, `fh_not_registrable`, `fh_no_player`, `fh_no_container`, `fh_refused`, `fh_inventory_down`,
`fh_inventory_error`. Item validation: `fh_item_not_table`, `fh_bad_item_name`, `fh_bad_label`, `fh_bad_weight`,
`fh_bad_value_base`, `fh_bad_illicit`, `fh_bad_stackable`.
B7: `fh_not_enough` (removeItem: container holds fewer than asked), `fh_duplicate_item` (registerItems name taken).
C3a: `fh_player_offline` (carried ref whose src has no loaded character), `fh_bad_info` (addItem / setItemInfo info
not a table). C3b: `fh_empty_slot` (setItemInfo: nothing in the slot), `fh_wrong_item` (setItemInfo: expectName
does not match the slot).

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
    kind = 'ped',            -- 'ped' | 'object' | 'horse' | 'wagon' (B7; 'vehicle' -> fh_spawn_kind_unsupported)
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
exports.fh_core:requestOfNetId(netId) -- requestId | nil
```

- **Wagons (B7):** `kind = 'wagon'` is created client-side with `CreateVehicle` (networked,
  `bDontAutoCreateDraftAnimals = false`: the game adds the draft horses; they are not separate requests). Adopt skips
  the player-ped check for wagons and objects (`FhSpawnRules.isPedKind`). Gated owner drop: `docs/spike-gated.md` row 5.
- **`requestOfNetId(netId)`:** maps an *adopted* entity's current netId to its requestId, so a consumer that
  deletes the entity on purpose (e.g. a skinned carcass) can `despawn(requestOfNetId(netId))` and stop the tick
  re-requesting it. Non-number, unknown, stale (replaced by a re-adopt with a new netId) and despawned netIds
  return `nil`; the lookup reads live request state, so a netId never maps to a re-used request. There is no
  release-on-death option.
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
- **Post-adopt hook:** after `fh:spawn:release` the spawning client fires the local event `fh:spawn:adopted`
  `{ requestId, tag, owner, kind, netId, entity }` so a resource can set the entity up (AI, weapon). `tag`/`owner` are sent in `fh:spawn:create`.
- **Owner drop** depends on `fh_spike_gated`: see `docs/spike-gated.md`. Gated (default): despawn and re-request.
- **Cleanup:** requests are despawned when the resource that made them stops, and all of them when fh_core stops.
- **Admin:** `fh_spawn_horse [model]`, `fh_spawn_ped [model]` (2 m in front of you), `fh_despawn <requestId>`;
  `group.admin`.
- Pure part specced in `spec/spawn_rules_spec.lua`; the natives side is **not runtime-tested** (no Cfx key yet).

## Access (B-access, private server)

Private dev server: the owner plus up to 5 friends over NordVPN Meshnet (host Media-Host, `100.102.50.11`) (`sv_maxclients 6`, unlisted via `sv_master1 ""`).
Files: `shared/access_rules.lua` (`FhAccessRules`, pure, `spec/access_rules_spec.lua`), `server/access.lua` (natives,
`spec/access_server_spec.lua` with fake natives).

- **Durable store: `fh_core/access.txt`** (gitignored), written with `SaveResourceFile` and read with
  `LoadResourceFile`, never Lua io: live on Windows, `io.open` on the server dir returned nil for an existing
  `admins.cfg` (fixed in core x1). One entry per line: `admin license:<hash>` (owner) / `allow license:<hash>` or
  `allow discord:<id>` (friend), `#` comments. At resource start every entry is validated with `parseIdentifier` and
  re-applied with `ExecuteCommand('add_principal ...')` (server.cfg: `add_ace resource.fh_core command.add_principal
  allow`); malformed entries are logged with their line number and never executed.
- **admins.cfg / allowlist.cfg** stay owner-editable manual overrides that server.cfg `exec`s at boot. fh_core reads
  `admins.cfg` for the lock if it can and best-effort appends grants to both; every io failure prints the path and
  the io error, and success never depends on it.
- **Lock rule** (auto-admin is claimed, nobody new is granted) when ANY of: `access.txt` has an `admin` entry;
  `access.txt` has a malformed `admin` line (fail closed until fixed); `admins.cfg` is readable and has an active
  admin line; at connect, the joiner or any online player already holds the `command` ace (group.admin evidence).
  An unreadable `admins.cfg` with no store owner does NOT lock on its own, because the store decides (that is the
  live bug: the first joiner was never granted). Residual risk, accepted for this private, convar-gated server:
  if `access.txt` is lost AND `admins.cfg` is unreadable AND no admin is online, the next joiner is granted. The
  admin-evidence check closes the common case (the owner is online, or the joiner is already admin via
  `exec admins.cfg`). `FhAccessRules.initialState(content)` without a store still fails closed.

- **Auto-admin:** with `fh_dev 1` and `fh_dev_autoadmin 1` (server.cfg, private dev server only) and no admin line in
  `access.txt` / `server/admins.cfg` (lock rule above), the first player to connect gets
  `add_principal identifier.license:<hash> group.admin` live, saved to `access.txt` (and best-effort `admins.cfg`);
  the console prints `granted group.admin to license:<hash>`. The lock engages only once the `access.txt` entry is
  verified by a re-read. If the write fails, that same license stays admin until restart and the write is
  retried on the next connect; nobody else is granted meanwhile. Later joiners are never auto-granted. Server
  events only (playerConnecting); there is no net event.
- **Allowlist:** rsg-core's own whitelist, switched on in `rsg-core/shared/config.lua` with
  `WhitelistPermission = 'fh.allowlist'`. server.cfg: `add_ace group.fh_allowlist fh.allowlist allow` and
  `add_principal group.admin group.fh_allowlist`, so admins always pass. A friend is
  `add_principal identifier.license:<hash> group.fh_allowlist` in the gitignored `server/allowlist.cfg`.
  `group.admin` also inherits `rsgcore.admin`, so rsg-core's admin commands work for the owner.
- **Connect order:** fh_core grants synchronously in its playerConnecting handler; rsg-core yields (`Wait(0)`,
  events.lua:139) before its whitelist check, so the first joiner is admin, and therefore allowlisted, before rsg-core
  checks, whichever handler runs first.
- **Rejected connect:** rsg-core alone rejects (its whitelist check, `deferrals.done`); fh_core never defers, it
  only prints one console line `allowlist: rejected <name> license:<hash> [discord:<id>]`. The player sees rsg-core's
  `error.not_whitelisted` locale text, edited in `rsg-core/locales/en.json` (server/VENDORED.md) to "You're not on
  this private server's allowlist. Ask the owner to add you: they can see your ID in the server console."
- **admins.cfg unreadable:** the console prints `autoadmin: cannot read admins.cfg (path: <path>: <io error>)` and
  `access.txt` decides the lock (rule above).
- **Adding a friend:** `fh_allow <license:hash | hash | discord:id>` (group.admin, or the server console). Applies
  live, saves `allow <id>` to `access.txt` (verified) and best-effort appends to `allowlist.cfg` (idempotent). The
  friend reconnects. Revoke: delete the line from `access.txt` (and `allowlist.cfg` if there) and restart.
- `tools/lib.ps1` `Initialize-AccessCfgs` creates both cfgs (comments only) when missing, so `exec` never fails.

## Natives

See `docs/natives.md`.

## Tests

`spec/*_spec.lua` (repo root). Run `tools/test.ps1`, which calls `tools/run-specs.py`: embedded Lua 5.4
through Python `lupa` 2.x (`pip install lupa`), one fresh Lua state per spec, exit code 0 when green.
`python tools/run-specs.py --syntax <dir>` compile-checks every `.lua` under a folder. The specs stay
runner-agnostic through `spec/support/fh_prelude.lua`: they also run under busted (`.busted`) or plain
`lua spec/rules_spec.lua`. The server API is covered by `spec/fh_inventory_smoke_spec.lua`, which loads fh_core's
`server/inventory.lua` and fh_inventory's server scripts against stubbed natives (exports are in-process there,
not msgpack'd): B7 removeItem, C3a carried addItem/removeItem, C3b setItemInfo.
