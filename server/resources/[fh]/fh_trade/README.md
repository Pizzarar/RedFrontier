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
`server/migrations/0005_fh_trade.sql`: `fh_trade_prices (region_id, item, shortage, saturation, updated_at)`, PK (region_id, item). Dirty rows flush every `saveMs` and on resource stop; load decays to "now".

## Tests
`python tools/run-specs.py spec/trade_prices_spec.lua spec/freight_spec.lua` (SPECS NOT RUN yet for freight: python3-lupa / lua / luac missing on the build host)

## TODO(B7 @core)
`fh_core:removeItem` and `fh_core:registerItems` ship with @core B7. Until then the resource logs "not available yet", goods are not registered, and every sale is refused (`Trading is not available yet.`). If `pay` fails after the items were removed there is no player refund export: it logs `ALERT ... owed $N`.

## In-game checklist (needs Cfx key + B7)
- [ ] Next to the post: `/tradequote` lists three goods with prices; away from it: "not at a trade post".
- [ ] Give goods (`fh_give <id> trade_salt 10`), `/tradesell trade_salt 10`: items gone, cash up, one `fh_ledger` pay row.
- [ ] Sell 10 again: pays less; wait/restart: price recovers; `/tradesell trade_salt 999` and 0: refused, nothing taken.
- [ ] `fh_trade_shortage heartlands trade_salt 0.8` raises the quote; restart server: shortage survives (decayed).

## Freight contracts (R4)
A **job type for fh_quests** (no board of its own). `shared/freight.lua` (pure, `spec/freight_spec.lua`) + `server/freight.lua` (wiring).
fh_quests is a **soft dependency**: it is not in `dependencies`; `registerJobType('freight', ...)` runs on `onResourceStart` of `fh_quests` or of fh_trade, only when `GetResourceState('fh_quests') == 'started'`.

- `offers(region_id)`: one offer per shortage found in the OTHER regions that have `freight.destinations` (`FhFreight.generate`). Offer: `key` = `<from>.<to>.<item>` (stable), `title`, `text`, `from_region`, `to_region`, `item`, `qty` (ceil(level x `qtyPerLevel`)), `reward` (qty x quote x `premium`), `rewards = { money, rep = { region_id = to, delta } }`, `deadline_s`. With a single region (today) there are no offers unless `freight.allowSameRegion = true`.
- `accept(src, offer)`: re-validates the offer, finds your own wagon within `acceptReach` (`fh_cargo:nearestWagon`), `canFit`, then `fh_core:addItem(wagonRef, item, qty, { freight = key })` and records the contract (memory + `fh_trade_contracts`, migration `0006`, provisional number).
- Check loop (`checkMs`): deadline -> `fh:trade:contract_failed` (`reason = 'timeout'`); wagon gone / not owner / cargo below qty for `graceChecks` consecutive checks -> failed (`wagon_lost` / `cargo_missing`); own wagon within the destination radius with >= qty of the item -> cargo is moved out of the wagon (into a throwaway drop bag, deleted) and `fh:trade:contract_delivered` fires. Unreadable cargo fails closed (neither).
- `onEvent(name, payload, state)`: delivered -> `'complete'`, failed -> `'fail'` for the matching `job:freight:<key>` only; otherwise nil. `abandon(src, state)`: drops the contract (no failed event) and takes the cargo back out of the wagon, best effort.
- **Payout is not done here.** The fh_quests engine pays the offer's `rewards` once on `'complete'` (`fh_economy:pay` reason `quest:job:freight:<key>`).
- Events (one table): `fh:trade:contract_delivered` / `fh:trade:contract_failed` = `{ src?, citizenid, key, quest_id, from_region, to_region, item, qty, reward, reason? }`.
- Export `getContracts(src)` -> active contracts (`key, from_region, to_region, item, qty, reward, deadline`).

### Freight test checklist (in game; needs R1 wagon, R0 spawn, fh_quests Q2/Q3, a 2nd region or `allowSameRegion = true`)
- [ ] `ensure fh_quests` then fh_trade: log `registered job type freight with fh_quests`. Restart fh_quests: log again. Start fh_trade without fh_quests: no error, no registration.
- [ ] `fh_trade_shortage <region> trade_salt 0.8`; the board at the other region lists `Freight: Nx Salt Sack to <region>`.
- [ ] `/fh_wagon t2`, stand next to it, accept: N salt appear in the wagon stash; accept again: refused; 3rd contract refused (`maxActivePerPlayer`).
- [ ] Accept with no wagon near: refused `fh_freight_no_wagon`. Too heavy for the wagon: refused, nothing added.
- [ ] Drive the wagon into the destination radius: cargo leaves the wagon, journal completes, ONE `fh_ledger` row `quest:job:freight:<key>`, rep up.
- [ ] Unload the cargo to a chest and wait `graceChecks x checkMs`: contract fails (`cargo_missing`), quest failed, no payout.
- [ ] Let `deadlineSeconds` pass (set it to 60): fails with `timeout`. Replace the wagon (`/fh_wagon t2` again): no spurious failure (same stash id).
- [ ] Abandon from the journal: cargo removed from the wagon, no failed event, no payout. Restart fh_trade mid-contract: it resumes (row in `fh_trade_contracts`).
