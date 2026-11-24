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
- idea-716+719 IN FLIGHT (Roa2 under R13, worker rn-f306e4916db0, branch roads-supplies; scope fixed by crafting-01 rulings :30/:32, no separate plan file). Buddy shape: flat config prices, unlimited stock, no shortage feed; charge with the post's region_id; fh_charge_busy = plain refusal; refund in full if addItem fails. CONSTRAINT for its done-check (Roa2): spec/crafting_sources_spec.lua:14 PENDING lists 9 roads items (lumber, nails, lead, casings, resource_gunpowder, herb_american_ginseng, herb_oregano, herb_red_sage, herb_wild_mint → idea-716); the block that sources any of them removes them from PENDING in the same branch, or the spec fails. gun_parts = idea-717 (not roads).
- (none blocking) Inbox follow-ups for a later plan: idea-669 (r5 lows), idea-676 (R4 abandon/check reorder). Card notes for the owner's playtest: step 10 needs Hunting's pelt flow; off-road wheel break is an inactive TODO.

## In flight
- 2026-11-23 roads-01 COMPLETE. Slot A (r1+r5+R6) main b06fc58; slot B (r3+r2+R4+R7) main 9a9ed6c, docs 081d746; specs 63/1270/0; `roads playtest-ready 9a9ed6c` logged; OWNER-TESTS `## Roads` card (migrations 0008, 0013, 0014). idea-617 closed, hash sent to Hunting. Lead Roa2 rn-5f1d358a6c1c idle. Awaiting the owner's playtest.
- 2026-11-23 Lows PASS: roads-lows (idea-669 fh_heat saveAwait + spec lock reuse, idea-676 freight busy-flag order) ff-merged to local main 10086d2 (from 69133cd). Gemini PASS 0/0/0; range-diff 2/2 '='; venv 68/1340/0.
- 2026-11-23 Supplies PASS: roads-supplies (idea-716/719 trade-post supplies buy side) ff-merged to local main e9bc8ee (from 7680103). Gemini PASS 0/0/1 7c0894e (low -> idea-725); range-diff '!' only crafting_sources PENDING={} + msg; venv 72/1400/0.
- 2026-11-23 idea-725 PASS: roads-725 (fh_trade reason() trade-neutral wording, +2/-2) ff-merged to local main 2182e31 (from 3c9359d). Lead review accepted by Overlord; no doc/spec text hits; venv 73/1407/0.
- 2026-11-24 idea-762 PASS: roads-762 (fh_trade seed only unpersisted region/items; no seed on load failure) ff-merged to local main e6b9ab7 (from 87f115e). Gemini PASS 0/0/1 0f0c9ec (low -> idea-792); range-diff '='; venv 78/1460/0, syntax 180/0.
