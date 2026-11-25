# hunting-02 · Legendary ladder (idea-840, goes with idea-839)

## Idea
Grow the one Legendary Bear into 15 original legendary animals, one per FhRegions region. Each entry is data, and a disabled region shows nothing. The bear becomes entry 1 (heartlands).

## Words (verbatim)
- Hub/accepted idea-840: "Content ladder (hub lean): 15 original legendary" (goes with idea-839)
- Hun2 (2026-11-24): "one per FhRegions region (11 regions currently enabled=false) ... original names/looks only ... Pattern to copy: docs/brainstorm/plans/quests-02-content-ladder.md (per-region data split + FhRegions.isEnabled gate) ... Lean: B1 = generalize the chain/legendary into a data-driven per-region table (the bear becomes entry 1) with the isEnabled gate; B2..Bn = content batches of ~5 legendaries each (data, items, trophies, OWNER-TESTS), which can run in parallel after B1."
- Red3 (Overlord): "keep your lane working its goals ... riff the plan with Hun2."

## Decided
- **Primitives checked (no new cross-lane API):** `FhRegions.isEnabled` (fh_core/shared/regions.lua:721, used by quests C0 378971c); fh_core `requestSpawn`/`despawn`/`requestOfNetId` (H4/H7); the chain state machine in fh_hunting/shared/chain.lua (it already emits `chain_id` in every payload: lines 171, 206, 221, 249); the DB table `0010_fh_hunting.sql`, which is already keyed `(citizenid, chain_id)`, so **no migration is needed**; `getTrophyComfort` (shared/trophies.lua); `nearestWagon`/`getWagon` (@roads, on main). vs/VS MCP: no new command or rule.
- **15 regions** (fh_core/shared/regions.lua): heartlands, scarlett_meadows, bayou_nwa, great_plains (enabled), plus bluewater_marsh, roanoke_ridge, grizzlies_east, grizzlies_west, cumberland_forest, big_valley, tall_trees, hennigans_stead, cholla_springs, gaptooth_ridge, rio_bravo (disabled). The Legendary Bear stays heartlands' entry, so there are **14 new entries**.
- **Data shape (Buddy lean, R13):** one file per region, `fh_hunting/data/legendaries/<region_id>.lua`, returning `{ id, label, species_model, outfit, scale, pelt{item,label,value,weight,image}, trophy{item,label,comfort}, rumour{coords,price,label}, markers{[2],[3]}, spawn{coords} }`. `animals.lua` and `trophies.lua` derive their legendary rows from these files, so batch blocks never edit shared tables and can run in parallel.
- **Rumour point per legendary (Buddy lean):** each entry has its own rumour point in its region (coords + price). The bear keeps the heartlands trapper coords. This avoids crossing the map to one trapper and keeps each region self-contained.
- **Identity:** a legendary is identified by the chain's adopted spawn (the existing H4 tag `fh_hunting:<chain_id>:<cid>`), never by its model alone. Several legendaries share base models with plain animals. `animals.get(model, legendary)` takes a legendary **id** instead of a boolean. A boolean `true` still maps to `legendary_bear` for compatibility.
- **Concurrent chains allowed:** state, cache and busy guards are keyed `(cid, chain_id)`. One spawn per chain per character, as today.
- **Gate:** if a region is disabled, its rumour, markers and spawn refuse with `fh_chain_region_closed`, and the client shows nothing there. Flipping `enabled` turns the entry on with no code change. A chain already in progress in a region that gets disabled later freezes in place; it is not reset.
- **Events (additive only):** the existing `fh:hunting:clue_found|legendary_spawned|chain_complete` payloads also carry `region_id` and `legendary` (the entry id). `pelt_skinned`/`pelt_sold` keep their shape, and `animal` = the legendary id. Tell @quests and @guide when B1 merges (FYI only, nothing breaks).
- **Original content:** names, labels and descriptions are original. No real-world, film or game legendary names, and no copying of any game's legendary roster. Looks come from base species models plus an outfit/tint preset and a scale, not from vanilla legendary model names. Builders choose names inside their batch. No plugin or parity inspiration, so no Credits line.
- **All legendaries are cargo pelts, 3★ fixed**, and use the existing wagon path (8 m). Trophies are bulky, comfort 25 each for v1 (tuning is Open).
- Rules: specs-first; specs only via `~/.venvs/rf/bin/python tools/run-specs.py`. Reviewer is the one Red3 currently names, and B1 gets the strongest one available. No push. Merge slots via Red3; one lane merges at a time. Never write the owner's name.

