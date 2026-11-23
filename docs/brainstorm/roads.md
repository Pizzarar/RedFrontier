# Brainstorm Summary · ROADS (`roads`)
- 2026-11-23 Lows PASS: roads-lows (idea-669 fh_heat saveAwait + spec lock reuse, idea-676 freight busy-flag order) ff-merged to local main 10086d2 (from 69133cd). Gemini PASS 0/0/0; range-diff 2/2 '='; venv 68/1340/0.

- 2026-11-23 Lows PASS: roads-lows (idea-669 fh_heat saveAwait + spec lock reuse, idea-676 freight busy-flag order) ff-merged to local main 10086d2 (from 69133cd). Gemini PASS 0/0/0; range-diff 2/2 '='; venv 68/1340/0.
> Rolling team brief (< ~5k tokens). Updated on every decision.
- 2026-11-23 Lows PASS: roads-lows (idea-669 fh_heat saveAwait + spec lock reuse, idea-676 freight busy-flag order) ff-merged to local main 10086d2 (from 69133cd). Gemini PASS 0/0/0; range-diff 2/2 '='; venv 68/1340/0.

- 2026-11-23 Lows PASS: roads-lows (idea-669 fh_heat saveAwait + spec lock reuse, idea-676 freight busy-flag order) ff-merged to local main 10086d2 (from 69133cd). Gemini PASS 0/0/0; range-diff 2/2 '='; venv 68/1340/0.
## Who's here
- 2026-11-23 Lows PASS: roads-lows (idea-669 fh_heat saveAwait + spec lock reuse, idea-676 freight busy-flag order) ff-merged to local main 10086d2 (from 69133cd). Gemini PASS 0/0/0; range-diff 2/2 '='; venv 68/1340/0.
- Brainstorm: Roads
- 2026-11-23 Lows PASS: roads-lows (idea-669 fh_heat saveAwait + spec lock reuse, idea-676 freight busy-flag order) ff-merged to local main 10086d2 (from 69133cd). Gemini PASS 0/0/0; range-diff 2/2 '='; venv 68/1340/0.
- Lead: ★ Roa2
- 2026-11-23 Lows PASS: roads-lows (idea-669 fh_heat saveAwait + spec lock reuse, idea-676 freight busy-flag order) ff-merged to local main 10086d2 (from 69133cd). Gemini PASS 0/0/0; range-diff 2/2 '='; venv 68/1340/0.
- Workers: 0
- 2026-11-23 Lows PASS: roads-lows (idea-669 fh_heat saveAwait + spec lock reuse, idea-676 freight busy-flag order) ff-merged to local main 10086d2 (from 69133cd). Gemini PASS 0/0/0; range-diff 2/2 '='; venv 68/1340/0.

- 2026-11-23 Lows PASS: roads-lows (idea-669 fh_heat saveAwait + spec lock reuse, idea-676 freight busy-flag order) ff-merged to local main 10086d2 (from 69133cd). Gemini PASS 0/0/0; range-diff 2/2 '='; venv 68/1340/0.
## Done when
- 2026-11-23 Lows PASS: roads-lows (idea-669 fh_heat saveAwait + spec lock reuse, idea-676 freight busy-flag order) ff-merged to local main 10086d2 (from 69133cd). Gemini PASS 0/0/0; range-diff 2/2 '='; venv 68/1340/0.
- M4 + M5 (spec §6) code-complete: specs green, `## Roads` card in OWNER-TESTS.md, `decision roads playtest-ready <hash>` logged.
- 2026-11-23 Lows PASS: roads-lows (idea-669 fh_heat saveAwait + spec lock reuse, idea-676 freight busy-flag order) ff-merged to local main 10086d2 (from 69133cd). Gemini PASS 0/0/0; range-diff 2/2 '='; venv 68/1340/0.

