# core-09 · Nit sweep + weapon wear unify + camp-stash reach clamp

Lead: @core lead Cor4 rn-263740f80b3e. Base: main after core-08 P2 slot (a686aaf).

## Idea
SPEC Done-when has only owner-gated gaps left: M0/M1 in-game, B1-live, the B6f flip. So core-09 clears the keyless queue: three review nits, the P1-wear field split (a real first-play bug: looted "worn" rifles show 100 quality), and the code half of CHEST-REACH.

## Lead words (Cor4)
"Open core queue: P2-nit, P5-nit (fh_log rotation/buffer), M2-nit in tierA review, P1-wear (needs gunsmith coord), B6f-cleanup + B1-live (owner-gated). CHEST-REACH declined: 10m refuted, fh_zones camp stashes use unverified z-hints and groundZAt isn't clamped by snapZ (root fix = verified camp coords + clamp; not core-owned?)"

## Decided
- **CHEST-REACH is core-owned.** fh_zones was built in @core (B6b), and FhSnap/FhGroundSnap live in fh_core/client/ground_snap.lua. Split it:
  - (a) Keyless code fix: clamp the groundZAt result through snapZ/SNAP_TOLERANCE everywhere it's used, the same way spawn.lua:48 and ground_snap.lua:41 do. Find any caller that uses raw groundZAt. Then the server reach band (fh_core/config.lua:46-51, SnapToleranceBelow 20 m) can shrink back toward the tolerance + InteractDistance. Specs.
  - (b) Verified camp stash coords need someone in-game, so add an OWNER-TESTS step: "stand at outlaw camp stash, run /fh_where (or the existing coords admin cmd), paste the result". Swap the TODO-verify-in-game hints once that comes back. That's a follow-up task CHEST-COORDS, owner-gated.
- **P1-wear: canonical field = `info.quality` (0-100), the field vendored rsg-weapons already reads, degrades and repairs.** Why: rsg-weapons is vendored byte-identical to upstream (P1), so forking it to read `condition` breaks that. fh_zones loot rolls `quality` instead of `condition`. fh_gunsmith /fh_restore and client/wear.lua read and write `quality`. Read fallback: `quality or condition` for one release, so items already in the DB still restore. Star caps (60/80/100) apply to quality. One block across fh_zones + fh_gunsmith, so there's never a half-state. **Needs @crafting OK** (fh_gunsmith is theirs). Buddy asks the Crafting Buddy now. If they say no, the block shrinks to fh_zones writing both fields.
- P2-nit, P5-nit: as written in TASKS.json. P5: size cap + one rotation (audit.log → audit.log.1), buffered flush on a timer (e.g. 2 s) and on resource stop.
- M2-nit is already in tierA review (rn-e29f1504c265). Merge on PASS; it's not in this plan.
- Checked existing primitives: FhGroundSnap.snapZ/SNAP_TOLERANCE (fh_core/client/ground_snap.lua), the Access tolerances (fh_core/config.lua:44-51), and the rsg-weapons quality path (server.lua:25-27,74,140). No new command; /fh_where only if no coords admin cmd exists (check B5 natives.md / admin cmds first).

## Plan
| Block | Touches | Clashes with | Kind |
|---|---|---|---|
| R1 reach clamp (CHEST-REACH a) | fh_core/client/ground_snap.lua callers, fh_core/config.lua Access, fh_zones client stash snap, specs | W1 (fh_zones: different files, so rebase) | Root cause (coords = CHEST-COORDS follow-up, owner-gated) |
| W1 wear unify (P1-wear) | fh_zones/config.lua + rules (loot info), fh_gunsmith server/main.lua, shared/restore_flow.lua, client/wear.lua, README both, specs | R1 (fh_zones), @crafting lane (fh_gunsmith; needs their OK) | Root cause |
| N1 nits | fh_core/server/useables.lua (P2-nit), fh_log/server/main.lua (P5-nit), specs | none | Root cause |

All parallel; W1 waits for the @crafting OK. Builders: Gemini for normal work. N1's useables part touches the money-clip path, so its review is tierA (Claude). R1 and W1 get normal review.
Done-check: venv specs green, check-contracts 0 findings, syntax clean.
- R1: spec proves no raw groundZAt reaches a reach/placement decision; tightened band still covers snapped containers.
- W1: looted rifle quality lands in 20-45, restore raises quality up to the star cap, a legacy `condition`-only item still restores, rsg-weapons untouched (diff empty).
- N1: unload maps cleared after drop; seq untouched while clipBusy; audit.log rotates at the cap; flush on stop.
- OWNER-TESTS gets the camp-coords step and "looted rifle shows worn quality".

## Open
- (none)

## Out of scope
B6f-cleanup, B1-live (owner-gated), verifying camp coords in-game, M2-nit (already in review).

## Amendment 2026-11-25: @crafting OK on W1 (core does all of it, one block)
Crafting terms (verbatim, condensed):
1. info.quality canonical; read `quality or condition`, write quality only.
2. Restore math stays in fh_crafting/shared/craft_rules.lua:59-70 (60/80/100 caps, PART_VALUE 20); param rename OK; numbers/reasons unchanged ('no_condition' may become 'no_quality', update specs).
3. Keep net event name `fh_gunsmith:conditionChanged` (fh_tutorial/client/main.lua:66 listens).
4. Update Crafting OWNER-TESTS lines mentioning condition (OWNER-TESTS.md ~95,166,244,256,259) + fh_gunsmith/fh_crafting READMEs.
5. Ping Cra3 (crafting lead) with the merge hash.
W1 touches now also include fh_crafting/shared/craft_rules.lua + its specs and OWNER-TESTS.md. Open item closed.
