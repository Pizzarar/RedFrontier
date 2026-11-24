# @roads SPEC · Cargo, Trade & Heat (L6 + L7, M4/M5/M7 roads slice)

Source: docs/FRONTIER_HOMESTEAD_SPEC.md §5 L6/L7, §6 M4/M5/M7. Plans: docs/brainstorm/plans/roads-01-cargo-trade-heat.md
(complete), docs/brainstorm/plans/roads-02-rep-unlocks.md (current). Rolling brief: docs/brainstorm/roads.md.

## Goal
Own wagons and hauling (`fh_cargo`), regional trade and freight contracts (`fh_trade`), and faction heat with its
road consequences (`fh_heat`). Use @core §4 APIs only (fh_core containers/spawn/regions/events, fh_economy
pay/charge/rep); a contract change is a request to @core, never an edit in fh_core. Lanes ship data and exports,
@ui ships screens. Pure-Lua specs + the in-game `## Roads` card; Aub tests at the end.

## Scope
- `[fh]/fh_cargo`: wagon tiers (T1 cart / T2 wagon / T3 freight: slots, weight, speed cap), per-wagon fh_core `wagon`
  container, cargo load/unload within reach of own wagon, fast-travel veto, wheel break roll + hammer/wagon_wheel
  repair, `/fh_wagon <tier>` dev spawn, `nearestWagon` for other lanes.
- `[fh]/fh_trade`: regional price model (base × shortage, drift, sell saturation), trade-post sell (fh_economy pay)
  and supplies buy side (flat config prices, fh_economy charge), freight contracts as an fh_quests job type.
- `[fh]/fh_heat`: per-character per-faction heat 0-100 (persisted), sources, lay-low decay, thresholds, bounty payoff
  (fh_economy charge, refund on post-charge failure), roadblocks; night ambush + mounted chase gated.
- roads-02 (M7 slice): rep gates on wagon tiers and T2 freight via `exports.fh_progression:canUnlock`.

## Owned migrations
- `server/migrations/0008_fh_heat.sql` (fh_heat)
- `server/migrations/0013_fh_trade.sql` (fh_trade price state)
- `server/migrations/0014_fh_trade_contracts.sql` (freight contracts)
New migrations take main max+1 at merge time (renumber on rebase, as b06fc58 / 9a9ed6c did).

## Locked export contracts (README per resource is the source of truth)
- `exports.fh_cargo:nearestWagon(src, coords, range) -> ref|nil`: container ref `{ type = 'wagon', id = 'fh:wagon:...' }`
  of the nearest LIVE wagon within `range` m of `coords` (nil = the player's ped) that `src` may load (v1: owner
  only). `range` > 0, capped at 25 m. Bad args return nil, never throw. Consumer: @hunting (idea-617).
- `exports.fh_cargo:canFastTravel(src) -> ok, reason`: blocked `fh_cargo_carried` (carrying cargo) or
  `fh_cargo_wagon_near` (own loaded wagon within 30 m); fails closed (`fh_cargo_unknown`); emits
  `fh:cargo:fasttravel_blocked` `{ src, citizenid, reason, wagon }`. No fast-travel system exists: whoever adds one
  calls this.
- Freight job type: `exports.fh_quests:registerJobType('freight', { offers(region_id), accept(src, offer),
  onEvent(name, payload, state), abandon(src, state), events = { 'fh:trade:contract_delivered',
  'fh:trade:contract_failed' } })`. Soft dep (no `dependencies` entry; registers on onResourceStart of fh_quests or
  self). Quest id `job:freight:<key>`; key from `state.progress.job.key`. Payout only via the fh_quests engine
  (exactly once); fh_trade never pays freight. Hooks never call fh_quests start/abandon/acceptOffer/talk; abandon
  also undoes a failed accept (cargo out via fh_core removeItem, contract row dropped). Events (one table):
  `{ src?, citizenid, key, quest_id, from_region, to_region, item, qty, reward, reason? }`.
- Other exports (spawnWagon, getWagon, quote, getShortages, setShortage, previewSell, listGoods, heat get/set/add/
  addSource/getAll/level/payoff) are documented in each README and may grow; signatures above may not change
  without the consumer lane's sign-off.

## Gated items (`fh_spike_gated` convar, default true; one flag, reused, rows in fh_core/docs/spike-gated.md)
- Mounted wagon chase (S2 spk_chase) and night ambush: no-op + log while gated (fh_heat config).
- Native wheel break (S3 spk_wheel): gated path = break state + speed cap only; ungated adds the native break.
- Flip only after the matching spike RESULT line is GO. Roadblocks are always on.

## Done when
- roads-01 (M4 + M5): DONE. Specs green, `## Roads` card in OWNER-TESTS.md, `roads playtest-ready 9a9ed6c` logged.
- roads-02 (M7 roads slice):
  - R8: `spawnWagon` (and any tier-upgrade path) refuses t2/t3 unless `canUnlock(src, 'wagon_t2'|'wagon_t3')`;
    T1 always allowed; fail closed (`fh_locked`) when fh_progression is not started or canUnlock throws; reason
    shown to the player; specs cover allowed / tier_too_low / not started / throws.
  - R9: freight offers carry `tier`; T2 templates (larger qty, longer route, higher pay, distance-scaled deadline);
    `accept` gates T2 on `canUnlock(src, 'contracts_t2')` and checks the wagon tier fits qty; gated offers listed
    with `locked = true`; T1 always available; specs.
  - R10: this SPEC.md + TASKS.json seeded.
  - R11: OWNER-TESTS `## Roads` has the rep-gate steps (admin set rep → tier 2 → t2 wagon + T2 contract unlock;
    tier 1 refused).
  - `git grep canUnlock` shows fh_cargo + fh_trade consumers; venv specs green
    (`~/.venvs/rf/bin/python tools/run-specs.py`); `vs log decision "roads-02 playtest-ready <hash>"`.

## Dependencies / requests
- @progression R8r: add `wagon_t3 = { region_id = 'heartlands', min_tier = 3 }` to fh_progression config. Until it
  lands, t3 refuses with `unknown_unlock` (correct fail-closed behaviour).
- @core: fh_core removeItem (B7) for cargo removal; spawn kind `wagon` (R0, landed in core B7).

## Out of lane
Fast-travel system itself, NUI screens (@ui), horse ownership/stables, hired hands, supplies shortage pricing,
new regions, ungated chase/ambush and off-road wheel break natives until @spikes S2/S3 RESULT lines, any push.
