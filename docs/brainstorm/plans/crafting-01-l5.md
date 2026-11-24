# Plan crafting-01 · L5 gunsmith + crafting (`fh_gunsmith`, `fh_crafting`, lane @crafting)

## Idea
Worn weapons carry condition as item data. Parts restore them at a gunsmith bench. A reloading press turns
components into ammo, and an apothecary turns herbs into tonics that apply fh_buffs. Stations come from
@homestead's station-slot API. Spec: docs/FRONTIER_HOMESTEAD_SPEC.md §5 L5, M2 ("Restore the looted rifle at a
bench; craft ammo; apothecary tonic").

## Owner's words (verbatim, from lane brief)
"build everything autonomously, Aub tests only at the end." Use @core §4 APIs only; contract changes = request to
@core. Anything waiting on in-game spike results goes behind one config flag. Pure-Lua specs (tools/run-specs.py) +
in-game test card. No push.

## Decided
- Checked primitives: fh_core FhItems.condition/stars (fh_core/shared/items.lua:132), fh_core `addItem` export
  (server/inventory.lua:362), fh_buffs `apply(src, buff_id, magnitude, duration)`/`get` (fh_buffs/server/main.lua:31),
  fh_buffs caps whitelist (fh_buffs/config.lua:5), `fh_spike_gated` convar (fh_core/docs/spike-gated.md), Homestead
  H3 station contract (plans/homestead-01 row H3), core B7 `removeItem` (plans/core-02). No new flag, no new command
  framework: one `/fh_craft` server command + fh_ui relay hook later.
- Crafting costs materials only. No money fee (money enters via buying parts at the fence/shop, which is out of scope).
- Restore cap: condition max = 60 / 80 / 100 for quality 1/2/3 stars (no stars = 1 star). Each `gun_parts` gives +20.
- Visual wear (applying condition to the real weapon degradation native) sits behind `fh_spike_gated`: while it's
  true, condition is data only and is shown in the item label/tooltip.
- Recipes are pure-Lua data tables in `fh_crafting/shared/recipes.lua`; station_type in {gunsmith, reload, apothecary}.

- 2026-11-23 Restore source (lead ask, rifle is `bulky`, carried slots refuse bulky per fh_core/shared/containers.lua:11-12): `/fh_restore` acts on the world container the player has OPEN (`exports.fh_core:openRef(src)` + `view`, fh_core/server/inventory.lua:351; same pattern as saddlebag.lua:110) when that container is within reach of a gunsmith station and its type accepts bulky (chest/wagon/saddlebag). Write-back via @core setItemInfo on that ref. Checked: openRef/view exist; no H3 stash API (git grep c3d0dd2 fh_homestead chest|stash = 0), so no new homestead contract. Rejected (a) weapon slot = new core feature; (c) un-bulky = breaks spec size classes. Folds into C5.

- 2026-11-23 H3 on main (2a7d98a, main fad2417). Homestead station types are workbench/campfire/tanning_rack (fh_homestead/config.lua:29-40); crafting uses gunsmith/reload/apothecary (fh_crafting config devStations). Crafting owns a `stationTypeMap` in fh_crafting/config.lua: gunsmith→workbench, reload→workbench, apothecary→campfire. No homestead change. Adapter treats fh_not_ready/{}/nil/false as "no station" (README:29). isNearStation is owner-only (README:40), so crafting is home-only, which fits. Restore's container-reach check uses getStations(citizenid) coords.

- 2026-11-23 idea-712 material sources ruling (C8). lumber, nails, lead, casings: BUY at fh_trade posts through a new `supplies` buy list, owned by @roads (fh_trade is sell-only today, server/main.lua:143). gun_parts: LOOT only, added to the outlaw camp loot table in fh_zones/config.lua (owner @core, B6b), so restore stays tied to the M2 raid loop. Gathering (tree chopping) is out of scope: it would be an additive spike later, not a replacement, so buying is the root source, not a workaround. Crafting does not edit fh_trade or fh_zones. C8 in-lane = a spec that every recipe input and homestead station cost has a source + an OWNER-TESTS update. Checked: no [rsg] shop resource, fence stock is illicit-only (fh_fence/config.lua:30), fh_trade has no buy side.

