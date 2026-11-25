# Brainstorm Summary · HOMESTEAD (`homestead`)

> Rolling team brief (< ~5k tokens). Updated on every decision.

## Who's here
- Brainstorm: Homestead
- Lead: ★ Hom3
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
- (none in lane) Parked/elsewhere: nails.png idea-724; owner in-game checks = OWNER-TESTS homestead cards (plots, props, lots); stale homestead worktrees (pre-rebase hashes) need manual sweep, owner OK first.

## In flight
- PASS/MERGED homestead-04 H18 garden pure rules: cc2f603 (PASS 0/1/3 3e3e341; carrot allowlist stopgap idea-1008 @survival). H19 finishing (Hom40), H20a fixing review FAIL.
- PASS/MERGED homestead-04 H19 garden server + migration 0021: d035a92 (PASS 0/0/0 0863d03). H20a PASS (53b1cb8 delta); H20b building (Hom43).
- PASS/MERGED homestead-04 H20 trough (H20a+H20b, 7 commits 61015ec..4866324 + slot commit, migration 0024): PASS 0/0/0 53b1cb8, 0/0/2 2bc08bf, 0/0/2 74c5954, 0/0/0 fdc75fc. feedTrough export (writes stay in homestead), getTrough read-only, refill flagged off. Next: H21 @progression.
- NOW: homestead-04 working homestead (plans/homestead-04-working-homestead.md): H18 MERGED cc2f603, H19 MERGED d035a92 (0021, idea-916 closed), H20 trough MERGED (0024). Remaining: H21 request to @progression (fh_hands feed_topup -> feedTrough), then playtest-ready. Owner Q: both/garden only/neither (default both, no answer). Disk 97%: owner must run `vs worktree sweep --apply` (needs-you logged).
- PASS/DONE homestead-03 complete: H14b merged a37a9c3+d5a0756 (PASS 0/1/2 913291e + delta PASS 0/0/0 32208d8; 129/2335/0). Logged `homestead homestead-03 playtest-ready d5a0756`. Next: Buddy plans homestead-04 (idea-916 farming candidate). Core follow-up idea-970.
- homestead-03 home hygiene (plans/homestead-03-home-hygiene.md): MERGED + pushed H16 (8d445f8, db07231), H13+H13b (68b815b, 24c4080, 6e2e898). H15 MERGED + pushed (36e9c42; PASS f6b7db6 + delta PASS e1b449a; 106/1976/0). H17 stationAt type + coords (idea-893) MERGED + pushed 13798db (PASS 0/0/0 2a4046a); Sur2 told, idea-893 archived. @a-life AL2 adds plotInfo coords/region/fenceBuilt (main.lua:577) on their side (a-life-03 C0), additive only, Hom3's conditions. H14a DELIVERED by core-03 C3a (9beb4c0): removeItem({type='backpack', id=src}, item, n), one section only. H17 MERGED 13798db (idea-893 closed). H14b PASS 0/1/2 913291e, M+2L folded in 32208d8, delta review rn-039c3850c771; then slot, then playtest-ready. fh_inventory addItem false-failure → @core idea-970. Hom3 hit 5h limit (resets 10:20Z). homestead-04 proposal to owner: garden slot (idea-916 veg for crafting) then trough slot (horse refill; hands feed trough not chest, removes fh_hands workaround). Awaiting owner pick.
- Owner Qs (non-blocking, defaults stand): lot trophies/extra slots = no; admin force-unclaim = clear items (logged).
- DONE: homestead-01 (H1-H5 + H2b/c/d) and homestead-02 town lots (H6-H12 incl. H9b, repByCitizenid rep-back, /where lot 3307497) on main, pushed, tip deb80ca, specs 86/1588/0. Logged `homestead town-lots playtest-ready deb80ca` 2026-11-24T17:13Z.
- Lead Hom3 rn-8ca5c7592ea0 (took over from Hom2 2026-11-24). Routing: normal builds plain Implement (A/B Sonnet/Gemini), tierA Implement - Opus pinned; review by the other provider; no DeepSeek. Slot work only in the worktree (push HEAD:main), no git writes in the main checkout. Overlord = `vs who lead --lane redfrontier` (Red4 now). Specs only via ~/.venvs/rf/bin/python. Migrations = main highest+1 at merge (main highest 0024, homestead trough).
- Contacts: Hunting Buddy rn-323e75f78948, Crafting Buddy (stations), @a-life Ali1 (lawSafeAt consumer), @world Wor1 (plot/lot config, /where).
