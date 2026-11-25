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
- roads-04 (wagon ownership): owned wagons table `fh_wagons` (R16), `buyWagon` export charged via fh_economy (refund on
  failure, owed alert never silent), trade-post wagon menu `/wagonpost` with buy / call / stow (R17, one live wagon
  per player, proximity via `exports.fh_trade:nearestPost`), farm supplies carrot / potato / corn at $3 in fh_trade
  supplies (R18). `/fh_wagon` stays the admin dev bypass.

## Owned migrations
- `server/migrations/0008_fh_heat.sql` (fh_heat)
- `server/migrations/0013_fh_trade.sql` (fh_trade price state)
- `server/migrations/0014_fh_trade_contracts.sql` (freight contracts)
- `server/migrations/0022_fh_wagons.sql` (fh_wagons, owned wagons)
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
  onEvent(name, payload, state), abandon(src, state), lockedFor(offer, src), events = { 'fh:trade:contract_delivered',
  'fh:trade:contract_failed' } })`. Soft dep (no `dependencies` entry; registers on onResourceStart of fh_quests or
  self). Quest id `job:freight:<key>`; key from `state.progress.job.key`. Payout only via the fh_quests engine
  (exactly once); fh_trade never pays freight. Hooks never call fh_quests start/abandon/acceptOffer/talk; abandon
  also undoes a failed accept (cargo out via fh_core removeItem, contract row dropped). `lockedFor(offer, src)` is
  display-only (T1 -> nil; gated T2/T3 reuse `tierUnlocked` + kill switches -> nil or `{ min_tier, reason }`, fail
  closed, no wagon check; `accept` stays authoritative). Events (one table):
  `{ src?, citizenid, key, quest_id, from_region, to_region, item, qty, reward, reason? }`.
- `exports.fh_cargo:buyWagon(src, tier, region_id) -> ok, err[, detail]`: buys a wagon tier, charged once at the post's
  region; t2/t3 gated by `canUnlock`; `fh_already_owned` refunds. `exports.fh_trade:nearestPost(src) -> post|nil`:
  the trade post the player stands in (radius + region gate); fh_cargo's post menu depends on it softly (not started =
  `fh_not_at_post`). Client entry `/wagonpost`; events `fh:cargo:wagon_bought`, `fh:cargo:wagon_buy_owed`.
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
    `accept` gates T2 on regional `getTier(src, origin_region) >= 2` with lane-local kill switch (`freight.t2.enabled`)
    and checks the wagon tier fits qty; gated offers listed with `locked = true`; T1 always available; specs.
  - R10: this SPEC.md + TASKS.json seeded.
  - R11: OWNER-TESTS `## Roads` has the rep-gate steps (admin set rep → tier 2 → t2 wagon + T2 contract unlock;
    tier 1 refused).
  - `git grep canUnlock` shows fh_cargo + fh_trade consumers; venv specs green
    (`~/.venvs/rf/bin/python tools/run-specs.py`); `vs log decision "roads-02 playtest-ready <hash>"`.
- roads-03 (regional freight network + T3 contracts):
  - R12: destinations resolved dynamically from `FhRegions.posts` via `FhPlaceResolver.resolvePosts` (with
    `freight.overrides` and `freight.exclude`), connecting enabled post regions (incl. `bayou_nwa` and `great_plains`)
    with route distance >= minDistance; missing coordinates skipped without throwing.
  - R13: freight tier gate = regional `getTier(src, origin_region)` (T2 >= 2, T3 >= 3) with lane-local kill switches
    (`freight.t2.enabled`, `freight.t3.enabled`); wagon tiers still use `canUnlock('wagon_t2'|'wagon_t3')`; fail
    closed (`fh_locked` / `fh_freight_tier_disabled`).
  - R14: T3 freight templates and config (`freight.t3`: `minWagonTier 3`, distance-scaled deadline, pay multiple,
    bounded by specs); `accept` verifies wagon tier fits and checks `minWagonTier 3`.
  - R15: OWNER-TESTS `## Roads` steps added for destinations to Saint Denis and Blackwater (noting unverified destination
    posts from FhRegions `verified = false`), regional tier gate, T3 contracts with t3 wagon, and kill switches.
  - Venv specs green (`~/.venvs/rf/bin/python tools/run-specs.py`); `vs log decision "roads-03 playtest-ready <hash>"`.
- roads-04 (wagon ownership):
  - R16: `fh_wagons` migration 0022 + `buyWagon` (specs `cargo_buy_spec`).
  - R17: `/wagonpost` buy / call / stow, `nearestPost` in fh_trade, one live wagon rule, stow reach (specs).
  - R18: carrot / potato / corn at $3 in fh_trade supplies.
  - R19: OWNER-TESTS `## Roads` steps 36-48 as a non-admin player; this SPEC + TASKS. Venv specs green;
    `vs log decision "roads-04 playtest-ready <hash>"`.

## Dependencies / requests
- @progression R8r: add `wagon_t3 = { region_id = 'heartlands', min_tier = 3 }` to fh_progression config. Until it
  lands, t3 refuses with `unknown_unlock` (correct fail-closed behaviour).
- @core: fh_core removeItem (B7) for cargo removal; spawn kind `wagon` (R0, landed in core B7).

## Out of lane
Fast-travel system itself, NUI screens (@ui), horse ownership/stables, hired hands, supplies shortage pricing,
new regions, ungated chase/ambush and off-road wheel break natives until @spikes S2/S3 RESULT lines, any push.