- 2026-11-23 Lows PASS: roads-lows (idea-669 fh_heat saveAwait + spec lock reuse, idea-676 freight busy-flag order) ff-merged to local main 10086d2 (from 69133cd). Gemini PASS 0/0/0; range-diff 2/2 '='; venv 68/1340/0.
## Decided
- 2026-11-23 Lows PASS: roads-lows (idea-669 fh_heat saveAwait + spec lock reuse, idea-676 freight busy-flag order) ff-merged to local main 10086d2 (from 69133cd). Gemini PASS 0/0/0; range-diff 2/2 '='; venv 68/1340/0.
- 2026-11-22 Plan roads-01 (docs/brainstorm/plans/roads-01-cargo-trade-heat.md): R0 core request, R1 fh_cargo wagons+tiers+fast-travel veto, R2 wheel/hammer, R3 fh_trade prices, R4 freight contracts+board data, R5 fh_heat, R6 roadblocks (+chase gated), R7 test card.
- 2026-11-23 Lows PASS: roads-lows (idea-669 fh_heat saveAwait + spec lock reuse, idea-676 freight busy-flag order) ff-merged to local main 10086d2 (from 69133cd). Gemini PASS 0/0/0; range-diff 2/2 '='; venv 68/1340/0.
- Reuse fh_spike_gated (no new flag): S2 chase + S3 native wheel break gated (RESULT lines empty).
- 2026-11-23 Lows PASS: roads-lows (idea-669 fh_heat saveAwait + spec lock reuse, idea-676 freight busy-flag order) ff-merged to local main 10086d2 (from 69133cd). Gemini PASS 0/0/0; range-diff 2/2 '='; venv 68/1340/0.
- Fast travel = `exports.fh_cargo:canFastTravel` veto contract; no fast-travel system built here.
- 2026-11-23 Lows PASS: roads-lows (idea-669 fh_heat saveAwait + spec lock reuse, idea-676 freight busy-flag order) ff-merged to local main 10086d2 (from 69133cd). Gemini PASS 0/0/0; range-diff 2/2 '='; venv 68/1340/0.
- R4 freight = job type for @quests fh_quests (soft dep, fh:trade:contract_* events); no roads board.
- 2026-11-23 Lows PASS: roads-lows (idea-669 fh_heat saveAwait + spec lock reuse, idea-676 freight busy-flag order) ff-merged to local main 10086d2 (from 69133cd). Gemini PASS 0/0/0; range-diff 2/2 '='; venv 68/1340/0.
- idea-617 (@hunting): R1 adds `exports.fh_cargo:nearestWagon(src, coords, range) -> ref|nil`, LOCKED (coords nil = ped pos, range cap 25m, never throws), confirmed to Hunting; send merge hash when R1 lands.
- 2026-11-23 Lows PASS: roads-lows (idea-669 fh_heat saveAwait + spec lock reuse, idea-676 freight busy-flag order) ff-merged to local main 10086d2 (from 69133cd). Gemini PASS 0/0/0; range-diff 2/2 '='; venv 68/1340/0.
- 2026-11-23 R4 cargo removal = fh_core:removeItem(wagonRef, name, n) from core-b7 (README:168); drop-bag workaround dropped (could never work). R4 merges after B7.
- 2026-11-23 Lows PASS: roads-lows (idea-669 fh_heat saveAwait + spec lock reuse, idea-676 freight busy-flag order) ff-merged to local main 10086d2 (from 69133cd). Gemini PASS 0/0/0; range-diff 2/2 '='; venv 68/1340/0.
- 2026-11-23 R4 contract source moved to fh_quests README quests-q5 0adc9aa (Quests lead): state.quest_id + state.progress.job.key (no state.id); abandon also undoes a failed accept (pull the cargo, drop the contract row); rewards money+rep only (items wait on core idea-643); route/cargo/deadline live in fh_trade's contract table; hooks never call fh_quests start/abandon/acceptOffer/talk. Earlier: R4 shape settled (fh_quests README quests-q1 d277f55): freight = `registerJobType('freight', {offers,accept,onEvent,abandon,events})`, soft dep, quest id `job:freight:<key>`, timeout/loss emit `fh:trade:contract_failed`, payout via fh_quests engine.apply. Plan R4 row updated.
- 2026-11-23 Lows PASS: roads-lows (idea-669 fh_heat saveAwait + spec lock reuse, idea-676 freight busy-flag order) ff-merged to local main 10086d2 (from 69133cd). Gemini PASS 0/0/0; range-diff 2/2 '='; venv 68/1340/0.
- Overlord rules: vs worktree units, rebase + run-specs green before local-main merge, one lane at a time, OWNER-TESTS `## Roads` only, no push, log playtest-ready.
- 2026-11-23 Lows PASS: roads-lows (idea-669 fh_heat saveAwait + spec lock reuse, idea-676 freight busy-flag order) ff-merged to local main 10086d2 (from 69133cd). Gemini PASS 0/0/0; range-diff 2/2 '='; venv 68/1340/0.

- 2026-11-23 Lows PASS: roads-lows (idea-669 fh_heat saveAwait + spec lock reuse, idea-676 freight busy-flag order) ff-merged to local main 10086d2 (from 69133cd). Gemini PASS 0/0/0; range-diff 2/2 '='; venv 68/1340/0.
## Open
- 2026-11-23 Lows PASS: roads-lows (idea-669 fh_heat saveAwait + spec lock reuse, idea-676 freight busy-flag order) ff-merged to local main 10086d2 (from 69133cd). Gemini PASS 0/0/0; range-diff 2/2 '='; venv 68/1340/0.
- (none blocking) Inbox follow-ups for a later plan: idea-669 (r5 lows), idea-676 (R4 abandon/check reorder). Card notes for the owner's playtest: step 10 needs Hunting's pelt flow; off-road wheel break is an inactive TODO.
- 2026-11-23 Lows PASS: roads-lows (idea-669 fh_heat saveAwait + spec lock reuse, idea-676 freight busy-flag order) ff-merged to local main 10086d2 (from 69133cd). Gemini PASS 0/0/0; range-diff 2/2 '='; venv 68/1340/0.

- 2026-11-23 Lows PASS: roads-lows (idea-669 fh_heat saveAwait + spec lock reuse, idea-676 freight busy-flag order) ff-merged to local main 10086d2 (from 69133cd). Gemini PASS 0/0/0; range-diff 2/2 '='; venv 68/1340/0.
## In flight
- 2026-11-23 Lows PASS: roads-lows (idea-669 fh_heat saveAwait + spec lock reuse, idea-676 freight busy-flag order) ff-merged to local main 10086d2 (from 69133cd). Gemini PASS 0/0/0; range-diff 2/2 '='; venv 68/1340/0.
- 2026-11-23 roads-01 COMPLETE. Slot A (r1+r5+R6) main b06fc58; slot B (r3+r2+R4+R7) main 9a9ed6c, docs 081d746; specs 63/1270/0; `roads playtest-ready 9a9ed6c` logged; OWNER-TESTS `## Roads` card (migrations 0008, 0013, 0014). idea-617 closed, hash sent to Hunting. Lead Roa2 rn-5f1d358a6c1c idle. Awaiting the owner's playtest.
- 2026-11-23 Lows PASS: roads-lows (idea-669 fh_heat saveAwait + spec lock reuse, idea-676 freight busy-flag order) ff-merged to local main 10086d2 (from 69133cd). Gemini PASS 0/0/0; range-diff 2/2 '='; venv 68/1340/0.
