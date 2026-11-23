# Brainstorm Summary · HUNTING (`hunting`)

> Rolling team brief (< ~5k tokens). Updated on every decision.

## Who's here
- Brainstorm: Hunting
- Lead: Hunting Lead
- Workers: 0

## Done when
- H1–H5 of docs/brainstorm/plans/hunting-01-l8.md merged to local main with reviewer PASS + run-specs green, a `## Hunting` section in OWNER-TESTS.md, and `decision hunting playtest-ready <hash>` logged.

## Decided
- Plan: docs/brainstorm/plans/hunting-01-l8.md (2026-11-22). Quality flag `Config.PeltQualitySource='roll'` (default; S4 untested) | `'native'`. Small/medium game = bulky pelts, big game + legendary = cargo (wagon within ~8 m, else the skin is refused). One Legendary Bear, 3-clue chain in one region (Buddy lean, R13). Trophies: `exports.fh_hunting:getTrophyComfort(itemId) -> number|nil`; Homestead owns placement and reads the export; Hunting fires no trophy events (agreed with Homestead Buddy rn-e71c3e2fc82c, 2026-11-22).
- Events for @quests/@guide (hub, 2026-11-22): pelt_skinned (H2), pelt_sold (H3), clue_found/legendary_spawned/chain_complete (H4), all `fh:hunting:*` with citizenid. Payloads are in plan Decided.
- pelt_sold payload = {citizenid,item_id,animal,size_class,quality,price,region_id} (@quests Q0b, accepted; Quests Buddy rn-f56f69815ec9, Guide Buddy rn-8111c1048653 informed).
- H2 deviations accepted: own Skin prompt (vanilla not hooked), bulky → saddlebag (backpack pocket-only), pelt_skinned carries src. Head/vital always 3★; body 10% 1★.
- Overlord integration rules: vs worktree units; PASS → rebase → run-specs green → merge local main, log hash; one lane merges at a time; no push; tests in OWNER-TESTS.md `## Hunting`; log `decision hunting playtest-ready <hash>` at the end.

## Open
- Big-game/legendary cargo pelts are refused until a wagon lookup exists (idea-617 ACCEPTED into @roads R1: `exports.fh_cargo:nearestWagon(src, coords, range) -> container ref|nil` LOCKED: owner-only v1, coords nil = ped pos, range capped 25 m, never throws; lands in roads-r1 fix round, Roads sends the merge hash; idea-616 → @core carcass end). Lean: hunting calls it through pcall; H4 can merge with the trophy + chain_complete working, but the full legendary pelt loop waits on @roads.
- @homestead H4 consumes getTrophyComfort (agreed; being built now).
- When S4 spk_pelt returns GO, consider flipping `PeltQualitySource` to `native`.

## In flight
- Hunting Lead rn-36662e6cd481 spawned 2026-11-22 with plan hunting-01-l8 (H1→H5).
- H1 PASS: merged to main e3fc679 (Gemini PASS e74ee3d, specs 21/345 green).
- FORGE FREEZE: no spawns, reviews or merges until the Overlord lifts it. Buddy watch cancelled; no workers running.
- PARKED (forge freeze 2026-11-23): H2 hunting-h2 2a841b6 committed and clean, specs 22/372 green. H2 PASS: Gemini PASS 0/0/1 2a841b6 (vs verdict exit 0), merge held by freeze. Resume order: rebase, run-specs, merge. The low (pcall around lib.progressBar, client/main.lua:110-115) goes into H3. Then H3 (trapper + pelt_sold {citizenid,item_id,animal,size_class,quality,price,region_id} + findCargoWagon via pcall exports.fh_cargo:nearestWagon(src,coords,range)), then H4||H5.
- Known: boot-check needs a licence key; pelts non-stackable pending @core.
