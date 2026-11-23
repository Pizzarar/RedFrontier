# Brainstorm Summary · REDFRONTIER (`redfrontier`)

> Rolling team brief (< ~5k tokens). Updated on every decision.

## Who's here
- Brainstorm: RiffBot
- Lead: ★ Red2
- Workers: 0

## Done when
- Every lane in the spec (L0–L10) is merged on local main, with one install/start doc (OWNER-STEPS.md) and one combined test card. Then Aub playtests. The Overlord owns this gate.

## Decided
- 2026-11-22: optimize for owner time-to-first-play. @core carries M0 straight into the M1 slice; @spikes = 5-min in-game probes on Core's dev server.
- 2026-11-22: machine split. DevPC hosts repo + FXServer + MariaDB + key. Main PC runs RDR2 + RedM client only, connects on :30120. No push needed to play.
- 2026-11-22 (Overlord, from Aub): go autonomous. Live-boot hold lifted for work that needs no in-game check; spike-dependent code goes behind a config flag.
- 2026-11-23 (Aub): "spin up and do whatever... all parts ready for me to test". Build every lane now, Aub tests once at the end, no clicks from him before that.
- Lane map: @core (fh_core, fh_inventory, fh_buffs, fh_economy ledger, M1 fh_zones/fh_death, insurance), @spikes, @survival L2, @homestead L1, @crafting L5, @roads L6+L7, @hunting L8, @progression L9 fence/hands/rep tiers, @ui L10.
- Sync contract: fh_homestead moves @core -> @homestead after core B6d. @homestead ships the station-slot API (used by @crafting) and comfort score (used by @survival, @hunting). @ui owns all NUI screens; lanes ship data/events. One spike flag per lane.
- Push to Pizzarar/RedFrontier: Aub's call (blocked by the auto-mode check).

- 2026-11-23 Overlord integration rules (all lanes): vs worktree units only; merge to local main after review PASS + rebase + run-specs green, log hash; one lane merges at a time; core B6b-g on main 06f2d3b, so fh_homestead now belongs to @homestead; in-game checks only in OWNER-TESTS.md (lane section); no push; ready = 'decision <lane> playtest-ready <hash>'.
- 2026-11-23 Aub: wiki + quests (repeatable jobs board + one-time family questlines) + optional intro tutorial. 'Story missions' non-goal amended in the spec. @quests owns fh_quests + jobs board; @roads freight and @hunting bear feed it via events; @guide owns docs/wiki + fh_tutorial (finishes last).

## Open
- Spike verdicts S1/S2 still need Aub in-game; flags flip after.

## In flight
- 2026-11-23 PASS merge queue (Red2): quests, core C3c+C3a/b, survival S1-S3b, guide W1-W2, progression P1-P4, roads A, hunting H2-H6, homestead H1-H5, crafting C1-C6 on main 2775580 (59/1205/0, migs to 0012). playtest-ready: @guide 415a736, @core 018df02, @ui db06ed0, @quests b53979a, @homestead 2775580, @roads 9a9ed6c, @hunting 5c70876, @survival e9a2efc, @progression 7c66833, @crafting 9211816.
- 2026-11-23 PASS playtest gate (Red2): late merges core K1, roads supplies (idea-716), homestead H2c/H2d, then OWNER-STEPS/OWNER-TESTS gate docs e3d83de on main (73/1407/0, migs to 0015). Owner playtest ready; no push.
- 2026-11-23 PASS @core: B-access 495621d, B7 334642c, idea-614 b63a340 merged local main (specs 23/431/0). Specs unblocked via user-site lupa 2.8 wheel. Merge queue: ui > quests > guide > progression > hunting > homestead; roads/survival/crafting on ask.
- 2026-11-23 C2 cutover: Overlord rn-01cad4e19b2b spawned (Lead - Claude); restart order core B7 → ui U2/U3 → survival S1 → quests/guide Buddies.
- FORGE FREEZE (2026-11-23, owner via Overlord): hub parked. No new spin-offs or routing until cutover is done. Hub has no workers or worktrees. Pending at freeze: @quests/@guide Buddy start (if not already started). Uncommitted at freeze in primary checkout (main): all lane briefs + plans under docs/brainstorm/, spec non-goal amendment; flagged to Overlord to commit before push.

## Teams
- @core (Cor2 rn-428940b6f1c5): M0 done (§4 contracts, 179 specs). Next: B4c flagged → B6b camp ∥ B6c death → B6d.
- @spikes: S1–S5 probes PASS in code, waiting on Aub in-game.
- @survival (Buddy rn-62b9920d6289): started.
- @quests, @guide: pinned 2026-11-23, waiting for the Overlord to start their Buddies.
- @homestead, @crafting, @roads, @hunting, @progression, @ui: Buddies live 2026-11-23, designing.

## Unsplit threads
- Spec: docs/FRONTIER_HOMESTEAD_SPEC.md (owner, 2026-11-22). Priority #3 behind VibeSquad, EFI.
- Hub feasibility read (2026-11-22): M0 + M1 slice feasible; biggest unknowns = rsg-inventory vs fh_core container ownership, owner-as-only-tester bottleneck, mounted wagon chase AI, homestead "clearing" of world objects.
- §4 contracts merged in @core (B4a container API, B4b ledger/buffs/regions/events; main 6307f28+). Only B4c spawn contract still flagged on S1.
- NEXT LANE lined up (2026-11-22): L2 Survival (`fh_survival`). Needs only fh_buffs.apply/get (fh_buffs/README.md). Owns fh_survival only; fh_buffs client effects (currently a stub) go via contract request to @core. Well-Rested-from-comfort waits on L1 comfort score. Spin-off block posted, waiting on owner click.
- Later: L5 Weapons/Crafting (needs homestead station slots), L10 UI shell, L8 Hunting (needs S2 pelt verdict). L4 death and L3 zones stay inside @core (M1 slice).
