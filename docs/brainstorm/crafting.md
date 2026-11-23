# Brainstorm Summary · CRAFTING (`crafting`)

> Rolling team brief (< ~5k tokens). Updated on every decision.

## Who's here
- Brainstorm: Crafting
- Lead: ★ Cra2
- Workers: 0

## Done when
- (what makes this team finished)

## Decided
- 2026-11-23 C7 merged 9211816, playtest-ready. idea-712 UN-PARKED as C8: buy lumber/nails/lead/casings at fh_trade posts (@roads `supplies` list); gun_parts = outlaw camp loot (@core fh_zones). No gathering. Crafting adds a sources spec + OWNER-TESTS only. idea-718: gunpowder + 4 herbs also BUY via idea-716 supplies; herb gathering parked.
- 2026-11-23 CORRECTION: B7 removeItem was already on main. C1-C6 + C5a/C5b merged to main 40e0b57 (docs 11bb2ce, specs 57/1155/0). Next: C7 = H3 type map + ready gate + owner-plot reach via getStations + core-03 carried API/setItemInfo swap (lead packet-crafting.md). Not playtest-ready until C7.
- 2026-11-23 H3 merged (2a7d98a). Crafting maps its station types onto homestead's: gunsmith/reload→workbench, apothecary→campfire (stationTypeMap in fh_crafting config). C5 H3 half unblocked; B7 half still waits. In-game OWNER-TESTS need H2 /fh_build (in review).
- 2026-11-23 Restore reads the OPEN world container near the gunsmith bench (fh_core openRef+view), bulky-capable types only; no homestead stash contract. (a) weapon slot / (c) un-bulky rejected. In C5. Status: C1-C4 PASS (924ff24 9fd2e40 f87cfba e7fe15b), C6 7a16b6b in review, merges held.
- 2026-11-22 Overlord integration rules: work only in `vs worktree create` units; merge to local main after review PASS (rebase on main, `python tools/run-specs.py` green, merge, log hash), one lane merges at a time; in-game checks go in the Crafting section of OWNER-TESTS.md only; no pushes; when ready log `decision crafting playtest-ready <hash>`.
- 2026-11-22 Plan docs/brainstorm/plans/crafting-01-l5.md (C1-C6). Materials only, no money fee. Restore cap 60/80/100 by stars, +20 per gun_parts. Contracts: @homestead H3 (idea-599), @core tonic caps (idea-612) + B7 removeItem.
- Station dependency: @homestead station-slot API doesn't exist yet (grep "station" in [fh] = 0 hits). Build L5 against a thin station adapter (stations = id + coords + owner plot); swap to Homestead's API when it lands. Workaround, follow-up = adapter swap block.
- Visual wear behind existing `fh_spike_gated` convar (fh_core/docs/spike-gated.md); no new flag. Condition already in item info via FhItems.condition (fh_core/shared/items.lua:132); worn_rifle drops at 20-45 (fh_zones/config.lua:27).

## Open
- C8 contracts: @roads supplies buy list; @core gun_parts in camp loot.
- @ui buff HUD: lead-queued.
- C7 (next lead): H3 type map + ready gate + getStations reach + core-03 carried API/setItemInfo swap. Tonic caps idea-612 status unverified.

## In flight
- 2026-11-23 PASS+MERGED C8 (idea-712) to main dc6c11e (ff on efc5227; Gemini PASS 0/0/2 + spec-only minors; venv 70/1357/0). spec/crafting_sources_spec.lua PENDING: 9 buy items -> @roads idea-716, gun_parts -> @core idea-717; must shrink to {}.
- 2026-11-23 PASS+MERGED C7 to main 9211816 (ff on 9c86f29; Gemini PASS 0/0/0 51413f3 + docs-only 612 commit; venv 67/1335/0). Crafting plan complete: playtest-ready 9211816 (owner test needs H2 /fh_build or fh_dev 1).
- 2026-11-23 Lead rn-5fa69919de55 handing off at 160k; next lead picks up C7 from packet-crafting.md.
- 2026-11-23 MERGED C1-C6 (incl. C5a, C5b) to main 40e0b57 (ff, on 9beb4c0; venv specs 57/1155/0; crafting files identical to reviewed b6fb09a; shared append-only files +lines only). NEXT unit C7 (not started): H3 type map + ready gate + owner-plot reach via getStations, and swap to core-03 carried API (addItem/removeItem carried refs, setItemInfo). Not playtest-ready until C7.
