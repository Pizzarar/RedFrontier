# Brainstorm Summary · ROADS (`roads`)

> Rolling team brief (< ~5k tokens). Updated on every decision.

## Who's here
- Brainstorm: Roads
- Lead: Roads Lead
- Workers: 3

## Done when
- M4 + M5 (spec §6) code-complete: specs green, `## Roads` card in OWNER-TESTS.md, `decision roads playtest-ready <hash>` logged.

## Decided
- 2026-11-22 Plan roads-01 (docs/brainstorm/plans/roads-01-cargo-trade-heat.md): R0 core request, R1 fh_cargo wagons+tiers+fast-travel veto, R2 wheel/hammer, R3 fh_trade prices, R4 freight contracts+board data, R5 fh_heat, R6 roadblocks (+chase gated), R7 test card.
- Reuse fh_spike_gated (no new flag): S2 chase + S3 native wheel break gated (RESULT lines empty).
- Fast travel = `exports.fh_cargo:canFastTravel` veto contract; no fast-travel system built here.
- R4 freight = job type for @quests fh_quests (soft dep, fh:trade:contract_* events); no roads board. Shape to settle with @quests Buddy.
- idea-617 (@hunting): R1 adds `exports.fh_cargo:nearestWagon(src, coords, range) -> ref|nil`, LOCKED (coords nil = ped pos, range cap 25m, never throws), confirmed to Hunting; send merge hash when R1 lands.
- Overlord rules: vs worktree units, rebase + run-specs green before local-main merge, one lane at a time, OWNER-TESTS `## Roads` only, no push, log playtest-ready.

## Open
- L6+L7 fh_cargo, fh_trade, fh_heat: cargo-class wagon loading, fast-travel block, wagon tiers, wheel break/repair (gated on S-wheel), regional shortage prices, freight contracts + contract board data, faction heat/decay/bounty, chokepoint roadblocks; mounted chase only behind the S-chase flag. Uses @core fh_zones/regions. Spec: docs/FRONTIER_HOMESTEAD_SPEC.md. Owner: build everything autonomously, Aub tests only at the end. Use @core §4 APIs only (fh_core containers, fh_buffs, fh_economy, regions, events); contract changes = request to @core. Anything waiting on in-game spike results goes behind one config flag. Pure-Lua specs (tools/run-specs.py) + in-game test card in README. No push.

## In flight
- 2026-11-23 FORGE FREEZE (Aub via Hub15): nothing new started; lead told to commit WIP, park, update this section with branch+hash and reply 'drained forge-freeze roads'. Overlord pushes. Parked branches (unmerged, unpushed): roads-r1 32817e7 (R1+fixes+nearestWagon, WIP commit), roads-r2 884f19e, roads-r3 b278526, roads-r5 0def2aa. Resume = re-review r1 fixes, r2, r3, r5 → rebase+merge one at a time → R4 (fh_quests job type), R6, R7.
- R0 accepted as Core B7 (core-02-contracts-batch.md, Cor3 dispatching, pings on merge): wagon spawn kind, registerItems (items from fh_cargo/fh_trade, not fh_core config), removeItem, economy charge/getRep, heat admin delegate. Spike-gated.md append OK. Relayed to Roads Lead.
- Roads Lead rn-764dca5ae384 spawned on roads-01, R1 first.
- PARKED (forge freeze 2026-11-22), nothing merged to main, all committed, no push:
  - roads-r1 @ 32817e7 (8c355fc R1 + 68332be review fixes + 3cd2de9 nearestWagon idea-617, specs green 286). Review PASS 0/1/3 on 8c355fc; fixes + nearestWagon need re-review before merge.
  - roads-r2 @ 884f19e (R2 wheel/hammer, on 8c355fc; needs rebase onto r1 + review).
  - roads-r3 @ b278526 (R3 fh_trade prices; review not run).
  - roads-r5 @ 0def2aa (R5 fh_heat; review not run). r3+r5 both use migration 0005_* (name-keyed, harmless).
  - Not started: R4 (fh_quests job-type reshape), R6, R7.
