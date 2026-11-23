# Brainstorm Summary · SURVIVAL (`survival`)

> Rolling team brief (< ~5k tokens). Updated on every decision.

## Who's here
- Brainstorm: Survival
- Lead: ★ Sur2
- Workers: 1

## Done when
- S1-S5 of plan survival-01 merged on local main (specs green), `## Survival` card in OWNER-TESTS.md, `survival playtest-ready <hash>` logged. S3b/S4b (remove the stubs) done once @core B7 and @homestead H3/H4 are on main.

## Decided
- Overlord integration rules (2026-11-22), which every plan and lead must follow: work only in `vs worktree create` units, never the primary checkout. Merge to local main only after the review PASSes: rebase on current main, `python tools/run-specs.py` all green, merge, log the hash. One lane merges at a time; rebase again if main moved. No pushes. In-game checks go in a `## Survival` section of `OWNER-TESTS.md` (no separate test doc). When ready, log `decision survival playtest-ready <hash>`; Overlord gates the combined playtest.
- `fh_homestead` belongs to @homestead (core B6b-g are on main at 06f2d3b). Correction: Well-Rested from comfort is done HERE (homestead-01 says @survival reads getComfort and applies the buff).
- Shape (Buddy lean, acted on per the Overlord's "finish now"): needs are positive timed buffs (well_fed/hydrated/rested/warm/clean). Sluggish is worked out from what's missing (0-3), never lethal, behind the `SluggishEffect` flag (default `notify`). warm only counts in cold regions. Relog uses the lane table `fh_survival_needs` plus a 10-min grace for new characters. rsg-core hunger/thirst metadata is unused. Alt (`fh_buffs.remove` + debuff ids) is deferred.
- Plan: `docs/brainstorm/plans/survival-01-needs.md`. S1 → S2 → (S3||S4||S5); S3b/S4b remove the stubs for @core registerItems (B7) and @homestead isNearStation/getComfort (H3/H4).

## Open
- @core idea-613: add caps `hydrated`/`clean` to fh_buffs config. Not blocking: apply refuses cleanly until then.
- ColdRegions ids. Lean: use the high-elevation/snow §4.4 region ids if the registry has them, otherwise an empty list (warm is then only a bonus). The lead decides at S3 from the registry, no owner input needed.

## In flight
- MERGED S1 on main @ 9730266 (range-diff '=' vs 1d21178, venv specs 36/697/0).
- MERGED S2 on main @ 1408a01 (101d57d 1c40722 a2986fd 1408a01; mig 0012_survival_needs.sql; range-diff 1 '!' server.cfg ctx only, 2/3 '='; venv 57/1159/0).
- PASS (Gemini, vs verdict exit 0), not merged yet: S3 a850f98 (= a5093bc on survival-s3b), S4 8c5a032, S5 a4d6309 (stacked on old S2 8b9ffd3; ## Survival card on survival-s5). S3b 4a513b6 on survival-s3b, Gemini review rn-a65e8a266c76 still queued (do not rebase s3b until verdict). After S2 merges: rebase s3b `--onto main 8bdca5a`, then S4, S5 (config.lua/fxmanifest append conflicts, keep all blocks).
- FORGE FREEZE (Overlord, from the owner via Hub15): nothing new starts and there are no merges or pushes. The Overlord pushes all branches. Parked:
  - S1 is built on `survival-s1` @ 533fba9 (22 specs/355 tests green), NOT merged. Its review Sur2 rn-ba97d44e5597 was in progress.
  - Resume after the cutover: re-run the S1 review → merge → S2 review (rebase, fix server.cfg) → merge → S3||S4||S5.
- DRAINED (lead): `survival-s1` @ 533fba9 (S1, review incomplete: Sur2 stopped with no verdict, so re-run the review after the cutover). `survival-s2` @ d3c3e37 (empty WIP marker on top of a7c9268, S2 server core complete: 357 tests green, unreviewed; rebase on main expected to conflict in server.cfg). Both worktrees are clean and unmerged. Open: @core hydrated/clean caps; pick the ColdRegions ids.
