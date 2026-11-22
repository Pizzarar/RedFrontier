# Spikes P1 · five 5-minute in-game probes (@spk)

## Owner words (verbatim, via hub)
"Aub wants in-game ASAP. Each spike = a tiny resource he can /ensure on the @core dev server and judge go/no-go in under 5 minutes, with a one-line test script. Order by what blocks M1: outlaw camp spawn + ownership migration first, then mounted wagon chase, wheel break, pelt quality, weapon wear. Don't build your own server; agree the path with Core Buddy rn-bc8bcb7f7c98. Results go to natives.md via Core."

## Decided
- No own server. Spikes run on @core's M0 dev server (RSGCore + ox_lib + oxmysql).
- One resource per spike, `spk_<name>`, throwaway, never inside `fh_` folders. Not ensured by default; Aub runs `ensure spk_<name>`.
- Each spike ships a README whose first line is the test script (≤5 min), and ends with a `RESULT: GO|NO-GO|PARTIAL — <why>` line Aub fills in.
- Deps: ox_lib commands only. No RSG item/container calls (keeps spikes unblocked by Core's rsg-inventory decision).
- Every native used is listed in the spike README as name + hash + rdr3 natives reference link. Core folds proven ones into `fh_core/docs/natives.md`.
- Existing primitives checked: the spec's natives.md allowlist (`FRONTIER_HOMESTEAD_SPEC.md:122,148`) is the results sink; no new VS command or rule added.

- Core Buddy confirmed (2026-11-22): `server/` is FXServer server-data; spikes go in `server/resources/[spikes]/spk_<name>/`; not in server.cfg. Natives go in a `## Spikes` section the Core lead folds into `server/resources/[fh]/fh_core/docs/natives.md`. Core plan: docs/brainstorm/plans/core-01-boot-to-m1.md.
- Server boots at end of Core block B1 (Core lead rn-0e1a7e68e8de messages the owner test card). Build spikes now; test after boot.
- S1 default test = owner drop/rejoin migration (2nd account unknown).

## Open
- Does Aub have a 2nd RedM account/client? If yes, S1 adds a true 2-client check.

## Blocks
| # | Spike | Test script (one line) | GO if | Kind |
|---|---|---|---|---|
| S1 | `spk_camp` camp spawn + ownership | `/spk_camp` near a road → ride away 300m → return; owner disconnects + rejoins (2nd client if available) | Server spawns 4 outlaws + props once; no duplicates on 2nd join; camp persists across owner leave; kill state syncs | Root cause (M1 blocker, spec :124) |
| S2 | `spk_chase` mounted wagon chase | `/spk_chase` while driving a wagon → drive 60s | 3 AI riders keep pace and shoot for 60s on road + some off-road, no stalls/bunching | Root cause; NO-GO → spec fallback "chokepoint roadblocks only" (:123) |
| S3 | `spk_wheel` wheel break | `/spk_wheel` in wagon → `/spk_wheel fix` | One wheel visibly breaks/slows wagon; fix restores it | Root cause |
| S4 | `spk_pelt` pelt quality | `/spk_pelt` → shoot spawned deer head vs body → skin both | Quality readable from native carcass/kill data, differs by shot | Root cause; NO-GO → roll quality from hit bone ourselves |
| S5 | `spk_wear` weapon wear | `/spk_wear get` → fire 50 rounds → `/spk_wear set 0.8` | Per-weapon degradation readable and settable | Root cause |

| Block | Touches | Clashes with |
|---|---|---|
| S1–S5 | `server/resources/[spikes]/spk_*/` only  | none: server.cfg untouched; Core's natives.md only via Core lead |

Order: S1 → S2 → S3 → S4 → S5. Each can be built before the server boots; testing waits on Core's boot.

## Done-check per block
Resource starts with no console errors on `ensure`; README test line runs in ≤5 min; Aub's RESULT line filled; natives listed with hashes.

## Lead
@spk lead, spawned by Spikes Buddy 2026-11-22. Branch off origin/main; one PR per spike or one PR for S1–S5, never touching fh_ folders.

## Out of scope
Real fh_ systems, items/inventory, persistence beyond S1's camp state, polish, any server setup.
