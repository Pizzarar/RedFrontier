# fh_crafting (spec L5)

Reload press and apothecary recipes, herb gathering (C9), plus the station and carried-inventory adapters that
`fh_gunsmith` (C3) calls. Pure rules live in `shared/craft_rules.lua` (global `FhCraftRules`; load from another resource
with `'@fh_crafting/shared/craft_rules.lua'`) and `shared/gather_rules.lua` (global `FhGatherRules`). Recipes:
`shared/recipes.lua` (global `FhCraftRecipes`). Config: `config.lua` (global `FhCraftingConfig`; there is no `Config`
table). Server flow (C2): `/fh_craft <recipe>` = station check ->
canCraft -> remove inputs -> add outputs, all-or-nothing; any failed step undoes the applied ones newest-first (pure:
`shared/craft_flow.lua`, spec `spec/crafting_flow_spec.lua`). An undo that fails is logged as `ROLLBACK INCOMPLETE`
with what was not undone.

## Commands

| Command | Who | Behaviour |
|---|---|---|
| `/fh_craft <recipe>` | player | Craft one recipe id. No argument prints the usage plus every recipe id. Success: `Done: <label>.`; short inputs: `Missing: <need>x <item> (have <n>), ...`. Runtime-only; the server console is refused. |
| `/fh_restore <slot>` | player | Owned by `fh_gunsmith`, not this resource (see its README). |

Chat/notify strings come from the code: `busy`, `unknown_recipe`, `bad_type`, `no_station`, `no_homestead`, `homestead_error`, `no_remove`, `no_add`,
`not_enough` (see `server/craft.lua`).

## Server exports

| Export | Signature | Notes |
|---|---|---|
| `getRecipes` | `() -> list` | The `shared/recipes.lua` list (live table, not a copy). |
| `isNearStation` | `(src, stationType, maxDist?) -> boolean, reason\|nil` | H3 shape; delegate of `FhCraftStations.isNearStation`; reasons `bad_type`, `no_station`, `no_homestead`, `homestead_error`. |
| `getStations` | `(citizenid) -> list` | H3 shape; `fh_homestead` stations plus `devStations` (`dev = true`) while `fh_dev 1`. |
| `stationAt` | `(coords, maxDist?) -> { plot_id, slot_id, station_type }\|nil` | H3 shape; dev fallback `{ station_type, dev = true }`. |
| `craft` | `(src, recipeId) -> ok, reason, info` | Programmatic `/fh_craft`; reasons `no_player`, `busy`, `unknown_recipe`, `no_station` (+ station reason), `missing_inputs` (`info.missing`), take/give reasons (`no_remove`, `no_add`, `not_enough`, `fh_*`), `error`. |
| `invCount` | `(src, item) -> integer` | Equipped + backpack, via `fh_core` `snapshot`. |
| `invTake` | `(src, item, amount) -> ok, reason` | All-or-nothing across equipped then backpack; `bad_item`, `bad_amount`, `not_enough`, `no_remove`, `fh_*`. |
| `invGive` | `(src, item, amount, info?) -> ok, reason` | First carried section that takes the whole amount; `bad_item`, `bad_amount`, `no_add`, `fh_*`, `no_room`. |
| `invSlot` | `(src, slot) -> item\|nil` | Reads one carried slot (equipped slots first, then backpack). |
| `invSetInfo` | `(src, slot, info, expectName?) -> ok, reason` | `exports.fh_core:setItemInfo` on equipped then backpack (core-03); `expectName` refuses a swapped slot (`fh_wrong_item`); `no_set_info` only when fh_core lacks the export. |

Internal globals (not exports): `FhCraftStations` (`isNearStation`, alias `isNear`, `getStations`, `stationAt`),
`FhCraftInv` (`removeItem`, `addItem`, `count`, `take`, `give`, `slot`, `setInfo`), `FhCraft` (`craft`), `FhCraftFlow`,
`FhCraftRules`.

## Config keys (`config.lua`)

