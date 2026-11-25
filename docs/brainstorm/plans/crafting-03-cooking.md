# crafting-03 · Campfire cooking (idea-852)

## Idea
Add cooking recipes at the homestead campfire: raw meat → cooked meat, meat + veg → stew, veg → vegetable stew. @survival already turns the outputs into `well_fed`. This connects hunting → crafting → survival.

## Owner's words (verbatim)
Overlord relay 2026-11-24: "Keep your lane working its goals: no parking without a real blocker." Card idea-852 (from @survival): campfire station_type + cooking recipes (raw meat -> cooked_meat, meat+veg -> stew; survival maps cooked outputs to well_fed).

## Decided
- Outputs are rsg-core items, so crafting doesn't register them: `cooked_meat` (rsg-core/shared/items.lua:93), `stew` (:118), `stew_veg` (:120). Survival already maps all three to well_fed (fh_survival/shared/items.lua:33-35,48). No survival change.
- Inputs are rsg-core items: `raw_meat` (:151), `carrot` (:89), `potato` (:149), `corn` (:141). Nothing in `[fh]` grants them today (grep raw_meat|carrot|potato|corn in [fh] = config comment + UI fixture only).
- New crafting station type `cook`, with `stationTypeMap.cook = 'campfire'` (fh_crafting/config.lua:32). The map is already many-to-one (gunsmith+reload → workbench), so apothecary and cook both on campfire is fine. A separate type keeps the cooking and tonic recipe lists apart in UI and specs. No homestead change.
- Recipes (fh_crafting/shared/recipes.lua):
  - `cook_meat` (cook): raw_meat 1 → cooked_meat 1
  - `cook_stew` (cook): raw_meat 2 + carrot 1 + potato 1 → stew 1
  - `cook_stew_veg` (cook): carrot 1 + potato 1 + corn 1 → stew_veg 1
- Sources (ruling, same approach as idea-712/718):
  - raw_meat = **skinning grant** from @hunting: skinning an animal also grants raw_meat (1-3, by animal size) using the same GrantOrder (fh_hunting/config.lua:19). Fits the fiction, and it's the only raw_meat source.
  - carrot, potato, corn = **BUY** through the @roads supplies list (idea-716/719). Homestead farming (rsg seedcarrot/seedpotato/seedcorn exist, :185-191) is parked as a later additive idea.
- Checked primitives: existing recipe engine + stationTypeMap (C7), C8 sources spec with PENDING set, rsg-core items, survival food map. No new command, flag or resource.

## Blocks
| Block | Touches | Clashes with | Kind |
|---|---|---|---|
| C10a `cook` type in the recipe station enum + `stationTypeMap.cook='campfire'` + 3 recipes + specs (canCraft for each, map resolves cook→campfire). C8 sources spec: raw_meat PENDING @hunting card, carrot/potato/corn PENDING @roads card; outputs need no source entry | fh_crafting/shared/recipes.lua, fh_crafting/config.lua (append only), spec/crafting_* | none (C9 merged) | Root cause |
| C10b README recipe table + Crafting OWNER-TESTS card: build campfire, cook raw_meat → cooked_meat, eat → Well Fed in the HUD; stew with bought veg | fh_crafting/README.md, OWNER-TESTS.md (Crafting section only) | other lanes' OWNER-TESTS sections | Root cause |

Order: C10a → C10b. Done-check: venv specs green, Gemini review PASS, merge via the Red3 slot. Live playtest still needs the @hunting and @roads contracts; the spec PENDING set tracks them, so merging isn't blocked.

## Open
- @hunting contract: raw_meat on skin (card sent).
- @roads: carrot, potato, corn added to the supplies list (card sent).
- Later idea: homestead farming plots for veg (parked).

## Lead
Cra2 (rn-ba5485686a96).

## Out of scope
Meat spoilage (fh_inventory decay config, survival/core), cooking animations/props, cooking quality or skill, farming.
