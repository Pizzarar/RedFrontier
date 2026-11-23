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
- Plot count: 4 by default; owner can change.
- (orig ask) L1 fh_homestead (ownership moves from @core after its B6a/B6d chest work): cabin/fence/prop placement on fixed plots, persistent storage, station-slot API (Crafting consumes it), comfort score (Survival + Hunting feed/read it). No world-object clearing: pick clear plots or fake with props. Spec: docs/FRONTIER_HOMESTEAD_SPEC.md. Owner: build everything autonomously, Aub tests only at the end. Use @core §4 APIs only (fh_core containers, fh_buffs, fh_economy, regions, events); contract changes = request to @core. Anything waiting on in-game spike results goes behind one config flag. Pure-Lua specs (tools/run-specs.py) + in-game test card in README. No push.

## In flight
- MERGED H2 to local main (ff-only, Red2 slot): 8bbc891 2e696ce 42baa30 (review PASS 0/0/2 rn-59cb34a9a37b, venv 59/1205/0). H1-H5 all merged. Follow-up H2b (2 lows: open_chest chestBuilt spec gap; fh_economy missing from fxmanifest dependencies) on homestead-h2b, then playtest-ready.
- MERGED to local main (ff-only, slot from Red2): H3 2a7d98a, H4 f22ea9d (migration renumbered 0011_homestead_trophies), H5 84cfd2e + refs chore f4272e6. Venv specs 51/1022/0, migration dedupe empty. H2 (8b15695, stacked on old H5) in Gemini review Hom10 rn-59cb34a9a37b; rebase onto main + next slot.
- Lead rn-115ea34769e8. Overlord Red2 rn-657b4dc593d4 (merge slot). Specs only via ~/.venvs/rf/bin/python. Migrations = main highest+1 at merge (highest now 0011). Crafting Buddy told H3 exports on main (idea-599 unblocked).
- LAST BLOCK: H2 in Gemini review; needs its own merge slot, rebase onto fad2417 after review (Hom10, watch w-fdd5df01): ebe56a6 build flow, d87d369 spec, 8b15695 docs, on top of h5. Full venv suite on tip 28/542/0. Order: take materials, charge, set tier; each failure refunds once; ownership re-checked after every wait; lumber+nails; isInSafeZone only claimed plots, bigger when fenced; props behind verifiedProps; no migration. Hom9 also fixed 3 defects in the Lua-error-mid-build path (details lost; review checks them).
- Contacts: Hunting Buddy rn-323e75f78948, Overlord Red2 rn-657b4dc593d4 (merge slot), Crafting Buddy (H3 consumer).