| Key | Shape | Meaning |
|---|---|---|
| `items` | table, item name -> definition | Registered at start (and again when `fh_core` restarts) through `exports.fh_core:registerItems`. `resource_gunpowder`, `ammo_box_revolver`, `ammo_box_rifle` and `herb_*` already exist in rsg-core and are not re-registered. |
| `TonicDurations` | table, tonic item -> seconds | `tonic_vigor = 600`, `tonic_steady = 300`. Read by `FhCraftRules.tonicFor`. |
| `devStations` | table, station type -> `{x, y, z}` | Dev-only fallback stations (`gunsmith` at `-280.0, 805.0, 119.0`, `reload` at `-283.0, 805.0, 119.0`, `apothecary` at `-286.0, 805.0, 119.0`, `cook` at `-289.0, 805.0, 119.0`), consulted only while convar `fh_dev = 1`. Placeholder coordinates: TODO verify in game. |
| `stationTypeMap` | table, crafting type -> H3 type | `gunsmith` and `reload` -> `workbench`, `apothecary` and `cook` -> `campfire`. Applied in `server/stations.lua` before every `fh_homestead` call (homestead only builds workbench/campfire/tanning_rack). |
| `stationMaxDist` | number | Default reach used by `isNearStation` / `stationAt` when no `maxDist` is passed (3.0). |
| `herbPatches` | list of `{ id, herb, coords, yield, respawnSeconds }` | 8 wild herb patches (2 per herb). Press E at a patch to pick: the server grants `yield` (1-2) of `herb` and starts a shared per-patch cooldown (`respawnSeconds`, in-memory, cleared on restart). Coordinates are `TODO-verify-in-game` placeholders. |

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
| `cook_meat` | `cook` | Cook meat | `raw_meat` 1 | `cooked_meat` 1 |
| `cook_stew` | `cook` | Cook stew | `raw_meat` 2, `carrot` 1, `potato` 1 | `stew` 1 |
| `cook_stew_veg` | `cook` | Cook vegetable stew | `carrot` 1, `potato` 1, `corn` 1 | `stew_veg` 1 |

The `cook` recipes use only rsg-core items (nothing registered here); fh_survival maps the three outputs to `well_fed`.
`raw_meat` is pending the @hunting skin grant (idea-914) and `carrot`/`potato`/`corn` the @roads supplies list (idea-915):
`spec/crafting_sources_spec.lua` tracks both in its PENDING set.
Recipe shape: `{ id, station_type, inputs = {{item, amount}}, outputs = {{item, amount}}, label }`, with
`station_type` in `gunsmith | reload | apothecary | cook` (gunsmith has no recipe; restore is `fh_gunsmith`). Invalid or
duplicate recipes are printed at start by `FhCraftRules.validateRecipes`.

## Restore caps (`shared/craft_rules.lua`)

Used by `fh_gunsmith`; `gun_parts` restores 20 quality each (`PART_VALUE`).

- Cap by star rating: 1 star = 60, 2 stars = 80, 3 stars = 100 (`STAR_CAPS`). Missing or invalid `stars` = 1 star;
  fractional ratings round and clamp to 1..3.
- Parts needed = `ceil((cap - quality) / 20)`, capped by the parts held; the result never passes the cap. An item
  already at or above its cap refuses with `at_cap`; no quality refuses `no_quality`; no parts refuses `no_parts`.

## Tonics (C4, `server/apothecary.lua`)

| Item / buff id | Magnitude | Duration |
|---|---|---|
| `tonic_vigor` | 1.15 | 600 s |
| `tonic_steady` | 1.10 | 300 s |

Both are registered as rsg-core usable items. Use order: remove one tonic -> `exports.fh_buffs:apply(src, buff_id,
magnitude, duration)`. The tonic is consumed only when the buff applies; on an apply failure the tonic is given back
(`buff_failed`); if the give-back also fails it is lost (`refund_failed`, logged at error level). Magnitude/duration
come from `FhCraftRules.tonicFor` (`TONICS` + `TonicDurations`).

## Adapter contract (signatures mirror @homestead H3 and @core B7)

