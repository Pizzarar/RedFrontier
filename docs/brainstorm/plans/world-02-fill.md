# world-02 · fill the map (World Buddy, 2026-11-24)
Owner (via Red3): "push whatever you need, get as much done for me to try when home". Follows world-01 (on main d966dcf).

## Blocks
| Block | Touches | Clashes with | Kind |
|---|---|---|---|
| E lootByFaction 8x3 | fh_zones/config.lua camp loot (A-Life's optional `lootByFaction`), loot spec | @a-life (reads it), G (new camps) | Root cause |
| F Single source for camp/post coords (idea-809) | fh_zones/config.lua, fh_trade/config.lua, fh_core/shared/regions.lua territories/posts, their specs | E, G, @a-life (camp fields) | Root cause (replaces world-01 C workaround) |
| G Data for the 11 disabled regions | regions.lua towns/territories/posts/ambush, fh_homestead/config.lua plots | F (same tables), E | Root cause (coords unverified → owner /where, then flip enabled) |
Order: F first (shape), then E + G in parallel.

### E · Loot tables
- One loot table per faction (8) x tier (T1-T3) using existing items only; gangs richer in contraband, lawmen/traders in ammo/money. Desert gang gets one (today it falls back to camp loot).
- Done-check: every camp's owner faction resolves to a table for its tier; A-Life specs green.

### F · Collapse duplicates
- fh_zones camps and fh_trade posts derive center/region/faction from FhRegions; their configs keep only gameplay fields (peds, loot, activationRadius, radius). Keep every field A-Life reads (id/region/territory/center/activationRadius/peds/loot/lootByFaction).
- Done-check: no camp/post coordinate defined in two places (grep spec); zones/trade/heat/alife specs green.

### G · Other 11 regions
- Per region: 3-5 claims, 1-3 town lots (claimable per @homestead H10 rules), 3-4 camps, 1-2 posts, 2-3 ambush points. All verified=false, region stays enabled=false. Original names only, no RDR2 named places for camps/claims. Same spacing rules (claim↔town ≥150 m, camp ≥200 m from claims/towns).
- Done-check: spacing spec covers all 15 regions; enabling a region is a one-line flip.

## Decided
- Checked primitives: FhRegions §4.4 registry, fh_zones camps, fh_trade posts, A-Life lootByFaction field (a-life-01). No new command.
- Merge via Red3's merge slot; specs via ~/.venvs/rf/bin/python tools/run-specs.py.

## Out of scope
- Enabling the 11 regions (after the owner walks the first 4). Town-lot purchase (@homestead H10). Contracts/questlines/legendaries (@quests/@hunting).
