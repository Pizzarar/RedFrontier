# fh_crafting (spec L5)

Reload press and apothecary recipes, plus the station and inventory adapters that `fh_gunsmith` (C3) calls.
Pure rules live in `shared/craft_rules.lua` (global `FhCraftRules`; load from another resource with
`'@fh_crafting/shared/craft_rules.lua'`). Recipes: `shared/recipes.lua`. Config: `config.lua`.
Server flow, apothecary handlers and the in-game test card come with C2-C6.

## Adapter contract (workaround until C5)
| Global | Signature | Notes |
|---|---|---|
| `FhCraftStations.isNear` | `(src, stationType) -> boolean, reason\|nil` | reasons `bad_type`, `no_station`; fh_homestead `isNearStation`, else `devStations` when `fh_dev 1` |
| `FhCraftInv.count` | `(src, item) -> integer` | carried inventory |
| `FhCraftInv.take` | `(src, item, amount) -> ok, reason` | all-or-nothing; `not_enough` |
| `FhCraftInv.give` | `(src, item, amount, info\|nil) -> ok, reason` | `no_room` etc. |
| `FhCraftInv.slot` | `(src, slot) -> item\|nil` | |
| `FhCraftInv.setInfo` | `(src, slot, info) -> ok, reason` | |
| `FhCraft.craft` | `(src, recipeId) -> ok, reason` | `/fh_craft <recipe>` |

## Server exports
`getRecipes()`, `isNearStation(src, type)`, `invCount`, `invTake`, `invGive`, `invSlot`, `invSetInfo`.
