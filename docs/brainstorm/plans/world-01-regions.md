# world-01 · real places (World Buddy, 2026-11-24)
Owner (via Red3): "push whatever you need, get as much done for me to try when home". Owner at work; leans taken per R13.
Owner/hub (via RiffBot): two home classes (town lots vs wilderness claims), 15 regions, 8 original factions, coords ground-snapped + tagged unverified, /where as the fix-up tool, move the Valentine camp off the plots.

Goal tonight: when Aub logs in, homestead plots are **real, named countryside sites**, not the 150 m grid inside Valentine; camps and trade posts sit at believable spots in every enabled region; all 15 regions exist as data.

## Blocks
| Block | Touches | Clashes with | Kind |
|---|---|---|---|
| A Region map + factions | fh_core/shared/regions.lua (+ its spec) | B, C (read A's ids) | Root cause |
| B Real claim sites | fh_homestead/config.lua plots (+ spec), fh_tutorial/shared/tutorial.lua:30 waypoint | A (region ids) | Root cause (coords unverified = Workaround → follow-up D + owner /where) |
| C Camps + trade posts | fh_zones/config.lua camps, fh_trade/config.lua posts, regions.lua territories | A (same file), B (distance from plots) | Root cause |
| D Ground-snap + enabled gate | fh_ui blips client, /where, homestead chest/prop spawn client, fh_zones camp spawn | B, C (reads their data) | Root cause |
Order: A first (small, ~1h), then B + C in parallel, then D. One worktree per block or one serial worker; lead's call.

### A · Region map + factions
- All 15 regions in `regions.regions` (no Guarma): heartlands, scarlett_meadows (fold in as-is from d3184a6/cb2403d), bayou_nwa, bluewater_marsh, roanoke_ridge, grizzlies_east, grizzlies_west, cumberland_forest, big_valley, great_plains, tall_trees, hennigans_stead, cholla_springs, gaptooth_ridge, rio_bravo. Each gets `state` (new_hanover/lemoyne/ambarino/west_elizabeth/new_austin), `towns` list (id, label, x, y, z-hint), `enabled`.
- `enabled = true` tonight for heartlands, scarlett_meadows, bayou_nwa (Saint Denis), great_plains (Blackwater); these have verified spawn anchors in rsg-character/shared/config.lua:200-203. The other 11: `enabled = false`, data present.
- 8 factions. **Keep existing ids** (26 references in server/spec), relabel and add: `lawmen` (per-state label skin via region.state), `rail_mining` (rail + mining company), `settlers` (settlers' league), `traders` (traders' guild), `bounty_hunters`, `raiders` → swamp gang (Lemoyne), `outlaws` → mountain gang (north), `desert_gang` (New Austin). `rhodes_law` stays as an alias that resolves to `lawmen` (do not delete; fh_heat rows may be keyed on it). Names are original, no RDR2 gang/company names.
- Shape: factions keep `{id, label}`; optional new fields only: `kind = 'law'|'outlaw'|'neutral'` (A-Life reads it for hostility; lawmen/rhodes_law=law, the 3 gangs=outlaw, rest=neutral), `skins`, `alias_of`. `regions[id].factions` lists the region's factions; `territories[id].faction` = default camp owner (A-Life contract, a-life-01). If the lead finds this changes the §4.4 contract, send a contract request to @core instead of redefining it.
- Done-check: regions spec covers 15 regions, 8 factions + alias, isKnownRegion for all 15; existing specs green.

### B · Real claim sites (replaces fh_homestead/config.lua:81-108 grid)
- 3-5 **wilderness claims** per enabled region (≈15 total tonight), each with a `name` ("Cotorra Bend claim" style, original), `class = 'claim'`, countryside, ≥150 m from any town center and ≥150 m from each other, near water/timber where the map allows. x/y from map knowledge, z = hint, `verified = false`.
- **Keep plot ids heartlands_01..04 / scarlett_meadows_01..04** (DB keys in fh_plots); move their coords, add new ids for extras.
- 1-3 **town lots** per enabled region as data only: `class = 'town_lot'`, ~12-15 m radius, `claimable = false` until @homestead lands the schema (see Out of scope). Show on /where as "Town lot (coming soon)" or hide; lead's call.
- Update fh_tutorial waypoint (tutorial.lua:30) to the nearest Heartlands claim.
- Done-check: no plot within 150 m of a town center or of a camp; homestead specs green; /where lists the named claims.

### C · Camps + trade posts
- 3-4 outlaw **camps** per enabled region (≈14 tonight), owned by the region's gang faction, tier T1-T2, `verified = false`. Move heartlands_t1_camp off the plots (it is ~55 m from plots 2/4, fh_zones/config.lua:11). Camps ≥200 m from any claim and any town.
- fh_zones camps keep id/region/territory/center/activationRadius/peds/loot (A-Life reads them; it adds optional `lootByFaction`).
- Optional if time allows: `regions[id].ambush = { {x,y,z}, ... }`, 2-3 road points per enabled region, unverified (A-Life v2 nodes).
- 1-2 **trade posts** per enabled region (fh_trade/config.lua:39), town-adjacent.
- Single source: fh_zones camps and fh_trade posts read positions from FhRegions territories/posts (fh_economy already loads regions.lua via its manifest; same pattern). If that's too big tonight, keep duplicates and log a `vs task` to collapse them (named Workaround).
- Done-check: zones/trade/heat specs green; a spec asserts camp↔claim↔town spacing.

### D · Ground-snap + enabled gate
- Client snaps z for blips, chest/prop spawns and camp spawns via ground-height probe at runtime (probe only once the area has streamed in; fall back to z-hint and log `fh:world:unsnapped <id>`).
- `enabled = false` regions: no blips, no /where entries, no camp spawns, not offered by /jobs region pick.
- /where (2436bc6) shows `(unverified)` next to unverified entries, so the owner can stand there and report fixes. No new survey command (checked: /where already covers it).
- Done-check: specs for the enabled gate; syntax check green; OWNER-TESTS.md gets a "walk the claims" checklist.

## Decided
- Checked existing primitives: fh_core regions §4.4 registry (extend, don't fork), fh_homestead plots, fh_zones camps, fh_trade posts, /where + blips (fh_ui, 2436bc6). No new command added.
- Plots stay owned by fh_homestead/config.lua (DB ids); regions.lua owns regions/towns/factions/territories/posts.
- Specs only via `~/.venvs/rf/bin/python tools/run-specs.py`.
- Lead commits on a branch/worktree; merge to main only in Red3's merge slot (ask Red3 or its successor).

## Out of scope (Open in docs/brainstorm/world.md)
- Town-lot purchase + one lot AND one claim per character (fh_plots.citizenid UNIQUE): schema change → @homestead.
- Content ladder: 8 contract types, +2 family questlines, 15 legendaries, faction loot tables → @quests/@hunting/@crafting.
- Raids on claims → @alife.
- Enabling the other 11 regions (after the owner walks the first 4).
