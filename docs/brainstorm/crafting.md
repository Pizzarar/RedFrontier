# Brainstorm Summary · CRAFTING (`crafting`)

> Rolling team brief (< ~5k tokens). Updated on every decision.

## Who's here
- Brainstorm: Crafting
- Lead: ★ Cra3
- Workers: 0

## Done when
- The M2 crafting loop plays end to end in game: loot worn_rifle → restore at the bench, craft ammo, brew a tonic and see the buff. Every input has an in-game source (C8 sources spec has no PENDING), and the Crafting OWNER-TESTS card PASSes.

## Decided
- 2026-11-25 @core W1 (core-09) owns the wear-field fix across fh_gunsmith + craft_rules restore: info.quality canonical (rsg-weapons unforked), read quality-or-condition, caps 60/80/100 + PART_VALUE 20 unchanged, event fh_gunsmith:conditionChanged kept (fh_tutorial listens), OWNER-TESTS/README wording updated. Core pings Cra3 on merge.
- 2026-11-25 C10 merged c657135 (docs b041ef4). idea-916 farming bounced to @homestead: new homestead system, not crafting's; no owner go needed here.
- 2026-11-25 Plan docs/brainstorm/plans/crafting-03-cooking.md (C10a-b, idea-852): station type cook→campfire; cook_meat/cook_stew/cook_stew_veg into rsg cooked_meat/stew/stew_veg (survival already maps them to well_fed). raw_meat from @hunting skin grant; carrot/potato/corn BUY via @roads supplies.
- 2026-11-24 Plan docs/brainstorm/plans/crafting-02-herbs.md (C9a-c, idea-720): herb patches via lib.points + [E] + progressBar, server reach + shared per-patch cooldown, addItem carried. No new natives. Props/blips → spikes spk_herb (Open).
- 2026-11-23 C7 merged 9211816, playtest-ready. idea-712 UN-PARKED as C8: buy lumber/nails/lead/casings at fh_trade posts (@roads `supplies` list); gun_parts = outlaw camp loot (@core fh_zones). No gathering. Crafting adds a sources spec + OWNER-TESTS only. idea-718: gunpowder + 4 herbs also BUY via idea-716 supplies; herb gathering parked.
- 2026-11-23 CORRECTION: B7 removeItem was already on main. C1-C6 + C5a/C5b merged to main 40e0b57 (docs 11bb2ce, specs 57/1155/0). Next: C7 = H3 type map + ready gate + owner-plot reach via getStations + core-03 carried API/setItemInfo swap (lead packet-crafting.md). Not playtest-ready until C7.
- 2026-11-23 H3 merged (2a7d98a). Crafting maps its station types onto homestead's: gunsmith/reload→workbench, apothecary→campfire (stationTypeMap in fh_crafting config). C5 H3 half unblocked; B7 half still waits. In-game OWNER-TESTS need H2 /fh_build (in review).
- 2026-11-23 Restore reads the OPEN world container near the gunsmith bench (fh_core openRef+view), bulky-capable types only; no homestead stash contract. (a) weapon slot / (c) un-bulky rejected. In C5. Status: C1-C4 PASS (924ff24 9fd2e40 f87cfba e7fe15b), C6 7a16b6b in review, merges held.
- 2026-11-22 Overlord integration rules: work only in `vs worktree create` units; merge to local main after review PASS (rebase on main, `python tools/run-specs.py` green, merge, log hash), one lane merges at a time; in-game checks go in the Crafting section of OWNER-TESTS.md only; no pushes; when ready log `decision crafting playtest-ready <hash>`.
- 2026-11-22 Plan docs/brainstorm/plans/crafting-01-l5.md (C1-C6). Materials only, no money fee. Restore cap 60/80/100 by stars, +20 per gun_parts. Contracts: @homestead H3 (idea-599), @core tonic caps (idea-612) + B7 removeItem.
- Station dependency: @homestead station-slot API doesn't exist yet (grep "station" in [fh] = 0 hits). Build L5 against a thin station adapter (stations = id + coords + owner plot); swap to Homestead's API when it lands. Workaround, follow-up = adapter swap block.
- Visual wear behind existing `fh_spike_gated` convar (fh_core/docs/spike-gated.md); no new flag. Condition already in item info via FhItems.condition (fh_core/shared/items.lua:132); worn_rifle drops at 20-45 (fh_zones/config.lua:27).

## Open
- @core W1 wear-field unify (core-09): watch for merge; Cra3 rechecks gunsmith specs/owner card.
- Waiting on idea-914 (@hunting raw_meat) + idea-915 (@roads carrot/potato/corn). spec/crafting_sources_spec.lua PENDING shrinks to {} as they land.
- @ui buff HUD: lead-queued.

## In flight
- 2026-11-25 PASS+MERGED C9a-c herb gathering (idea-720, plan crafting-02-herbs) to main 3ee435d (ff on 743221f; Gemini PASS 0/0/0 7314883; venv 111/2046/0, contracts 0, syntax 0). Herb patches = second herb source next to trade supplies; coords TODO-verify-in-game.
- 2026-11-23 PASS+MERGED C8 (idea-712) to main dc6c11e (ff on efc5227; Gemini PASS 0/0/2 + spec-only minors; venv 70/1357/0). spec/crafting_sources_spec.lua PENDING: 9 buy items -> @roads idea-716, gun_parts -> @core idea-717; must shrink to {}.
- 2026-11-23 PASS+MERGED C7 to main 9211816 (ff on 9c86f29; Gemini PASS 0/0/0 51413f3 + docs-only 612 commit; venv 67/1335/0). Crafting plan complete: playtest-ready 9211816 (owner test needs H2 /fh_build or fh_dev 1).
- 2026-11-25 PASS+MERGED C10a-b cooking (idea-852, plan crafting-03-cooking) to main c657135 (ff on db4bd55; Gemini PASS 0/0/2 5236cc4, low 2 fixed c657135, low 1 places.lua ok by UI3; venv 122/2226/0, contracts 0, syntax 231/0). Live playtest needs fh_give until idea-914 raw_meat + idea-915 veg land.
- 2026-11-25 PASS+MERGED raw_meat source (idea-914): spec/crafting_sources_spec.lua reads FhHuntingConfig.MeatItem, PENDING now carrot/potato/corn only (idea-915); OWNER-TESTS Cooking card skin-a-rabbit wording. ff on 65d70d1 (0b622e7, f1c9e4c); Gemini FAIL 0/1/1 da48bc6 -> PASS 0/0/0 f109799; venv 139/2582/0, G5 0 unknown, contracts 0, syntax 268/0.
- 2026-11-25 PASS+MERGED veg cooking card (idea-915): OWNER-TESTS Cooking card + Crafting Preconditions buy carrot/potato/corn via /tradebuy ($3); sources PENDING = {} (roads-04 abbf600). ff on 01e7f51 (8fe3637); Gemini PASS 0/0/0 4210efb; venv 147/2736/0, G5 0 unknown, contracts 0, syntax 276/0. Crafting done-when now waits only on the owner Crafting OWNER-TESTS PASS.
