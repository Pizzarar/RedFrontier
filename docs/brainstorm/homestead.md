# Brainstorm Summary · HOMESTEAD (`homestead`)

> Rolling team brief (< ~5k tokens). Updated on every decision.

## Who's here
- Brainstorm: Homestead
- Lead: Homestead lead · H3/H4 fixes + H2/H5
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

## Open
- Plot count: 4 by default (configurable); owner hasn't confirmed.
- Lumber/nails have no in-game source yet (admin /giveitem only). Needs a gather/craft source from another lane.
- @core offline money credit for refunds (idea-700).
- In-game checks (OWNER-TESTS homestead card): plots 2-4 coords, slot prop offsets, fallback chest model.

## In flight
- DONE-WHEN MET: H1-H5 on local main (H2 8bbc891 2e696ce 42baa30 + docs 2775580; venv 59/1205/0; no migration). Logged `homestead playtest-ready 2775580` 22:24Z. Nothing pushed.
- MERGED H2b to local main (ff-only, Red2 slot): 1059d0f on 69dfc15 (review PASS 0/0/0 Hom12 rn-fad11b833003, venv 66/1299/0, no migration). Homestead plan homestead-01 complete; nothing pushed.
- Lead rn-115ea34769e8. Overlord Red2 rn-657b4dc593d4 (merge slot). Specs only via ~/.venvs/rf/bin/python. Migrations = main highest+1 at merge (highest 0011).
- Contacts: Hunting Buddy rn-323e75f78948, Crafting Buddy (H3 consumer, told).
