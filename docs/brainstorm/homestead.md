# Brainstorm Summary · HOMESTEAD (`homestead`)

> Rolling team brief (< ~5k tokens). Updated on every decision.

## Who's here
- Brainstorm: Homestead
- Lead: Homestead Lead
- Workers: 0

## Done when
- H1-H5 of plans/homestead-01 merged to local main (review PASS, run-specs green) and `decision homestead playtest-ready <hash>` logged; Overlord gates the combined playtest.

## Decided
- Plan: docs/brainstorm/plans/homestead-01-slots-stations-comfort.md. Fixed plots, default 4 (one per character). Build slots per plot (cabin 0-2, fence, station_1..3, trophy_wall, chest_2..3); each unlocks a mechanic. Props client-local from server state; unverified models/coords behind `verifiedProps` flag.
- Comfort = pure sum per slot + trophies, exports getComfort/addTrophy; Survival applies buffs, not us.
- Trophy contract (agreed w/ Hunting Buddy): Homestead owns placement on trophy_wall (removeItem from chest), points from exports.fh_hunting:getTrophyComfort(itemId)->number|nil, guarded while fh_hunting not on main. Hunting fires NO events; we emit fh:homestead:trophy_placed/removed.
- Overlord rules: vs worktree units; merge only after PASS + rebase + run-specs green, log hash; one lane merges at a time; tests in OWNER-TESTS.md homestead section; no push; log playtest-ready.
- H0 → @core B7 (plans/core-02-contracts-batch.md): charge fails fh_insufficient_funds, never negative; removeItem all-or-nothing. Materials registered from fh_homestead via fh_core.registerItems. H2 waits on B7 merge (Cor3 pings).

## Open
- Plot count: 4 by default; owner can change.
- (orig ask) L1 fh_homestead (ownership moves from @core after its B6a/B6d chest work): cabin/fence/prop placement on fixed plots, persistent storage, station-slot API (Crafting consumes it), comfort score (Survival + Hunting feed/read it). No world-object clearing: pick clear plots or fake with props. Spec: docs/FRONTIER_HOMESTEAD_SPEC.md. Owner: build everything autonomously, Aub tests only at the end. Use @core §4 APIs only (fh_core containers, fh_buffs, fh_economy, regions, events); contract changes = request to @core. Anything waiting on in-game spike results goes behind one config flag. Pure-Lua specs (tools/run-specs.py) + in-game test card in README. No push.

## In flight
- FORGE FREEZE (Overlord, 2026-11-22): lane PARKED. Nothing new starts; lead told to finish or commit WIP on branches and stop workers. Resume after cutover: H3 c3d0dd2 / H4 fc4c0d1+52eef2f reviews (rerun if stopped), then merge H3→H4, then H2 after @core B7, then H5.
- PARKED (forge freeze): H3 homestead-h3 c3d0dd2 review FAIL 0/2/2 (rn-250ee6892de0): slots.lua no ready flag (setTier before load, false station_built); setTier race vs unclaim/concurrent across MySQL await; minors: FhHomesteadClaims mutable, tier-0 row/slot.tiers check. Not merged.
- PARKED (forge freeze): H4 homestead-h4 52eef2f review FAIL 2/2/1 (rn-66d146354004): no unclaimed handler in comfort.lua (stale cache/phantom trophies); unplace addItem-before-delete dup + no in-flight lock/affected check; unchecked refund + points<1/id>64 precheck; placeTrophy capacity race; minor collapsed addItem reason. Not merged. Fix H3 first, H4 rebases on it.
- H2 blocked on core B7; H5 not started. homestead-h1 84ad63c already merged (a2deba7).
- Lead rn-cff990e608c1. H1 merged a2deba7. H3 c3d0dd2 (286 tests) in review rn-250ee6892de0; H4 fc4c0d1+52eef2f (292 tests) in review rn-66d146354004; H3 merges first. H2 held for @core B7. Trophy contract confirmed.
- H1 PASS merged a2deba7 (local main, 277 specs green).
