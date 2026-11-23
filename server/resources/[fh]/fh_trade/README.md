# fh_trade

Regional trade prices, shortages and trade-post selling (spec L6). R3 of `roads-01`. Depends on fh_core, fh_economy, oxmysql, ox_lib.

## Price model (`shared/trade_prices.lua`, pure, specced)
`unit = base x regionFactor x (1 + gain*shortage) x (1 + wobble) x (1 - maxDrop*saturation)`

- **shortage** 0..1: set by `setShortage`, decays toward 0 (half-life), eased by selling into it.
- **wobble**: seeded value-noise in +-8% of baseline; a pure function of `seed/region/item/clock` (deterministic, `FhTradeConfig.seed`).
- **saturation** 0..1: every unit sold into a region depresses its price; recovers over time (half-life).
- All functions take `now` (unix seconds) and the config; nothing reads a clock. Tuning and goods live in `config.lua`.

## Exports (server)
- `exports.fh_trade:quote(region, item)` -> `price, detail` (`detail` = `{ base, shortage, saturation, wobble }`) or `nil, 'unknown_region'|'unknown_item'|'invalid_time'`
- `exports.fh_trade:getShortages(region)` -> `{ { item, level, multiplier, price }, ... }` worst first (level >= `shortage.threshold`). R4 freight contracts generate from this.
- `exports.fh_trade:setShortage(region, item, level)` -> `ok, err` (level clamped 0..1)
- `exports.fh_trade:previewSell(region, item, amount)` -> whole-dollar total or `nil, err`
- `exports.fh_trade:listGoods()` -> `{ [item] = { label, base } }`

## Events
- Emits (server): `fh:trade:sold` `{ src, region, post, item, amount, total }` after a paid sale. Emits (to the client): `fh:trade:menu`, `fh:trade:sold`.
- Consumes (from clients, server re-validates everything): `fh:trade:menu`, `fh:trade:sell(item, amount)`.

## Selling
Server checks the player stands within a post's `radius`, validates item/amount, `fh_core.removeItem({type='backpack', id=src}, item, amount)` (all-or-nothing), commits the sale to the price state, then `fh_economy:pay(src, total, 'trade_sell:<item>', region)`. Money only comes from `pay`.
Goods are registered by this resource with `fh_core.registerItems` at start (and when fh_core restarts).

## Commands
- Player: `/tradepost` (ox_lib menu + amount dialog), `/tradequote`, `/tradesell <item> <amount>` (chat fallback).
- Server console: `fh_trade_shortage <region> <item> <level 0..1>`; `tradequote` dumps the price rows as JSON.

## DB
`server/migrations/0013_fh_trade.sql`: `fh_trade_prices (region_id, item, shortage, saturation, updated_at)`, PK (region_id, item). Dirty rows flush every `saveMs` and on resource stop; load decays to "now".

## Tests
`python tools/run-specs.py spec/trade_prices_spec.lua spec/freight_spec.lua spec/freight_server_spec.lua` (SPECS NOT RUN yet for freight: python3-lupa / lua / luac missing on the build host)

## TODO(B7 @core)
`fh_core:removeItem` and `fh_core:registerItems` ship with @core B7. Until then the resource logs "not available yet", goods are not registered, and every sale is refused (`Trading is not available yet.`). If `pay` fails after the items were removed there is no player refund export: it logs `ALERT ... owed $N`.

## In-game checklist (needs Cfx key + B7)
- [ ] Next to the post: `/tradequote` lists three goods with prices; away from it: "not at a trade post".
- [ ] Give goods (`fh_give <id> trade_salt 10`), `/tradesell trade_salt 10`: items gone, cash up, one `fh_ledger` pay row.
- [ ] Sell 10 again: pays less; wait/restart: price recovers; `/tradesell trade_salt 999` and 0: refused, nothing taken.
- [ ] `fh_trade_shortage heartlands trade_salt 0.8` raises the quote; restart server: shortage survives (decayed).

## Freight contracts (R4)
A **job type for fh_quests** (no board of its own); contract per `README registerJobType` on `quests-q5` `0adc9aa`. `shared/freight.lua` (pure, `spec/freight_spec.lua`) + `server/freight.lua` (wiring, `spec/freight_server_spec.lua` with stubbed fh_core/fh_cargo/fh_quests).
fh_quests is a **soft dependency**: not in `dependencies`; `registerJobType('freight', ...)` runs on `onResourceStart` of `fh_quests` or of fh_trade, only when `GetResourceState('fh_quests') == 'started'`. While unregistered, fh_quests pauses freight jobs (no progress, no fail).

