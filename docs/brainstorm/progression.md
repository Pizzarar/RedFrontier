# Brainstorm Summary · PROGRESSION (`progression`)

> Rolling team brief (< ~5k tokens). Updated on every decision.

## Who's here
- Brainstorm: Progression
- Lead: Progression lead · P1-P4 resume
- Workers: 0

## Done when
- Spec M7 slice: rep tier gate (`canUnlock`), roving fence on schedule with rare parts + treasure leads, one hired hand on a timer. Specs green, Gemini PASS, merged local main, OWNER-TESTS progression section, `decision progression playtest-ready <hash>` logged.

## Decided
- Plan: docs/brainstorm/plans/progression-01-l9.md (P0 core request → P1 fh_progression → P2 fh_fence ∥ P3 fh_hands → P4 tests).
- Overlord rules: vs worktree units; merge only after PASS + rebase + run-specs green; one lane merges at a time; tests in OWNER-TESTS.md progression section (not README); no push; log playtest-ready.
- idea-600 delivered: core B7 on local main 334642c (getRep, charge, removeItem). P1b swaps shim to getRep; P2/P3 debits use charge (retry on fh_charge_busy) + removeItem. Sent to lead rn-5dc775ae6f22.
- Reuse fh_spike_gated for fence NPC spawn. Fence shop = ox_lib menu stopgap, @ui screen follow-up (idea-601).
- Hand's first task = chest feed top-up (troughs unowned).

## Open
- Trough task for fh_hands once a lane owns troughs. (2026-11-23: still unowned, only an rsg-core item def. Out of the M7 slice; keep parked.)
- (orig ask) L9 fh_fence + fh_hands + rep-tier unlocks on top of @core's fh_economy ledger: regional rep tiers, roving fence on a schedule (stops, not real driving), rare parts/treasure leads, hired hands as timers automating upkeep. Insurance stays with @core fh_death. Spec: docs/FRONTIER_HOMESTEAD_SPEC.md. Owner: build everything autonomously, Aub tests only at the end. Use @core §4 APIs only (fh_core containers, fh_buffs, fh_economy, regions, events); contract changes = request to @core. Anything waiting on in-game spike results goes behind one config flag. Pure-Lua specs (tools/run-specs.py) + in-game test card in README. No push.

## In flight
- 2026-11-23 P1 PASS 0/0/1 prog-p1 34ace36 (Gemini rn-adef187ccf78; SPECS BLOCKED, no lupa). Merge waits on lupa + slot.
- 2026-11-23 P3 PASS 0/0/2 prog-p3 0ee8d0a on p1 (Gemini rn-158fa422dc56; SPECS BLOCKED). Merge after P1.
- 2026-11-23 P2 PASS 0/0/0 prog-p2 99bb8bf on p1 (Gemini rn-07e02880a7ff; SPECS BLOCKED). Merge after P1; ping UI Buddy (idea-601) on merge.
- 2026-11-23 P4 PASS 0/0/2 prog-p4 b059206 (p3+p2 merge adacb09 + admin cmds + OWNER-TESTS Progression; Gemini rn-7729a72b765a; SPECS BLOCKED). Merge order P1 > P2 > P3 > P4. Left: P1b after core B7 on main.
- 2026-11-23 MERGED P1-P4 to local main (slot from Red2): P1 84087d6, P2 f60805c, P3 f13e710 (hands migration renumbered 0009), P4 ed2cb1e. Venv specs 41/808/0, syntax 18/0, dedupe empty. Not pushed. Next: P1b (Prg16) review, then playtest-ready.
- Freeze lifted. Lead rn-5dc775ae6f22 ack'd B7 -> task prog-p1b (getRep swap, charge + error map + busy retry, fence sell via removeItem, P4 review lows). Order: P1 rebased b63a340 (25/454/0), queued after ui+guide -> merge P2/P3/P4 (reviewed) -> P1b (after Prg9 P2 spec fix; both touch fh_fence trade.lua).
