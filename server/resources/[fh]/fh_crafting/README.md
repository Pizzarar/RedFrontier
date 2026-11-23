# fh_crafting (spec L5)

Reload press and apothecary recipes, plus the station and inventory adapters that `fh_gunsmith` (C3) calls.
Pure rules live in `shared/craft_rules.lua` (global `FhCraftRules`; load from another resource with
`'@fh_crafting/shared/craft_rules.lua'`). Recipes: `shared/recipes.lua`. Config: `config.lua`.
Server flow (C2): `/fh_craft <recipe>` = station check -> canCraft -> remove inputs -> add outputs, all-or-nothing;
any failed step undoes the applied ones newest-first (pure: `shared/craft_flow.lua`, spec `spec/crafting_flow_spec.lua`).
An undo that fails is logged as `ROLLBACK INCOMPLETE` with what was not undone.

## Adapter contract (workaround until C5; signatures mirror @homestead H3 and @core B7 so C5 swaps bodies only)
| Global | Signature | Notes |
|---|---|---|
| `FhCraftStations.isNearStation` (alias `isNear`) | `(src, stationType, maxDist?) -> boolean, reason\|nil` | H3 shape; reasons `bad_type`, `no_station`. fh_homestead export when started, plus `devStations` while `fh_dev 1` |
| `FhCraftStations.getStations` | `(citizenid) -> list` | H3 shape; dev stations appended (`dev = true`) under `fh_dev` |
| `FhCraftStations.stationAt` | `(coords, maxDist?) -> { plot_id, slot_id, station_type }\|nil` | H3 shape; dev fallback `{ station_type, dev = true }` |
| `FhCraftInv.removeItem` | `(ref, item, amount) -> ok, reason` | mirrors fh_core B7; `no_remove` when fh_core lacks the export |
| `FhCraftInv.addItem` | `(ref, item, amount, info?) -> ok, reason` | mirrors fh_core addItem; `no_add` when missing |
| `FhCraftInv.count` | `(src, item) -> integer` | equipped + backpack, via fh_core `snapshot` |
| `FhCraftInv.take` | `(src, item, amount) -> ok, reason` | all-or-nothing across equipped then backpack; `not_enough`, `bad_amount`, `no_remove` |
| `FhCraftInv.give` | `(src, item, amount, info\|nil) -> ok, reason` | first carried section that takes the whole amount |
| `FhCraftInv.slot` | `(src, slot) -> item\|nil` | |
| `FhCraftInv.setInfo` | `(src, slot, info) -> ok, reason` | refuses `no_set_info` (no fh_core contract yet) |
| `FhCraft.craft` | `(src, recipeId) -> ok, reason, info` | `/fh_craft <recipe>`; reasons `busy`, `unknown_recipe`, `no_station`, `missing_inputs` (+ `info.missing`), take/give reasons |

Known gap: fh_core B7 `removeItem`/`addItem` refuse carried refs (`fh_not_registrable`), so crafting refuses cleanly until
@core ships a carried-inventory contract (C5 swaps to it).

## Server exports
`getRecipes()`, `isNearStation(src, type, maxDist?)`, `getStations(citizenid)`, `stationAt(coords, maxDist?)`,
`craft(src, recipeId)`, `invCount`, `invTake`, `invGive`, `invSlot`, `invSetInfo`.
