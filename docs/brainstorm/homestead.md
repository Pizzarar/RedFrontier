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
- homestead-02 defaults (built as config, owner can change any time): $300/lot, +25 region rep (taken back on abandon), lot slots chest_2 + workbench, no refund on abandon, old rows = claim. lawSafeAt(coords, citizenid) owner-only.

## Open
- (none in lane) Parked/elsewhere: /where lot finder idea-815 (homestead inbox); nails.png idea-724; citizenid rep path for offline admin abandon idea-804 @core; owner in-game checks = OWNER-TESTS homestead cards (plots, props, lots); stale homestead worktrees (pre-rebase hashes) need manual sweep, owner OK first.

## In flight
- DONE: homestead-01 (H1-H5 + H2b/c/d) and homestead-02 town lots (H6-H10 + H9b) on main, pushed, tip deb80ca, specs 86/1588/0. Logged `homestead town-lots playtest-ready deb80ca` 2026-11-24T17:13Z.
- Lead Hom2 rn-4b289c2c0700. Overlord = `vs who lead --lane redfrontier`. Specs only via ~/.venvs/rf/bin/python. Migrations = main highest+1 at merge (homestead highest 0018).
- Contacts: Hunting Buddy rn-323e75f78948, Crafting Buddy (stations), @a-life Ali1 (lawSafeAt consumer), @world Wor1 (plot/lot config, /where).