- 2026-11-23 idea-718 ruling: resource_gunpowder and herb_american_ginseng/oregano/red_sage/wild_mint (rsg-core items only, no gatherer in repo) = BUY, added to the same @roads `supplies` list (idea-716). One shop surface for all bought inputs. Herb gathering is parked as an additive spike (inbox), not a replacement.

## Contracts / stubs
- **@homestead H3** (in review, c3d0dd2): `isNearStation(src, type)`, `getStations(citizenid)`, `stationAt(coords)`.
  `fh_crafting/server/stations.lua` adapter calls it when `GetResourceState('fh_homestead')=='started'` and the export
  exists. Otherwise it falls back to config `Config.devStations` (coords per type) gated by `fh_dev`. Kind: Workaround →
  removed by block C5.
- **@core B7** `removeItem(ref, item, amount)` (not on main yet). Until it lands the adapter uses the existing rsg
  inventory remove inside fh_core helpers only if an fh_core export exists; otherwise crafting refuses ('no_remove')
  and specs cover the pure path. Kind: Workaround → C5.
- **@core caps request**: add `tonic_vigor` (1.15) and `tonic_steady` (1.10) to fh_buffs/config.lua caps (config
  only, no API change). Before that lands, `apply` returns an error and the tonic is not consumed. Kind: Root cause
  (request sent to @core inbox).

## Blocks
| Block | Touches | Clashes with | Kind |
|---|---|---|---|
| C1 fh_crafting skeleton + pure rules: `shared/recipes.lua`, `shared/craft_rules.lua` (canCraft(inv, recipe), outputs, restore math with star caps), item registration for gun_parts, powder, lead, casings, herbs, ammo items, tonic_vigor, tonic_steady via fh_core item registry; specs | new fh_crafting/, spec/crafting_*, server.cfg ensure line | server.cfg (other lanes add ensures; append only) | Root cause |
| C2 station adapter + `/fh_craft <recipe>` server flow: isNearStation check → canCraft → remove inputs → add outputs, all-or-nothing with rollback; dev-station fallback | fh_crafting/server | none (consumes H3, B7) | Workaround (adapter fallback) → C5 |
| C3 fh_gunsmith restore: `/fh_restore <slot>` at gunsmith station, consumes gun_parts, raises info.condition to the star cap; `fh_spike_gated` false → client applies weapon degradation native (native verified in fh_core/docs/natives.md, else stays data-only and logs it) | new fh_gunsmith/ | fh_core/docs/natives.md (append only) | Root cause |
| C4 apothecary: tonic use handler → fh_buffs.apply(tonic_*), consume only on success; specs | fh_crafting | @core caps request | Root cause |
| C5 swap to the real contracts once H3 + B7 are on main: delete dev-station fallback path from default flow (keep behind fh_dev), use B7 removeItem; specs on the adapter | fh_crafting/server/stations.lua | waits for H3 + B7 merges | Root cause (replaces C2 workaround) |
| C6 README (exports/events/config) + Crafting section in OWNER-TESTS.md: loot worn_rifle → build gunsmith station → restore → craft ammo → drink tonic, buff visible | READMEs, OWNER-TESTS.md | other lanes' OWNER-TESTS sections (own section only) | Root cause |

Parallel: C1 first. Then C2, C3 and C4 can run in parallel (C3 and C4 depend only on C1 rules + the C2 adapter
signature, so the lead defines the adapter signature in C1). C5 starts after H3 and B7 merge, and C6 comes last.

## Integration rules (Overlord)
Work only in `vs worktree create` units. Review PASS → rebase on current main → `python tools/run-specs.py` all green →
merge to local main → log the hash. One lane merges at a time (rebase again if main moves). No pushes. When done:
`vs log decision "crafting playtest-ready <hash>"`.

## Done-check
All blocks merged on local main, specs green, OWNER-TESTS Crafting section present, playtest-ready logged.

## Out of scope
Selling parts/ammo (shop/fence = @roads/@progression), weapon wear accrual from firing (later), station placement/props
(@homestead), NUI screens (@ui; we ship data + commands), crafting skill/XP.
