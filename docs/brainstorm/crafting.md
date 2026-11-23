# Brainstorm Summary · CRAFTING (`crafting`)

> Rolling team brief (< ~5k tokens). Updated on every decision.

## Who's here
- Brainstorm: Crafting
- Lead: Crafting lead · C1 review + C2-C6
- Workers: 0

## Done when
- (what makes this team finished)

## Decided
- 2026-11-23 H3 merged (2a7d98a). Crafting maps its station types onto homestead's: gunsmith/reload→workbench, apothecary→campfire (stationTypeMap in fh_crafting config). C5 H3 half unblocked; B7 half still waits. In-game OWNER-TESTS need H2 /fh_build (in review).
- 2026-11-23 Restore reads the OPEN world container near the gunsmith bench (fh_core openRef+view), bulky-capable types only; no homestead stash contract. (a) weapon slot / (c) un-bulky rejected. In C5. Status: C1-C4 PASS (924ff24 9fd2e40 f87cfba e7fe15b), C6 7a16b6b in review, merges held.
- 2026-11-22 Overlord integration rules: work only in `vs worktree create` units; merge to local main after review PASS (rebase on main, `python tools/run-specs.py` green, merge, log hash), one lane merges at a time; in-game checks go in the Crafting section of OWNER-TESTS.md only; no pushes; when ready log `decision crafting playtest-ready <hash>`.
- 2026-11-22 Plan docs/brainstorm/plans/crafting-01-l5.md (C1-C6). Materials only, no money fee. Restore cap 60/80/100 by stars, +20 per gun_parts. Contracts: @homestead H3 (idea-599), @core tonic caps (idea-612) + B7 removeItem.
- Station dependency: @homestead station-slot API doesn't exist yet (grep "station" in [fh] = 0 hits). Build L5 against a thin station adapter (stations = id + coords + owner plot); swap to Homestead's API when it lands. Workaround, follow-up = adapter swap block.
- Visual wear behind existing `fh_spike_gated` convar (fh_core/docs/spike-gated.md); no new flag. Condition already in item info via FhItems.condition (fh_core/shared/items.lua:132); worn_rifle drops at 20-45 (fh_zones/config.lua:27).

## Open
- @core setItemInfo contract (restore writes condition) + @ui buff HUD: lead-queued.
- 2026-11-23 Freeze still on (redfrontier 14:43: no spawns/merges until cutover done). Deps both FAIL-in-review: @homestead H3 c3d0dd2 (has getStations/stationAt/isNearStation, covers idea-599); @core B7 9bad7c4 (charge bug, fix brief ready). On thaw: C2 adapter mirrors H3 signatures so C5 swap is a rename.
- Waiting on @core B7 + tonic caps idea-612 (C5/C4); carried-inventory take/give idea-615 (lead ask).

## In flight
- 2026-11-23 MERGED C1-C6 (incl. C5a, C5b) to main 40e0b57 (ff, on 9beb4c0; venv specs 57/1155/0; crafting files identical to reviewed b6fb09a; shared append-only files +lines only). NEXT unit C7 (not started): H3 type map + ready gate + owner-plot reach via getStations, and swap to core-03 carried API (addItem/removeItem carried refs, setItemInfo). Not playtest-ready until C7.
- 2026-11-23 FORGE FREEZE: PARKED. crafting-c1 @ 924ff24 (C1 built, specs 23/372 green, committed, NOT reviewed, NOT merged). Review Cra2 cancelled before start. C2-C6 not started. Resume: Gemini review of crafting-c1, then rebase+specs+merge.
- 2026-11-22 FORGE FREEZE: nothing new. Lead told to park WIP on its branches ('WIP: parked for forge freeze'), commit everything, no push (Overlord pushes). Parked: crafting-c1 @ 924ff24 (C1 built, 23 specs/372 tests green, NOT reviewed/merged; worktree clean). C2-C6 not started. Resume: Gemini review of crafting-c1 → rebase → specs → merge, then C2/C3/C4 in parallel.
- Lead rn-aab7586ab709 (Crafting Lead) spawned with crafting-01-l5. C1 first, then C2/C3/C4 in parallel, C5 after H3+B7, C6 last.
