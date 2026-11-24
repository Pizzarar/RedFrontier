# Brainstorm Summary · HOMESTEAD (`homestead`)

> Rolling team brief (< ~5k tokens). Updated on every decision.

## Who's here
- Brainstorm: Homestead
- Lead: ★ Hom2
- Workers: 0

## Done when
- H1-H5 of plans/homestead-01 merged to local main (review PASS, run-specs green) and `decision homestead playtest-ready <hash>` logged; Overlord gates the combined playtest.

## Decided
- Plan: docs/brainstorm/plans/homestead-01-slots-stations-comfort.md. Fixed plots, default 4 (one per character). Build slots per plot (cabin 0-2, fence, station_1..3, trophy_wall, chest_2..3); each unlocks a mechanic. Props client-local from server state; unverified models/coords behind `verifiedProps` flag.
- Placeholder plots 150 apart + spec: no two plots overlap at max fenced radius (in H1, a2deba7). Plots 2-4 coords TODO-verify in game.
- Comfort = pure sum per slot + trophies, exports getComfort/addTrophy; Survival applies buffs, not us.
- Trophy contract (agreed w/ Hunting Buddy): Homestead owns placement on trophy_wall (removeItem from chest), points from exports.fh_hunting:getTrophyComfort(itemId)->number|nil, guarded while fh_hunting not on main. Hunting fires NO events; we emit fh:homestead:trophy_placed/removed.
- Overlord rules: vs worktree units; merge only after PASS + rebase + run-specs green, log hash; one lane merges at a time; tests in OWNER-TESTS.md homestead section; no push; log playtest-ready. Migration number = main's highest + 1, set at merge during the pre-merge rebase (h4 and survival-s2 both claim 0006; second to merge renumbers).
- H0 → @core B7 (plans/core-02-contracts-batch.md): charge fails fh_insufficient_funds, never negative; removeItem all-or-nothing. Materials registered from fh_homestead via fh_core.registerItems. B7 merged to local main 334642c (idea-603 delivered).
- Plot count: 4 by default, one config value; owner can change it any time (closed 2026-11-23, no objection).

## Open
- (none in lane) Resolved: lumber $3 / nails $2 at every trade post (fh_trade/config.lua:25, roads supplies); build money refund via fh_economy.credit (018df02, H2c d19146d). Tracked elsewhere: nails.png icon → idea-724; in-game checks (plots 2-4 coords, prop offsets, fallback chest model) → OWNER-TESTS homestead card; 6 stale homestead worktrees (pre-rebase hashes) need manual sweep, owner OK first.

## In flight
- homestead-02 town lots (idea-801): H6 MERGED 281d88a+c90e069 (mig 0018); H7 MERGED b7b73a0; H9 30e713d PASS 0/0/2 (Hom27; lows = plotInfo reports unowned until claims load at startup, same as getPlot, accepted). H9b (Hom26, on homestead-h9): export lawSafeAt for @a-life (Ali1). DECIDED lawSafeAt(coords, citizenid): owner-only, nil without citizenid (stops outlaws hiding in strangers' lots); Ali1 told, passes wanted player id from fh_heat; "any owned lot" would be a separate function. H9b a058f72 PASS 0/0/0 (Hom28), hash sent to Ali1; @a-life caller on main e7a2783 (fh_heat calls lawSafeAt guarded, live once our stack merges). H10 must also check @world /where shows open lots as lots, not claim sites. Stack H8 e5a5b30 → H9 30e713d → H9b a058f72 all PASS, @world B MERGED f342821 → Hom26 rebasing (keep world plot entries, lots stay claimable=false until H10; world D touches fh_homestead/client only, no clash) → keeping both config.lua edits → specs → merge slot → H10. H8 PASS 0/0/0 e5a5b30 on homestead-h8, held until @world B on main; H9 PASS 0/0/2 30e713d (Hom27) + H9b lawSafeAt(coords,citizenid) for @a-life PASS 0/0/0 a058f72 (Hom28) on homestead-h9 (stacked on h8), held with H8 for @world B; lead now Hom2 rn-4b289c2c0700; H10 after B. Follow-ups idea-803 (@a-life enforce lot safety), idea-804 (@core citizenid rep path).
- homestead-02 decisions: lawman-safe = Workaround (enforcement idea-803 @a-life); lot abandon takes +25 rep back; offline admin abandon releases lot + logs skipped rep (citizenid rep path idea-804 @core). Owner defaults ($300, +25, chest_2+workbench, no refund, old rows = claim) built as config, still unconfirmed by owner.
- DONE-WHEN MET: H1-H5 on local main (H2 8bbc891 2e696ce 42baa30 + docs 2775580; venv 59/1205/0; no migration). Logged `homestead playtest-ready 2775580` 22:24Z. Nothing pushed.
- MERGED H2b to local main (ff-only, Red2 slot): 1059d0f on 69dfc15 (review PASS 0/0/0 Hom12 rn-fad11b833003, venv 66/1299/0, no migration). Homestead plan homestead-01 complete; nothing pushed.
- MERGED H2c+H2d to local main (ff-only, Red2 slot): d19146d (build money refund via fh_economy.credit by citizenid; PASS 0/0/1 rn-39f017886dec) c6eb2ee (items spec; gate-audit lumber/nails claim false positive; PASS 0/0/3 rn-7c53c5dd3102). venv 73/1407/0, no migration. Lumber/nails now bought at trade posts (roads supplies); README + OWNER-TESTS updated.
- Lead Hom2 rn-4b289c2c0700 (took over from rn-115ea34769e8 2026-11-24 via vs handoff). Overlord = `vs who lead --lane redfrontier` (Red3 → Red4 handoff). Specs only via ~/.venvs/rf/bin/python. Migrations = main highest+1 at merge (highest 0011).
- Contacts: Hunting Buddy rn-323e75f78948, Crafting Buddy (H3 consumer, told).
