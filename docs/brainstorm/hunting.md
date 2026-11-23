# Brainstorm Summary · HUNTING (`hunting`)

> Rolling team brief (< ~5k tokens). Updated on every decision.

## Who's here
- Brainstorm: Hunting
- Lead: ★ Hun2
- Workers: 1

## Done when
- H1–H5 of docs/brainstorm/plans/hunting-01-l8.md merged to local main with reviewer PASS + run-specs green, a `## Hunting` section in OWNER-TESTS.md, and `decision hunting playtest-ready <hash>` logged.

## Decided
- Plan: docs/brainstorm/plans/hunting-01-l8.md (2026-11-22). Quality flag `Config.PeltQualitySource='roll'` (default; S4 untested) | `'native'`. Small/medium game = bulky pelts, big game + legendary = cargo (wagon within ~8 m, else the skin is refused). One Legendary Bear, 3-clue chain in one region (Buddy lean, R13). Trophies: `exports.fh_hunting:getTrophyComfort(itemId) -> number|nil`; Homestead owns placement and reads the export; Hunting fires no trophy events (agreed with Homestead Buddy rn-e71c3e2fc82c, 2026-11-22).
- Events for @quests/@guide (hub, 2026-11-22): pelt_skinned (H2), pelt_sold (H3), clue_found/legendary_spawned/chain_complete (H4), all `fh:hunting:*` with citizenid. Payloads are in plan Decided.
- pelt_sold payload = {citizenid,item_id,animal,size_class,quality,price,region_id} (@quests Q0b, accepted; Quests Buddy rn-f56f69815ec9, Guide Buddy rn-8111c1048653 informed).
- H2 deviations accepted: own Skin prompt (vanilla not hooked), bulky → saddlebag (backpack pocket-only), pelt_skinned carries src. Head/vital always 3★; body 10% 1★.
- Overlord integration rules: vs worktree units; PASS → rebase → run-specs green → merge local main, log hash; one lane merges at a time; no push; tests in OWNER-TESTS.md `## Hunting`; log `decision hunting playtest-ready <hash>` at the end.

## Open
- LANDED: nearestWagon + getWagon on local main b06fc58 (commit 6db6c2e). Was roads-r1 32817e7, re-review PASS 0/0/0. Returns {type='wagon', id='fh:wagon:<id>'}|nil. Hunting passes range=8 (plan). idea-616(2) wagon coords = exports.fh_cargo:getWagon(ref.id:gsub('^fh:wagon:','')).coords (no new export; Roads 2026-11-23). findCargoWagon wraps both in pcall. Merges first in the roads order once python3-lupa is on the forge; Roads Lead sends the main hash. Decided (R13): H3 codes against it now via pcall, nil/missing → refuse; no merge-order dependency.
- (UNBLOCKED, kept for context) Big-game/legendary cargo pelts are refused until a wagon lookup exists (idea-617 ACCEPTED into @roads R1: `exports.fh_cargo:nearestWagon(src, coords, range) -> container ref|nil` LOCKED: owner-only v1, coords nil = ped pos, range capped 25 m, never throws; lands in roads-r1 fix round, Roads sends the merge hash; idea-616 → @core carcass end). Lean: hunting calls it through pcall; H4 can merge with the trophy + chain_complete working, but the full legendary pelt loop waits on @roads.
- idea-616(1) delivered: core C3c on local main 2116460: exports.fh_core:requestOfNetId(netId) -> requestId|nil (adopted only). On skin: id = requestOfNetId(netId); if id then despawn(id) (pcall; nil for wild animals, the Legendary Bear path). Goes into H3 (claim) and H4 (bear). Carried removeItem (idea-687) = core C3a, in review.
- @homestead H4 consumes getTrophyComfort (agreed; being built now).
- When S4 spk_pelt returns GO, consider flipping `PeltQualitySource` to `native`.

## In flight
- 2026-11-23 Hun2: H6 MERGED to main 3ba2783 (ab49b50+3ba2783, range-diff '=' vs reviewed 3a97873, venv 57/1164/0, no migration). H7 despawn(requestOfNetId) on hunting-h7 cc030aa, in Gemini review rn-452bd87f8fa2.
- 2026-11-23 MERGED to main (slot, main 0fb8dc6 base): H2 43742a4, H3 ec31845, H5 f7b8eb8, H4 855ef3f (migration renumbered 0010). venv specs 49/962/0. H6 (core B7 charge/removeItem, hunting-h6) awaits re-review -> next slot; despawn(requestOfNetId) wiring -> next slot.
- 2026-11-23 Hunting lead rn-fba839f5dc6c: ALL BLOCKS REVIEW-CLEAN, merges held on lupa. Stack h2>h3>h5>h4 (branches hunting-h2..h4, local only):
  - H2 PASS: 45fb835 (= reviewed 2a841b6, range-diff Author-only).
  - H3 PASS 0/0/1 fabac75 (9833c38+180edec+fabac75; low = task hunting-xyz-probe).
  - H5 PASS 0/0/0 f67ca43 (08dc820+f67ca43, range-diff '=' vs reviewed 1bf8ee3).
  - H4 PASS 0/0/0 8220ced (6642985+f211689+8220ced; migration placeholder 0006, renumber at merge).
  - xyz-probe follow-up PASS 0/0/0 a9e095e on hunting-h4 (H3 low closed; h4 tip now a9e095e).
  - Workarounds queued to @core: idea-687 removeItem, idea-692 fh_economy charge.
- Hunting Lead rn-36662e6cd481 spawned 2026-11-22 with plan hunting-01-l8 (H1→H5).
- H1 PASS: merged to main e3fc679 (Gemini PASS e74ee3d, specs 21/345 green).
- FORGE FREEZE: no spawns, reviews or merges until the Overlord lifts it. Buddy watch cancelled; no workers running.
- PARKED (forge freeze 2026-11-23): H2 hunting-h2 2a841b6 committed and clean, specs 22/372 green. H2 PASS: Gemini PASS 0/0/1 2a841b6 (vs verdict exit 0), merge held by freeze. Resume order: rebase, run-specs, merge. The low (pcall around lib.progressBar, client/main.lua:110-115) goes into H3. Then H3 (trapper + pelt_sold {citizenid,item_id,animal,size_class,quality,price,region_id} + findCargoWagon via pcall exports.fh_cargo:nearestWagon(src,coords,range)), then H4||H5.
- Known: boot-check needs a licence key; pelts non-stackable pending @core.
