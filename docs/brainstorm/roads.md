# Brainstorm Summary · ROADS (`roads`)

> Rolling team brief (< ~5k tokens). Updated on every decision.

## Who's here
- Brainstorm: Roads
- Lead: ★ Roa2
- Workers: 0

## Done when
- M4 + M5 (spec §6) code-complete: specs green, `## Roads` card in OWNER-TESTS.md, `decision roads playtest-ready <hash>` logged.

## Decided
- 2026-11-22 Plan roads-01 (docs/brainstorm/plans/roads-01-cargo-trade-heat.md): R0 core request, R1 fh_cargo wagons+tiers+fast-travel veto, R2 wheel/hammer, R3 fh_trade prices, R4 freight contracts+board data, R5 fh_heat, R6 roadblocks (+chase gated), R7 test card.
- Reuse fh_spike_gated (no new flag): S2 chase + S3 native wheel break gated (RESULT lines empty).
- Fast travel = `exports.fh_cargo:canFastTravel` veto contract; no fast-travel system built here.
- R4 freight = job type for @quests fh_quests (soft dep, fh:trade:contract_* events); no roads board.
- idea-617 (@hunting): R1 adds `exports.fh_cargo:nearestWagon(src, coords, range) -> ref|nil`, LOCKED (coords nil = ped pos, range cap 25m, never throws), confirmed to Hunting; send merge hash when R1 lands.
- 2026-11-23 R4 cargo removal = fh_core:removeItem(wagonRef, name, n) from core-b7 (README:168); drop-bag workaround dropped (could never work). R4 merges after B7.
- 2026-11-23 R4 contract source moved to fh_quests README quests-q5 0adc9aa (Quests lead): state.quest_id + state.progress.job.key (no state.id); abandon also undoes a failed accept (pull the cargo, drop the contract row); rewards money+rep only (items wait on core idea-643); route/cargo/deadline live in fh_trade's contract table; hooks never call fh_quests start/abandon/acceptOffer/talk. Earlier: R4 shape settled (fh_quests README quests-q1 d277f55): freight = `registerJobType('freight', {offers,accept,onEvent,abandon,events})`, soft dep, quest id `job:freight:<key>`, timeout/loss emit `fh:trade:contract_failed`, payout via fh_quests engine.apply. Plan R4 row updated.
- Overlord rules: vs worktree units, rebase + run-specs green before local-main merge, one lane at a time, OWNER-TESTS `## Roads` only, no push, log playtest-ready.

## Open
- Core answered: carried removeItem = core-03 C3a (docs/brainstorm/plans/core-03-carried-api.md); r2/r3 merge after C3a. idea-616(2) wagon {ref,coords} = already covered by nearestWagon + getWagon (r1); told Hunting rn-126fb6e22cc2.
- 2026-11-23 B7 on local main 334642c. GAP: fh_core removeItem refuses carried refs (fh_core inventory.lua:247), so r3 sell (fh_trade main.lua:104) + r2 consumeWheel always fail. Asked Core Buddy rn-08026a3b3247 to allow carried refs. r2 + r3 merges HELD until answered; r1, r5 unaffected. R4 OK (wagons registered).
- Blocked only on python3-lupa on the forge (owner sudo install; core needs-you 15:13Z). Overlord pings specs-ready.
- Post-merge lows: idea-669 (r5's 2 lows; folding them pre-merge would need another tierA review), idea-676 (R4 abandon/check double-removeItem reorder).
- R7 card notes: set `freight.allowSameRegion = true` (single region); destination coords unchecked; step 10 needs Hunting's pelt flow; off-road wheel break = inactive TODO; wagon top-speed 0.0 reset check.

## In flight
- 2026-11-23 ALL BLOCKS REVIEW PASS (static, SPECS BLOCKED). Lead now Roa2 rn-5f1d358a6c1c (handed off from rn-e0ebc05301f3). Specs runnable: ~/.venvs/rf/bin/python tools/run-specs.py. fh_quests on local main b53979a (job contract unchanged; main migrations up to 0007 → renumber r3/r5/R4 at merge).
- Merge order (Overlord-approved, 2 slots; gate = review PASS or '=' range-diff + specs green on ~/.venvs/rf + merge slot): Slot A roads-a = r1 32817e7 + r5 ece580e + R6 54f8f40 (mig 0008_fh_heat), queued in Red2's slot after progression; Roads14 rebasing onto b53979a + spec rerun. Slot B = r3 b278526 + r2 c334bc6 + R4 c790f63 + R7 f92e653, built after core C3a lands, r3/R4 migrations renumbered then. Spec fix 1c9216e (freight stub dot-call) verified.
- After r1 merges: send the hash to the Hunting Buddy, close idea-617.
- 2026-11-23 Slot A PASS: roads-a (r1+r5+R6, mig 0008_fh_heat) ff-merged to local main b06fc58 (from 03516d1). venv 44/862/0; range-diff vs 84e8d0e 7= 2! (server.cfg hunk context only). Slot B pending core C3a.
- Done = all merged + `vs log decision "roads playtest-ready <hash>"`.