## Plan
| Block | Touches | Clashes with | Kind | Stakes |
|---|---|---|---|---|
| B1 Generalize: `data/legendaries/<region>.lua` ×15 (heartlands = bear moved from config.LegendaryBear; the other 14 are empty stubs `return nil`); a loader; chain.lua keyed by `(cid, chain_id)` and driven by the entry; `animals.get(model, legendaryId)`; derived item/trophy rows; isEnabled gate; region_id/legendary in event payloads; server/main.lua skin path uses `payload.animal` ∈ legendaries. Specs: **bear regression** (the full existing chain spec passes unchanged in behaviour); two chains at once; disabled region refuses all 3 clue steps + spawn; flipping enabled shows it; every FhRegions id has a data file; unknown/stub entries are ignored | fh_hunting/shared/chain.lua, animals.lua, trophies.lua, config.lua, server/main.lua, client (marker/rumour points from data), data/legendaries/* (new), fxmanifest, spec/* | none outside the lane; B2–B4 wait on it | Root cause | **High** (persisted chain state + the skin path; the bear must not regress) |
| B2 Batch A, enabled regions: scarlett_meadows, bayou_nwa, great_plains, plus bluewater_marsh, roanoke_ridge (5). Data, pelt + trophy items, image (reuse the base species image if there's no art), coords `TODO-verify-in-game`, spec rows | data/legendaries/<those 5>.lua, item image refs | none (separate files) | Root cause | Low |
| B3 Batch B: grizzlies_east, grizzlies_west, cumberland_forest, big_valley, tall_trees (5) | data/legendaries/<those 5>.lua | none | Root cause | Low |
| B4 Batch C: hennigans_stead, cholla_springs, gaptooth_ridge, rio_bravo (4) | data/legendaries/<those 4>.lua | none | Root cause | Low |
| B5 Docs: README legendary table (region → id/label/species), OWNER-TESTS `## Hunting` cards: one full chain in an **enabled** non-heartlands region, bear regression, and "disabled region shows nothing" | fh_hunting/README.md, OWNER-TESTS.md | other lanes' OWNER-TESTS sections (rebase carefully) | Root cause | Low |

**Species spread (guide, not a lock):** no species twice in neighbouring regions. Cover bear, wolf, cougar, elk, moose, bison, alligator, boar, coyote, fox, ram/bighorn, pronghorn, buck, beaver, panther. Wetlands get alligator/beaver, mountains get ram/cougar/moose, desert gets coyote/pronghorn/cougar. A builder may swap a species if it has no pelt row in animals.lua (then add one, cargo).

**Order:** B1 → (B2 ∥ B3 ∥ B4) → B5. The 3 batches run as 3 parallel workers on separate files; each rebases on B1. Merge order is B2, B3, B4, then B5 (one slot each, or one combined slot if Red3 prefers).
**Done-check per block:** venv specs green, reviewer PASS, merged in a Red3 slot, hash logged.
**Done when:** 15 data entries (bear + 14), each with a pelt + trophy; enabled regions run their chain end to end; disabled regions show nothing and need no code change to switch on; bear behaviour unchanged; OWNER-TESTS updated; `decision hunting legendary-ladder-ready <hash>` logged.

## Open
- Trophy comfort: 15 trophies × 25 may be too much comfort for @homestead. v1 keeps 25 each; tune with Homestead after the playtest.
- Outfit/tint presets per species are unverified in game: default outfit 0 + scale, marked `TODO-verify-in-game`. If presets look identical to plain animals, the follow-up is a scale + tint pass (task to be queued after the playtest).
- Coords for the 11 disabled regions stay `TODO-verify-in-game` until world-02 G verifies the regions.

## Out of scope
- New fh_core/fh_cargo APIs. Homestead trophy placement. Quest hooks (@quests reads the events). New UI screens. Balancing pelt prices beyond a legendary value per entry. Commissioned art.

## Lead
Hun2 (rn-bc5251cf4622).