- `offers(region_id)`: one offer per shortage in the OTHER regions with a `freight.destinations` entry. Offer: `key` = `<from>.<to>.<item>` (stable, quest id `job:freight:<key>`), `title`, `text`, `cooldown_min`, `rewards = { money, rep = { region_id = to, delta } }` (money + rep only; no items until core idea-643). No `on`: `onEvent` decides. Everything else (`from_region`, `to_region`, `item`, `qty`, `reward`, `deadline_s`) is NOT stored by fh_quests, it only reaches `accept`.
- `cooldown_min` is set explicitly from `freight.cooldownMin` (default **30** = the deadline: the same route/cargo cannot be re-taken while a previous run could still be live; `0` is allowed).
- `accept(src, offer)`: re-validates the offer, one accept at a time per player (cap `maxActivePerPlayer` is exact), finds your own wagon within `acceptReach` (`fh_cargo:nearestWagon`), `canFit`, `fh_core:addItem(wagonRef, item, qty, { freight = key })`, records the contract. Route/cargo/deadline live in **fh_trade's own table** `fh_trade_contracts` keyed `(citizenid, key)` (migration `0014_fh_trade_contracts.sql`): `wagon, from_region, to_region, item, qty, reward, accepted_at, deadline` is the complete set the checks need.
- Check loop (`checkMs`): deadline -> `fh:trade:contract_failed` (`reason = 'timeout'`, checked even when the player is offline). Otherwise, only while the player is online and their wagon has been **seen spawned** since the restart/login: wagon gone / not owner / cargo below qty for `graceChecks` consecutive checks -> failed (`wagon_lost` / `cargo_missing`). After a restart or while offline, losses are never counted (the wagon is not respawned yet). Own wagon inside the destination radius (`vector3` or table coords) holding >= qty -> `fh_core:removeItem(wagonRef, item, qty)` (B7, all-or-nothing, pcall'd); only on `true` does `fh:trade:contract_delivered` fire. `false` (`fh_not_enough`) or an error: nothing removed, no event, retried next check. Unreadable cargo fails closed.
- `onEvent(name, payload, state)`: delivered -> `'complete'`, failed -> `'fail'` when `state.quest_id == job:freight:<payload.key>`; otherwise nil.
- `abandon(src, state)` (key = `state.progress.job.key`): called on player abandon AND when fh_quests could not save the accept. Fully undoes accept: contract dropped (row deleted), cargo taken out of the wagon with `removeItem`, idempotent, safe against an in-flight delivery check (it never emits). It never calls back into fh_quests (hooks run inside its per-character lock).
- **Payout is not done here.** The fh_quests engine pays the offer's `rewards` once on `'complete'` (ledger reason `quest:job:freight:<key>`).
- Events (one table): `fh:trade:contract_delivered` / `fh:trade:contract_failed` = `{ src?, citizenid, key, quest_id, from_region, to_region, item, qty, reward, reason? }`.
- Export `getContracts(src)` -> active contracts. Needs fh_core **B7** (`removeItem`): R4 merges after B7.

### Freight test checklist (in game; needs R1 wagon, R0 spawn, fh_quests, core B7, a 2nd region or `allowSameRegion = true`)
- [ ] `ensure fh_quests` then fh_trade: log `registered job type freight with fh_quests`. Restart fh_quests: log again. Start fh_trade without fh_quests: no error, no registration.
- [ ] `fh_trade_shortage <region> trade_salt 0.8`; the board at the other region lists `Freight: Nx Salt Sack to <region>`.
- [ ] `/fh_wagon t2`, stand next to it, accept: N salt appear in the wagon stash; accept the same again: refused; over `maxActivePerPlayer`: refused.
- [ ] Accept with no wagon near: refused `fh_freight_no_wagon`. Too heavy for the wagon: refused, nothing added.
- [ ] Drive the wagon into the destination radius: the cargo leaves the wagon, journal completes, ONE `fh_ledger` row `quest:job:freight:<key>`, rep up. Cargo already unloaded: no delivery, no payout.
- [ ] Unload the cargo to a chest and wait `graceChecks x checkMs`: contract fails (`cargo_missing`), quest failed, no payout.
- [ ] Let the deadline pass (set `deadlineSeconds` to 60): fails with `timeout`, also if you log out first. Replace the wagon (`/fh_wagon t2` again): no spurious failure (same stash id).
- [ ] Restart the server mid-contract and log in: no failure while the wagon is not spawned; contract resumes once it is.
- [ ] Abandon from the journal: cargo removed from the wagon, no failed event, no payout; abandoning again changes nothing.
