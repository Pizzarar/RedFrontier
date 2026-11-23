# Brainstorm Summary · PROGRESSION (`progression`)

> Rolling team brief (< ~5k tokens). Updated on every decision.

## Who's here
- Brainstorm: Progression
- Lead: Prg Lead · L9 progression
- Workers: 0

## Done when
- Spec M7 slice: rep tier gate (`canUnlock`), roving fence on schedule with rare parts + treasure leads, one hired hand on a timer. Specs green, Gemini PASS, merged local main, OWNER-TESTS progression section, `decision progression playtest-ready <hash>` logged.

## Decided
- Plan: docs/brainstorm/plans/progression-01-l9.md (P0 core request → P1 fh_progression → P2 fh_fence ∥ P3 fh_hands → P4 tests).
- Overlord rules: vs worktree units; merge only after PASS + rebase + run-specs green; one lane merges at a time; tests in OWNER-TESTS.md progression section (not README); no push; log playtest-ready.
- fh_economy has only pay/rep (+rep_changed event). Asked @core for getRep + charge (idea-600); read-only shim until then.
- Reuse fh_spike_gated for fence NPC spawn. Fence shop = ox_lib menu stopgap, @ui screen follow-up (idea-601).
- Hand's first task = chest feed top-up (troughs unowned).

## Open
- Trough task for fh_hands once a lane owns troughs.
- (orig ask) L9 fh_fence + fh_hands + rep-tier unlocks on top of @core's fh_economy ledger: regional rep tiers, roving fence on a schedule (stops, not real driving), rare parts/treasure leads, hired hands as timers automating upkeep. Insurance stays with @core fh_death. Spec: docs/FRONTIER_HOMESTEAD_SPEC.md. Owner: build everything autonomously, Aub tests only at the end. Use @core §4 APIs only (fh_core containers, fh_buffs, fh_economy, regions, events); contract changes = request to @core. Anything waiting on in-game spike results goes behind one config flag. Pure-Lua specs (tools/run-specs.py) + in-game test card in README. No push.

## In flight
- FORGE FREEZE: lead drained, 'drained forge-freeze progression' sent to Overlord rn-5930636cd935. Lead Prg rn-cf119741f978 idle. Core B7 (getRep/charge, idea-600) still pending; P2/P3 debits return charge_unavailable until it merges.
- PARKED (forge freeze 2026-11-22), all worktrees clean, nothing merged, nothing pushed:
  - prog-p1 aef3632: P1 review fixes done (was FAIL 2/2/2 802dd2b), needs Gemini re-review. Specs green (17/274).
  - prog-p2 8a9611e (on 802dd2b): P2 fence, Gemini FAIL 2/2/3 (fence_stash per-player lock/dupe race + more). Needs fixes + rebase on prog-p1. Specs green.
  - prog-p3 d76a817 (on 802dd2b): P3 hands, Gemini FAIL 2/3/2 (double-charge/persistence races in processOwner/load/save + more). Needs fixes + rebase on prog-p1. Specs green.
  - Resume: send P2/P3 review findings (vs status rn-27c91b8a6c9b / rn-2733cf6127b7) to Prg3/Prg4, re-review P1, then P1b after Core B7, then P4.
