# fh_crafting (spec L5)

Reload press and apothecary recipes, plus the station and carried-inventory adapters that `fh_gunsmith` (C3) calls.
Pure rules live in `shared/craft_rules.lua` (global `FhCraftRules`; load from another resource with
`'@fh_crafting/shared/craft_rules.lua'`). Recipes: `shared/recipes.lua` (global `FhCraftRecipes`). Config: `config.lua`
(global `FhCraftingConfig`; there is no `Config` table). Server flow (C2): `/fh_craft <recipe>` = station check ->
canCraft -> remove inputs -> add outputs, all-or-nothing; any failed step undoes the applied ones newest-first (pure:
`shared/craft_flow.lua`, spec `spec/crafting_flow_spec.lua`). An undo that fails is logged as `ROLLBACK INCOMPLETE`
with what was not undone.

## Commands

| Command | Who | Behaviour |
|---|---|---|
| `/fh_craft <recipe>` | player | Craft one recipe id. No argument prints the usage plus every recipe id. Success: `Done: <label>.`; short inputs: `Missing: <need>x <item> (have <n>), ...`. Runtime-only; the server console is refused. |
| `/fh_restore <slot>` | player | Owned by `fh_gunsmith`, not this resource (see its README). |

Chat/notify strings come from the code: `busy`, `unknown_recipe`, `bad_type`, `no_station`, `no_remove`, `no_add`,
`not_enough` (see `server/craft.lua`).

## Server exports

| Export | Signature | Notes |
|---|---|---|
| `getRecipes` | `() -> list` | The `shared/recipes.lua` list (live table, not a copy). |
| `isNearStation` | `(src, stationType, maxDist?) -> boolean, reason\|nil` | H3 shape; delegate of `FhCraftStations.isNearStation`; reasons `bad_type`, `no_station`. |
| `getStations` | `(citizenid) -> list` | H3 shape; `fh_homestead` stations plus `devStations` (`dev = true`) while `fh_dev 1`. |
| `stationAt` | `(coords, maxDist?) -> { plot_id, slot_id, station_type }\|nil` | H3 shape; dev fallback `{ station_type, dev = true }`. |
| `craft` | `(src, recipeId) -> ok, reason, info` | Programmatic `/fh_craft`; reasons `no_player`, `busy`, `unknown_recipe`, `no_station` (+ station reason), `missing_inputs` (`info.missing`), take/give reasons (`no_remove`, `no_add`, `not_enough`, `fh_*`), `error`. |
| `invCount` | `(src, item) -> integer` | Equipped + backpack, via `fh_core` `snapshot`. |
| `invTake` | `(src, item, amount) -> ok, reason` | All-or-nothing across equipped then backpack; `bad_item`, `bad_amount`, `not_enough`, `no_remove`, `fh_*`. |
| `invGive` | `(src, item, amount, info?) -> ok, reason` | First carried section that takes the whole amount; `bad_item`, `bad_amount`, `no_add`, `fh_*`, `no_room`. |
| `invSlot` | `(src, slot) -> item\|nil` | Reads one carried slot (equipped slots first, then backpack). |
| `invSetInfo` | `(src, slot, info) -> false, 'no_set_info'` | Always refuses: no `fh_core` contract writes item info on a carried slot yet. |

Internal globals (not exports): `FhCraftStations` (`isNearStation`, alias `isNear`, `getStations`, `stationAt`),
`FhCraftInv` (`removeItem`, `addItem`, `count`, `take`, `give`, `slot`, `setInfo`), `FhCraft` (`craft`), `FhCraftFlow`,
`FhCraftRules`.

## Config keys (`config.lua`)

| Key | Shape | Meaning |
|---|---|---|
| `items` | table, item name -> definition | Registered at start (and again when `fh_core` restarts) through `exports.fh_core:registerItems`. `resource_gunpowder`, `ammo_box_revolver`, `ammo_box_rifle` and `herb_*` already exist in rsg-core and are not re-registered. |
| `TonicDurations` | table, tonic item -> seconds | `tonic_vigor = 600`, `tonic_steady = 300`. Read by `FhCraftRules.tonicFor`. |
| `devStations` | table, station type -> `{x, y, z}` | Dev-only fallback stations (`gunsmith` at `-280.0, 805.0, 119.0`, `reload` at `-283.0, 805.0, 119.0`, `apothecary` at `-286.0, 805.0, 119.0`), consulted only while convar `fh_dev = 1`. Placeholder coordinates: TODO verify in game. |
| `stationMaxDist` | number | Default reach used by `isNearStation` / `stationAt` when no `maxDist` is passed (3.0). |

Items registered by `fh_crafting`:

| Item | Label | Weight | Size class | Useable |
|---|---|---|---|---|
| `gun_parts` | Gun Parts | 150 | pocket | no |
| `lead` | Lead | 60 | pocket | no |
| `casings` | Brass Casings | 20 | pocket | no |
| `tonic_vigor` | Vigor Tonic | 200 | pocket | yes |
| `tonic_steady` | Steady Tonic | 200 | pocket | yes |

Convars (server.cfg): `setr fh_dev 1` enables the dev-station fallback (read with `GetConvarInt`); `set fh_spike_gated`
is not read here, only by `fh_gunsmith`.

## Recipes (`shared/recipes.lua`)

