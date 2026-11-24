# Plan survival-02 · Food you can find, fire you own

Lead: Sur2 (`vs who lead` → rn-9bba3824750e). Buddy: Survival. 2026-11-24.

## Why
survival-01 shipped the needs loop, but feeding it is thin:
- The only food that feeds `well_fed` is fh_jerky/fh_biscuit/fh_stew, and those only drop from settler camps (`fh_zones/config.lua:1253-1278`). Other camp loot (bread, canned_beans, canned_apricots, canned_salmon, coffee) and the rsg-core foods (`cooked_meat`, `stew`, `stew_veg`, `jerky_meat` at `rsg-core/shared/items.lua:93-120`) don't feed any need. No `[fh]` resource consumes them.
- `exports.fh_survival:setHeatSource` (`fh_survival/server/actions.lua:153`) has no callers. A player's own homestead campfire (`fh_homestead/config.lua:37`, stationType `campfire`) does not warm them. Only two seeded coords do.
- Hunting grants pelts only, and fh_crafting has no campfire station or food recipes. Cooking is a cross-lane matter, so it is routed out of this plan (see below).

## Owner / Overlord words (verbatim)
Red3: "Keep your lane working its goals: no parking without a real blocker... Buddy: if your lead has no plan, riff the next one from your SPEC Done-when gaps and hand it over this hour."
Sur2 lean: "survival-02 = (3)+(2) (code-only, spec-testable), (1) as a single owner-card spike."

## Decided
- I take Sur2's lean, scoped to what this lane owns. (3) cooking means fh_crafting recipes plus fh_hunting meat, which belong to @crafting and @hunting. I'm sending those to their inboxes. This lane does the eat side: a data map of food and drink items, so anything they ship later only needs a table row.
- (2) Coords: no new data source. The owner verifies coords through the card. The real fix is owned fires: homestead campfire stations become heat sources through the existing `fh_homestead` exports (getStations / isNearStation; @survival already calls these after S4b). No new export.
- (1) Natives: a single owner-card step. The default flips only after the owner reports PASS (separate tiny follow-up, not in this plan).
- (5) The sluggish HUD is routed to @ui. (4) Cold regions stay Open until @world adds a cold region.
- Primitives I checked: `exports.fh_survival:setHeatSource` (exists, unused); `fh_homestead` getStations/isNearStation (exist); the fh_core registerItems / S3 `I.ITEMS` path (exists); fh_crafting `getStations` (wraps homestead). I add no command, export or migration.

## Plan (order + done-check)
| Block | Touches | Clashes with | Kind |
|---|---|---|---|
| F1 food/drink map | `fh_survival/shared/items.lua` (or a new `shared/foods.lua`), `server/actions.lua` use handlers, config, specs | Any rsg consumable resource that already registers these items as useable: the lead checks first. If one does, hook its use event instead of re-registering. | Root cause |
| F2 owned campfire = heat | `fh_survival/server/actions.lua` warm check, config | @homestead stations (read-only use of exports) | Root cause |
| F3 owner card steps | `OWNER-TESTS.md ## Survival` | other lanes' OWNER-TESTS sections (append only to Survival) | Root cause |

Order: F1 || F2, then F3.

- **F1**: Add a data table `item → { need, fraction, magnitude? }` that covers the existing fh_* foods and the rsg-core/loot foods: bread, canned_beans, canned_apricots, canned_salmon, cooked_meat, stew, stew_veg, jerky_meat → well_fed; coffee (and any rsg water/drink item the lead finds) → hydrated. Use the existing S3 consume path (remove 1 → apply buff, refuse/refund on failure, same as the 68ab3ef fix). Rows for missing items are skipped silently, so @crafting/@hunting items are one-row adds later. Done-check: specs cover the map (every row's item exists in the registry or is skipped; the fractions match the jerky/biscuit/stew scale; a failed remove grants no buff). Venv specs show 0 fail / 0 load errors.
- **F2**: In the warm tick, a player within `HeatRadius` of a homestead station of type `campfire` they own (or on their plot) gets `warm`, alongside the seeded Campfires. Gate it with GetResourceState like S4b. Done-check: specs with a stubbed homestead export (owned fire → warm, no fire → none, fh_homestead stopped → seeded fires still work).
- **F3**: Card steps: eat bread/canned beans → `well_fed`; place a homestead campfire and stand at it → `warm`; **natives spike**: set `WaterCheck='native'` and `/refill` in the river, then set `SluggishEffect='native'` and note whether stamina/regen changes. The owner also records corrected WaterZones/Campfires coords if they're off. Done-check: card merged; log `survival playtest-ready <hash>`.

Merge: per-block review PASS → rebase → venv specs green → merge slot via Red3 → log the hash. No pushes.

## Routed out (sent, not in this plan)
- @crafting: a `campfire` station_type plus cooking recipes (meat → cooked_meat, meat+veg → fh_stew/stew). Use fh_homestead's campfire station.
- @hunting: carcass skinning also grants a raw meat item (needs an item: rsg-core has none). Feeds @crafting cooking.
- @ui: HUD consumer for `fh:survival:state` sluggish level + active needs.

## Open
- Cold regions: wait for @world to add a cold region id, then a one-line `ColdRegions` add.
- Native default flip: after the owner's F3 PASS, a tiny follow-up sets `WaterCheck`/`SluggishEffect` defaults.

## Out of scope
Cooking recipes, meat items and HUD work (other lanes). Debuff-id alternative (deferred, @core). Lethal anything.
