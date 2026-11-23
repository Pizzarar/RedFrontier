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
`python tools/run-specs.py spec/trade_prices_spec.lua`

## TODO(B7 @core)
`fh_core:removeItem` and `fh_core:registerItems` ship with @core B7. Until then the resource logs "not available yet", goods are not registered, and every sale is refused (`Trading is not available yet.`). If `pay` fails after the items were removed there is no player refund export: it logs `ALERT ... owed $N`.

## In-game checklist (needs Cfx key + B7)
- [ ] Next to the post: `/tradequote` lists three goods with prices; away from it: "not at a trade post".
- [ ] Give goods (`fh_give <id> trade_salt 10`), `/tradesell trade_salt 10`: items gone, cash up, one `fh_ledger` pay row.
- [ ] Sell 10 again: pays less; wait/restart: price recovers; `/tradesell trade_salt 999` and 0: refused, nothing taken.
- [ ] `fh_trade_shortage heartlands trade_salt 0.8` raises the quote; restart server: shortage survives (decayed).
