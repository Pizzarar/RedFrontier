# Brainstorm Summary · ROADS (`roads`)

> Rolling team brief (< ~5k tokens). Updated on every decision.

## Who's here
- Brainstorm: Roads
- Lead: ★ Roa4
- Workers: 2

## Done when
- M4 + M5 (spec §6) code-complete: specs green, `## Roads` card in OWNER-TESTS.md, `decision roads playtest-ready <hash>` logged.

## Decided
- 2026-11-25 R13 call (b): contracts gate = regional getTier only; contracts_t2/t3 canUnlock dropped (heartlands-bound); kill switch = fh_trade freight.t2/t3.enabled. Told @progression the ids are unused.
- 2026-11-25 roads-02 merged+pushed main a447017, playtest-ready logged (card steps 25-31).
- 2026-11-25 roads-03 (plans/roads-03-regional-freight.md): destinations from FhRegions posts; contract tier gate is regional (getTier(src, origin) plus global canUnlock); T3 = 2x T2; fail closed to T1.
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
- idea-716+719 IN FLIGHT (Roa2 under R13, worker rn-f306e4916db0, branch roads-supplies; scope fixed by crafting-01 rulings :30/:32, no separate plan file). Buddy shape: flat config prices, unlimited stock, no shortage feed; charge with the post's region_id; fh_charge_busy = plain refusal; refund in full if addItem fails. CONSTRAINT for its done-check (Roa2): spec/crafting_sources_spec.lua:14 PENDING lists 9 roads items (lumber, nails, lead, casings, resource_gunpowder, herb_american_ginseng, herb_oregano, herb_red_sage, herb_wild_mint → idea-716); the block that sources any of them removes them from PENDING in the same branch, or the spec fails. gun_parts = idea-717 (not roads).
- (none blocking) Inbox follow-ups for a later plan: idea-669 (r5 lows), idea-676 (R4 abandon/check reorder). Card notes for the owner's playtest: step 10 needs Hunting's pelt flow; off-road wheel break is an inactive TODO.

## In flight
- 2026-11-25 roads-03 handed to Roa3 rn-c9b952c0fd51 (R12→R13→R14 stacked, R15 last). Latest plan file = roads-03.
- 2026-11-25 roads-03 PASS (Roa4): R12 a2b0c2e, R13 f77511f (tierA), R14 ce8c86d, R15 card steps 32-35; merged via Red4 slot.
