# Brainstorm Summary · SURVIVAL (`survival`)

> Rolling team brief (< ~5k tokens). Updated on every decision.

## Who's here
- Brainstorm: Survival
- Lead: ★ Sur2
- Workers: 0

## Done when
- S1-S5 of plan survival-01 merged on local main (specs green), `## Survival` card in OWNER-TESTS.md, `survival playtest-ready <hash>` logged. S3b/S4b (remove the stubs) done once @core B7 and @homestead H3/H4 are on main.

## Decided
- Overlord integration rules (2026-11-22), which every plan and lead must follow: work only in `vs worktree create` units, never the primary checkout. Merge to local main only after the review PASSes: rebase on current main, `python tools/run-specs.py` all green, merge, log the hash. One lane merges at a time; rebase again if main moved. No pushes. In-game checks go in a `## Survival` section of `OWNER-TESTS.md` (no separate test doc). When ready, log `decision survival playtest-ready <hash>`; Overlord gates the combined playtest.
- `fh_homestead` belongs to @homestead (core B6b-g are on main at 06f2d3b). Correction: Well-Rested from comfort is done HERE (homestead-01 says @survival reads getComfort and applies the buff).
- Shape (Buddy lean, acted on per the Overlord's "finish now"): needs are positive timed buffs (well_fed/hydrated/rested/warm/clean). Sluggish is worked out from what's missing (0-3), never lethal, behind the `SluggishEffect` flag (default `notify`). warm only counts in cold regions. Relog uses the lane table `fh_survival_needs` plus a 10-min grace for new characters. rsg-core hunger/thirst metadata is unused. Alt (`fh_buffs.remove` + debuff ids) is deferred.
- survival-02 (2026-11-24, Red3 quota push): `docs/brainstorm/plans/survival-02-food-and-fire.md`. F1 food/drink map (loot + rsg-core foods) || F2 owned homestead campfire = warm, then F3 card + natives spike. Cooking/meat/HUD routed: @crafting idea-852, @hunting idea-853, @ui idea-854. No new export/command/migration.
- Plan: `docs/brainstorm/plans/survival-01-needs.md`. S1 → S2 → (S3||S4||S5); S3b/S4b remove the stubs for @core registerItems (B7) and @homestead isNearStation/getComfort (H3/H4).

## Open
- ColdRegions: wait for @world to add a cold region id, then add it.
- Native default flip (WaterCheck/SluggishEffect) after the owner's F3 spike PASS.

## In flight
- PASS/MERGED 2026-11-25: idea-857 /rest e8ba6f1 (Gemini PASS 0/0/1); G1 any-owner campfire heat via stationAt (idea-893) + restBed cooldown (idea-948) 8d0b4f1 (Sonnet PASS 0/0/2). New gates clean for survival on 8d0b4f1: 128/2303/0/0, load-manifests 0 unknown, contracts 0 findings. Owner steps 29-31 added. MERGED idea-1008 carrot well_fed 0.25 (0f4d2e9 2af9721 + H18 allowlist stopgap dropped 67059af; Gemini PASS 0/0/0). Owner steps 29-32. Lane queue empty: next plan via Buddy.
- survival-02 handed to Sur2 rn-9bba3824750e (2026-11-24). survival-01 fully merged (caebf25).
- PASS/MERGED survival-02 complete: F1 c6e26bd + F2 029a49f (Gemini PASS 0/0/1, 0/0/3), F3 card dc424a1 (PASS 0/0/0). venv 105/1947/0/0. Lows queued: task F-lows, @homestead idea-893. Next: owner runs ## Survival steps 21-28; native default flip only after spike PASS.
- MERGED S1 on main @ 9730266 (range-diff '=' vs 1d21178, venv specs 36/697/0).
- MERGED S2 on main @ 1408a01 (101d57d 1c40722 a2986fd 1408a01; mig 0012_survival_needs.sql; range-diff 1 '!' server.cfg ctx only, 2/3 '='; venv 57/1159/0).
- MERGED S3+S3b on main @ 883d46c (c239455 40a24fe eeea378 f92c87e 883d46c; Gemini PASS 0/0/0 on 4a513b6; range-diff 1 '!' natives.md keep-both doc, rest '='; venv 58/1172/0).
- MERGED S4 on main @ c0dafc1 (01b935e fa481a0 c0dafc1; Gemini PASS 0/0/0 a60f748, range-diff all '='; venv 65/1290/0). Bedroll registers via S3b I.ITEMS path.
- MERGED S5 on main @ e9a2efc (Gemini PASS 0/0/1 a72557b, low fixed in doc commit; range-diff '=' vs b37946c; venv 66/1299/0). ## Survival card in OWNER-TESTS.md. survival-01 S1-S5 COMPLETE, playtest-ready e9a2efc.
- MERGED S4b on main @ caebf25 (homestead pcall adapter dropped, direct exports + GetResourceState gate; Gemini PASS 0/0/1 6e74574; range-diff '='; venv 78/1456/0/0, syntax 180/0). survival-01 fully done incl. S3b/S4b.
- 2026-11-24 PASS survival-01 (Red3): stale FREEZE/DRAINED notes about S1/S2 removed; all of S1-S5, S3b and S4b are merged (see above). No open units, empty inbox. Lane idle by design.