| Global | Signature | Notes |
|---|---|---|
| `FhCraftStations.isNearStation` (alias `isNear`) | `(src, stationType, maxDist?) -> boolean, reason\|nil` | H3 shape; reasons `bad_type`, `no_station`, `no_homestead`, `homestead_error`. `fh_homestead` export when started; `devStations` only while `fh_dev 1` |
| `FhCraftStations.getStations` | `(citizenid) -> list` | H3 shape; dev stations appended (`dev = true`) under `fh_dev` |
| `FhCraftStations.stationAt` | `(coords, maxDist?) -> { plot_id, slot_id, station_type }\|nil` | H3 shape; dev fallback `{ station_type, dev = true }` |
| `FhCraftInv.removeItem` | `(ref, item, amount) -> ok, reason` | mirrors fh_core B7; `no_remove` when fh_core lacks the export |
| `FhCraftInv.addItem` | `(ref, item, amount, info?) -> ok, reason` | mirrors fh_core addItem; `no_add` when missing |
| `FhCraftInv.take` | `(src, item, amount) -> ok, reason` | all-or-nothing across equipped then backpack; `not_enough`, `bad_amount`, `no_remove` |
| `FhCraftInv.give` | `(src, item, amount, info\|nil) -> ok, reason` | first carried section that takes the whole amount |
| `FhCraftInv.slot` | `(src, slot) -> item\|nil` | |
| `FhCraftInv.setInfo` | `(src, slot, info, expectName?) -> ok, reason` | fh_core `setItemInfo` (core-03); `no_set_info` when the export is missing |

## Events

| Kind | Event | Payload |
|---|---|---|
| Emits (client) | `chat:addMessage` | `/fh_craft` and `fh:crafting:gather` replies: `{ args = { 'Crafting', msg } }` |
| Consumes (server) | `onResourceStart` | validates recipes and herb patches for this resource; re-registers items for this resource or `fh_core` |
| Consumes (server) | `playerDropped` | clears the per-player `busy` craft and gather flags |
| Consumes (server) | `fh:crafting:gather` | `patchId` (bare string) -> pick that patch (server decides reach, cooldown and grant; replies via `chat:addMessage`) |
| Registers | rsg-core usable items | `tonic_vigor`, `tonic_steady` -> `exports['rsg-core']:CreateUseableItem`; results go out via `exports['rsg-core']:Notify` |

The only custom net event is `fh:crafting:gather` (consumed by the server; nothing else is emitted).

## Herb gathering (C9)

Wild herb patches (plan crafting-02). Walk up, press E at the `[E] Pick <Herb>` prompt, a ~4 s progress bar plays, and
the server grants 1-2 of the patch's herb into your backpack. The server decides everything: your position comes from
`GetPlayerPed` + `GetEntityCoords` (never client coords), reach matches `FhContainers.canReach` (3.5 m, pure rules in
`shared/gather_rules.lua`), and the grant goes through the fh_core carried `addItem` on a backpack ref. Each patch has a
**shared, per-patch** cooldown (`respawnSeconds`, 900 by default, held in server memory and cleared on restart): a patch
is shared frontier, so everyone waits on the same regrowth. Patches are invisible except for the `[E]` prompt (a plant
prop/blip is a queued `spk_herb` spike); find them by the `herbPatches` coordinates in `config.lua` (`TODO-verify-in-game`).
The herbs stay buyable at trade posts (idea-716/719); gathering is a free, slower second source.

## Pending contracts

None. All previously-pending contracts are on main:

- **@homestead H2 `/fh_build`** (on main): stations are real (H3 on main) and built on your own plot. Crafting types map
  to homestead types through `stationTypeMap`. Before the homestead slot load finishes, H3 returns
  `{}` / `nil` / `false` / `'fh_not_ready'`; all read as `no_station`. `isNearStation` is owner-only (own plot), so
  crafting works only on the player's own plot. `/fh_restore` reach reads `getStations(citizenid)` filtered to
  `workbench` and compares coordinates with the open container. `stationAt` returns the raw H3 type (`workbench`), not
  the crafting type.
- **@roads idea-716/719** (on main): trade post `supplies` sells all 9 buy items: `lumber`, `nails`, `lead`, `casings`,
  `resource_gunpowder`, `herb_american_ginseng`, `herb_oregano`, `herb_red_sage`, `herb_wild_mint`.
- **@core idea-717** (on main): `gun_parts` drops from the outlaw camp loot table (`fh_zones/config.lua`).

Resolved: idea-612 (`fh_buffs` caps `tonic_vigor` 1.15 / `tonic_steady` 1.10 on main; `TONICS` equal the caps, and
`fh_buffs` validate does not reject magnitude == cap); core-03 carried `addItem`/`removeItem` (refs `{ type = 'backpack'|'equipped', id = src }`; idea-615) and
`setItemInfo(ref, slot, info, expectName)` (idea-689); B7 `removeItem`.