| id | Station | Label | Inputs | Outputs |
|---|---|---|---|---|
| `ammo_revolver` | `reload` | Reload revolver ammo | `resource_gunpowder` 1, `lead` 2, `casings` 2 | `ammo_box_revolver` 1 |
| `ammo_rifle` | `reload` | Reload rifle ammo | `resource_gunpowder` 2, `lead` 2, `casings` 2 | `ammo_box_rifle` 1 |
| `tonic_vigor` | `apothecary` | Brew Vigor Tonic | `herb_american_ginseng` 2, `herb_wild_mint` 1 | `tonic_vigor` 1 |
| `tonic_steady` | `apothecary` | Brew Steady Tonic | `herb_oregano` 2, `herb_red_sage` 1 | `tonic_steady` 1 |

Recipe shape: `{ id, station_type, inputs = {{item, amount}}, outputs = {{item, amount}}, label }`, with
`station_type` in `gunsmith | reload | apothecary` (gunsmith has no recipe; restore is `fh_gunsmith`). Invalid or
duplicate recipes are printed at start by `FhCraftRules.validateRecipes`.

## Restore caps (`shared/craft_rules.lua`)

Used by `fh_gunsmith`; `gun_parts` restores 20 condition each (`PART_VALUE`).

- Cap by star rating: 1 star = 60, 2 stars = 80, 3 stars = 100 (`STAR_CAPS`). Missing or invalid `stars` = 1 star;
  fractional ratings round and clamp to 1..3.
- Parts needed = `ceil((cap - condition) / 20)`, capped by the parts held; the result never passes the cap. An item
  already at or above its cap refuses with `at_cap`; no condition refuses `no_condition`; no parts refuses `no_parts`.

## Tonics (C4, `server/apothecary.lua`)

| Item / buff id | Magnitude | Duration |
|---|---|---|
| `tonic_vigor` | 1.15 | 600 s |
| `tonic_steady` | 1.10 | 300 s |

Both are registered as rsg-core usable items. Use order: remove one tonic -> `exports.fh_buffs:apply(src, buff_id,
magnitude, duration)`. The tonic is consumed only when the buff applies; on an apply failure the tonic is given back
(`buff_failed`); if the give-back also fails it is lost (`refund_failed`, logged at error level). Magnitude/duration
come from `FhCraftRules.tonicFor` (`TONICS` + `TonicDurations`).

## Adapter contract (workaround until C5; signatures mirror @homestead H3 and @core B7 so C5 swaps bodies only)

| Global | Signature | Notes |
|---|---|---|
| `FhCraftStations.isNearStation` (alias `isNear`) | `(src, stationType, maxDist?) -> boolean, reason\|nil` | H3 shape; reasons `bad_type`, `no_station`. `fh_homestead` export when started, plus `devStations` while `fh_dev 1` |
| `FhCraftStations.getStations` | `(citizenid) -> list` | H3 shape; dev stations appended (`dev = true`) under `fh_dev` |
| `FhCraftStations.stationAt` | `(coords, maxDist?) -> { plot_id, slot_id, station_type }\|nil` | H3 shape; dev fallback `{ station_type, dev = true }` |
| `FhCraftInv.removeItem` | `(ref, item, amount) -> ok, reason` | mirrors fh_core B7; `no_remove` when fh_core lacks the export |
| `FhCraftInv.addItem` | `(ref, item, amount, info?) -> ok, reason` | mirrors fh_core addItem; `no_add` when missing |
| `FhCraftInv.take` | `(src, item, amount) -> ok, reason` | all-or-nothing across equipped then backpack; `not_enough`, `bad_amount`, `no_remove` |
| `FhCraftInv.give` | `(src, item, amount, info\|nil) -> ok, reason` | first carried section that takes the whole amount |
| `FhCraftInv.slot` | `(src, slot) -> item\|nil` | |
| `FhCraftInv.setInfo` | `(src, slot, info) -> ok, reason` | refuses `no_set_info` (no fh_core contract yet) |

## Events

| Kind | Event | Payload |
|---|---|---|
| Emits (client) | `chat:addMessage` | `/fh_craft` replies: `{ args = { 'Crafting', msg } }` |
| Consumes (server) | `onResourceStart` | validates recipes for this resource; re-registers items for this resource or `fh_core` |
| Consumes (server) | `playerDropped` | clears the per-player `busy` craft flag |
| Registers | rsg-core usable items | `tonic_vigor`, `tonic_steady` -> `exports['rsg-core']:CreateUseableItem`; results go out via `exports['rsg-core']:Notify` |

No custom net events are emitted by this resource.

## Pending contracts

- **@homestead H3 station API** (`isNearStation`, `getStations`, `stationAt`): not on main yet. `server/stations.lua`
  calls `exports.fh_homestead` when the resource is started and the export exists; otherwise (and when the player has no
  built station) it falls back to `devStations` while `fh_dev 1`. Workaround removed by block C5 (the fallback then
  stays behind `fh_dev` only).
- **@core B7 `removeItem(ref, item, amount)`** (not on main yet): `server/inv.lua` calls it when the fh_core export
  exists; otherwise every take refuses with `no_remove` and nothing is half-done. Workaround removed by C5.
- **idea-615 (carried-inventory add/remove)**: B7 `removeItem`/`addItem` refuse carried refs (`fh_not_registrable`), so
  crafting, restore and tonics refuse safely (no items are consumed or created) until @core accepts carried refs.
- **idea-612 (tonic caps in fh_buffs)**: `fh_buffs/config.lua` has no caps for `tonic_vigor`/`tonic_steady`, so
  `fh_buffs.apply` refuses and the tonic is returned (`buff_failed`) instead of applying a buff.
- **@core carried-item `setInfo` contract** (unnamed in the plan): `FhCraftInv.setInfo` always refuses
  (`no_set_info`), so `/fh_restore` cannot write a raised condition in game yet.
