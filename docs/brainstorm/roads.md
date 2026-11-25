# Brainstorm Summary · ROADS (`roads`)

> Rolling team brief (< ~5k tokens). Updated on every decision.

## Who's here
- Brainstorm: Roads
- Lead: ★ Roa3
- Workers: 0

## Done when
- M4 + M5 (spec §6) code-complete: specs green, `## Roads` card in OWNER-TESTS.md, `decision roads playtest-ready <hash>` logged.

## Decided
- 2026-11-24 R8r delivered: wagon_t3 on main ae3f6a2 (progression G1; tiers for 4 regions).
- 2026-11-24 R9: T2 locked shown globally ([T2] tag), real gate at accept; per-player display queued to @quests inbox. T2 pay target ≈ 3x T1 per trip, spec-bounded ≤ 4x (qty by slots + pay cap).
- 2026-11-24 roads-02 = M7 roads slice via fh_progression canUnlock (wagon_t2/t3, contracts_t2), fail closed, soft dep. Off-road natives, ungated chase (@spikes), supplies shortage feed = out of scope.
- 2026-11-22 Plan roads-01 (docs/brainstorm/plans/roads-01-cargo-trade-heat.md): R0 core request, R1 fh_cargo wagons+tiers+fast-travel veto, R2 wheel/hammer, R3 fh_trade prices, R4 freight contracts+board data, R5 fh_heat, R6 roadblocks (+chase gated), R7 test card.
- Reuse fh_spike_gated (no new flag): S2 chase + S3 native wheel break gated (RESULT lines empty).
- Fast travel = `exports.fh_cargo:canFastTravel` veto contract; no fast-travel system built here.
- R4 freight = job type for @quests fh_quests (soft dep, fh:trade:contract_* events); no roads board.
- idea-617 (@hunting): R1 adds `exports.fh_cargo:nearestWagon(src, coords, range) -> ref|nil`, LOCKED (coords nil = ped pos, range cap 25m, never throws), confirmed to Hunting; send merge hash when R1 lands.
- 2026-11-23 R4 cargo removal = fh_core:removeItem(wagonRef, name, n) from core-b7 (README:168); drop-bag workaround dropped (could never work). R4 merges after B7.
- 2026-11-23 R4 contract source moved to fh_quests README quests-q5 0adc9aa (Quests lead): state.quest_id + state.progress.job.key (no state.id); abandon also undoes a failed accept (pull the cargo, drop the contract row); rewards money+rep only (items wait on core idea-643); route/cargo/deadline live in fh_trade's contract table; hooks never call fh_quests start/abandon/acceptOffer/talk. Earlier: R4 shape settled (fh_quests README quests-q1 d277f55): freight = `registerJobType('freight', {offers,accept,onEvent,abandon,events})`, soft dep, quest id `job:freight:<key>`, timeout/loss emit `fh:trade:contract_failed`, payout via fh_quests engine.apply. Plan R4 row updated.
- Overlord rules: vs worktree units, rebase + run-specs green before local-main merge, one lane at a time, OWNER-TESTS `## Roads` only, no push, log playtest-ready.

## Open
- roads-03 candidate: T3 freight (contracts_t3, no consumer yet) + freight destinations for bayou_nwa (saint_denis_post) and great_plains (blackwater_post); today only heartlands + scarlett_meadows. Unlocks are heartlands-only: consider per-region unlock ids with @progression.
- idea-716+719 IN FLIGHT (Roa2 under R13, worker rn-f306e4916db0, branch roads-supplies; scope fixed by crafting-01 rulings :30/:32, no separate plan file). Buddy shape: flat config prices, unlimited stock, no shortage feed; charge with the post's region_id; fh_charge_busy = plain refusal; refund in full if addItem fails. CONSTRAINT for its done-check (Roa2): spec/crafting_sources_spec.lua:14 PENDING lists 9 roads items (lumber, nails, lead, casings, resource_gunpowder, herb_american_ginseng, herb_oregano, herb_red_sage, herb_wild_mint → idea-716); the block that sources any of them removes them from PENDING in the same branch, or the spec fails. gun_parts = idea-717 (not roads).
- (none blocking) Inbox follow-ups for a later plan: idea-669 (r5 lows), idea-676 (R4 abandon/check reorder). Card notes for the owner's playtest: step 10 needs Hunting's pelt flow; off-road wheel break is an inactive TODO.

## In flight
- R9 balance 0d36163 (T2 = 3x T1 exactly; range $315..$6993, top end from R3 shortage); R10 6b19dfc; R8 live t3; R11 card in progress → reviews → merge slot.
- 2026-11-24 roads-02 (docs/brainstorm/plans/roads-02-rep-unlocks.md) handed to Roa3 rn-c9b952c0fd51: R8 wagon tier gate, R9 T2 freight, R10 lane SPEC/TASKS seed, R11 card. Latest plan file = roads-02.
- 2026-11-23 roads-01 COMPLETE. Slot A (r1+r5+R6) main b06fc58; slot B (r3+r2+R4+R7) main 9a9ed6c, docs 081d746; specs 63/1270/0; `roads playtest-ready 9a9ed6c` logged; OWNER-TESTS `## Roads` card (migrations 0008, 0013, 0014). idea-617 closed, hash sent to Hunting. Lead Roa2 rn-5f1d358a6c1c idle. Awaiting the owner's playtest.
- 2026-11-23 Lows PASS: roads-lows (idea-669 fh_heat saveAwait + spec lock reuse, idea-676 freight busy-flag order) ff-merged to local main 10086d2 (from 69133cd). Gemini PASS 0/0/0; range-diff 2/2 '='; venv 68/1340/0.
- 2026-11-23 Supplies PASS: roads-supplies (idea-716/719 trade-post supplies buy side) ff-merged to local main e9bc8ee (from 7680103). Gemini PASS 0/0/1 7c0894e (low -> idea-725); range-diff '!' only crafting_sources PENDING={} + msg; venv 72/1400/0.
- 2026-11-23 idea-725 PASS: roads-725 (fh_trade reason() trade-neutral wording, +2/-2) ff-merged to local main 2182e31 (from 3c9359d). Lead review accepted by Overlord; no doc/spec text hits; venv 73/1407/0.
- 2026-11-24 idea-762 PASS: roads-762 (fh_trade seed only unpersisted region/items; no seed on load failure) ff-merged to local main e6b9ab7 (from 87f115e). Gemini PASS 0/0/1 0f0c9ec (low -> idea-792); range-diff '='; venv 78/1460/0, syntax 180/0.
- 2026-11-24 idea-792 PASS: roads-792 (spec/trade_server_spec.lua, stubbed-server spec for fh_trade seedShortages(load()) wiring) ff-merged to main 2866850 by Red3 (already on 34214ab). Gemini PASS 0/0/1 (low -> idea-793); venv 79/1465/0, syntax 180/0.
- 2026-11-24 idea-793 PASS: roads-793 (trade_server_spec strict quote helper, Gemini low on 2866850) ff-merged to main 2b682f2 (from 4f14bd2). Gemini PASS 0/0/0; range-diff =; venv 79/1465/0.
- 2026-11-25 roads-02 PASS (M7 rep unlocks): R8 fh_cargo t2/t3 wagon gate 21b2d7e, R9 fh_trade T2 freight (3x T1, cap 4x) c0299e4, R10 lane SPEC/TASKS 6356a56, R11 OWNER-TESTS ## Roads M6 steps 25-31 c2f20d2; Gemini PASS 0/0/0 on R8/R9/R10 deltas; range-diff all =; stacked on d870ee2.
