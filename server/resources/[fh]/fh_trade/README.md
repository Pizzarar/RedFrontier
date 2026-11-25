# fh_trade

Regional trade prices, shortages, trade-post selling and supplies buying (spec L6; buying: idea-716/719). R3 of `roads-01`. Depends on fh_core, fh_cargo, fh_economy, oxmysql, ox_lib.

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
- Emits (server): `fh:trade:sold` `{ src, region, post, item, amount, total }` after a paid sale; `fh:trade:bought` (same shape) after a paid and granted buy; `fh:trade:owed` `{ src, citizenid, region, item, amount, owed }` when the payout `credit` failed after the goods were removed (fix by hand). Emits (to the client): `fh:trade:menu` (now also `supplies = { { item, label, price } }`, `maxBuy`), `fh:trade:sold`, `fh:trade:bought`.
- Consumes (from clients, server re-validates everything): `fh:trade:menu`; the fh_ui `tradepost` screen actions relayed as `fh:trade:ui_sell` / `fh:trade:ui_buy` (payload `{item, amount}`; src comes from the relay, not the payload).

## Selling
Server checks the player stands within a post's `radius`, validates item/amount, `fh_core.removeItem({type='backpack', id=src}, item, amount)` (all-or-nothing), commits the sale to the price state, then pays `fh_economy:credit(citizenid, total, 'trade_sell:<item>', region)`. The citizenid is captured **before** the goods are removed (no loaded character -> `no_player`, nothing taken), so a drop or character switch mid-sale still pays the character that owned the goods (online pay or queued for next load). If `credit` throws or refuses after removal: console `ALERT credit failed ... owed $N`, event `fh:trade:owed` `{ src, citizenid, region, item, amount, owed }`, player sees `pay_failed` (fix by hand).
Goods are registered by this resource with `fh_core.registerItems` at start (and when fh_core restarts).

## Buying supplies (`shared/supplies.lua`, pure, `spec/trade_supplies_spec.lua`)
Every post sells `FhTradeConfig.supplies` (item -> flat whole-dollar price per unit, unlimited stock, max `maxBuyPerTx` per request). Buying never reads or writes the price model (no shortage, saturation or wobble). Today: lumber $3, nails $2, lead $2, casings $2, resource_gunpowder $3, herb_american_ginseng / herb_oregano / herb_red_sage / herb_wild_mint $3 (just above each item's `value_base`).

Sequence (all-or-nothing, one trade per player at a time; the busy lock is shared with selling and released on every path, pcall-guarded):
1. Server checks the post radius (as selling), the item is in `supplies`, amount is a whole number 1..`maxBuyPerTx`.
2. citizenid of `src` read with no yield before the charge (= the character `charge` charges).
3. `fh_economy:charge(src, total, 'trade_buy:<item>', post.region)`. Not `true` -> refused, no item, no refund; the code is passed through (`fh_insufficient_funds`, `fh_charge_busy`, `no_player`, `player_changed`, ...). A throw -> `charge_error` (ALERT log, no item).
4. `fh_core:addItem({ type = 'backpack', id = src }, item, amount)`: all-or-nothing (fh_core README, addItem row: nothing is added on a refusal), so a refusal (`fh_too_heavy`, `fh_no_slot`, `fh_player_offline`, ...) or a throw means nothing was granted.
5. Grant failed -> `fh_economy:credit(citizenid, total, 'trade_buy_refund:<item>', post.region)` (online pay or queued for next load). OK -> `grant_failed_refunded`; refund refused/threw -> `refund_failed` and console `ALERT refund FAILED for <cid> ... owed $N` (fix by hand).

## Commands
- Player: `/tradepost` (opens the fh_ui `tradepost` screen; sell goods and buy supplies), `/tradequote` (also lists supplies), `/tradesell <item> <amount>`, `/tradebuy <item> <amount>` (chat fallback).
- Server console: `fh_trade_shortage <region> <item> <level 0..1>`; `tradequote` dumps the price rows as JSON.

## DB
`server/migrations/0013_fh_trade.sql`: `fh_trade_prices (region_id, item, shortage, saturation, updated_at)`, PK (region_id, item). Dirty rows flush every `saveMs` and on resource stop; load decays to "now". After the load, `initialShortages` (config) are seeded only for a region/item with no row at all (`P.seedShortages`), then saved; a row whose shortage was cleared to 0 is never re-seeded. If the load fails, nothing is seeded.

## Tests
`~/.venvs/rf/bin/python tools/run-specs.py spec/trade_prices_spec.lua spec/trade_supplies_spec.lua spec/freight_spec.lua spec/freight_server_spec.lua spec/trade_sell_spec.lua`

## TODO(B7 @core)
`fh_core:removeItem` and `fh_core:registerItems` ship with @core B7. Until then the resource logs "not available yet", goods are not registered, and every sale is refused (`Trading is not available yet.`). If `credit` fails after the items were removed there is no player refund export: it logs `ALERT ... owed $N` and emits `fh:trade:owed`.

## In-game checklist (needs Cfx key + B7)
- [ ] Next to the post: `/tradequote` lists three goods with prices; away from it: "not at a trade post".
- [ ] Give goods (`fh_give <id> trade_salt 10`), `/tradesell trade_salt 10`: items gone, cash up, one `fh_ledger` pay row.
- [ ] Sell 10 again: pays less; wait/restart: price recovers; `/tradesell trade_salt 999` and 0: refused, nothing taken.
- [ ] `fh_trade_shortage heartlands trade_salt 0.8` raises the quote; restart server: shortage survives (decayed).
- [ ] `/tradebuy lumber 5` with >= $15: cash -$15, 5 lumber in the backpack, one `fh_ledger` charge row `trade_buy:lumber`. With too little cash: refused, nothing changes. With a full/too-heavy backpack: charge row, then a `credit` row `trade_buy_refund:lumber` for the same amount, no lumber.

## Freight contracts (R4)
A **job type for fh_quests** (no board of its own); contract per `README registerJobType` on `quests-q5` `0adc9aa`. `shared/freight.lua` (pure, `spec/freight_spec.lua`) + `server/freight.lua` (wiring, `spec/freight_server_spec.lua` with stubbed fh_core/fh_cargo/fh_quests/fh_progression).
fh_quests is a **soft dependency**: not in `dependencies`; `registerJobType('freight', ...)` runs on `onResourceStart` of `fh_quests` or of fh_trade, only when `GetResourceState('fh_quests') == 'started'`. While unregistered, fh_quests pauses freight jobs (no progress, no fail).

- `offers(region_id)`: one offer per shortage in the OTHER post regions whose resolved destination has valid coordinates and whose horizontal route distance is at least that tier's `minDistance` (`freight.minDistance` for T1, `freight.t2.minDistance` for T2, `freight.t3.minDistance` for T3). Destinations resolve from `FhTradeConfig.posts` + `FhRegions.posts` (`F.resolveDestinations`, roads-03 R12, default delivery radius `freight.destinationRadius` = 40 m) rather than a hardcoded `destinations` table: only regions with >= 1 trade post get offers, `freight.overrides` allows per-region `{ x?, y?, z?, radius?, post? }` tweaks, `freight.exclude` opts regions out, and regions with missing coords are skipped (no throw). Board caps (`freight.maxOffers` = 3 for T1, `freight.t2.maxOffers` = 2 for T2, `freight.t3.maxOffers` = 2 for T3) keep boards bounded as regions scale. Offer: `key` = `<from>.<to>.<item>` (stable, quest id `job:freight:<key>`), `title`, `text`, `cooldown_min`, `rewards = { money, rep = { region_id = to, delta } }` (money + rep only; no items until core idea-643). No `on`: `onEvent` decides. Everything else (`tier`, `region_id` (= origin `from_region`, the board's region), `from_region`, `to_region`, `item`, `qty`, `reward`, `deadline_s`, and T2/T3's `locked`, `min_region_tier`, `min_wagon_tier`) is NOT stored by fh_quests, it only reaches `accept`. Every offer has `tier` (1, 2, or 3 below); an offer without one is T1.
- `cooldown_min` is set explicitly from `freight.cooldownMin` (default **30** = the deadline: the same route/cargo cannot be re-taken while a previous run could still be live; `0` is allowed).
- `accept(src, offer)`: re-validates the offer, one accept at a time per player (cap `maxActivePerPlayer` is exact), T2/T3: the kill switch and the regional tier gate (below), finds your own wagon within `acceptReach` (`fh_cargo:nearestWagon`), the wagon-tier fit (below), `canFit`, `fh_core:addItem(wagonRef, item, qty, { freight = key })`, records the contract. Route/cargo/deadline live in **fh_trade's own table** `fh_trade_contracts` keyed `(citizenid, key)` (migration `0014_fh_trade_contracts.sql`): `wagon, from_region, to_region, item, qty, reward, accepted_at, deadline` is the complete set the checks need.
- Check loop (`checkMs`): deadline -> `fh:trade:contract_failed` (`reason = 'timeout'`, checked even when the player is offline). Otherwise, only while the player is online and their wagon has been **seen spawned** since the restart/login: wagon gone / not owner / cargo below qty for `graceChecks` consecutive checks -> failed (`wagon_lost` / `cargo_missing`). After a restart or while offline, losses are never counted (the wagon is not respawned yet). Own wagon inside the destination radius (`vector3` or table coords) holding >= qty -> `fh_core:removeItem(wagonRef, item, qty)` (B7, all-or-nothing, pcall'd); only on `true` does `fh:trade:contract_delivered` fire. `false` (`fh_not_enough`) or an error: nothing removed, no event, retried next check. Unreadable cargo fails closed.
- `onEvent(name, payload, state)`: delivered -> `'complete'`, failed -> `'fail'` when `state.quest_id == job:freight:<payload.key>`; otherwise nil.
- `abandon(src, state)` (key = `state.progress.job.key`): called on player abandon AND when fh_quests could not save the accept. Fully undoes accept: contract dropped (row deleted), cargo taken out of the wagon with `removeItem`, idempotent, safe against an in-flight delivery check (it never emits). It never calls back into fh_quests (hooks run inside its per-character lock).
- **Payout is not done here.** The fh_quests engine pays the offer's `rewards` once on `'complete'` (ledger reason `quest:job:freight:<key>`).
- Events (one table): `fh:trade:contract_delivered` / `fh:trade:contract_failed` = `{ src?, citizenid, key, quest_id, from_region, to_region, item, qty, reward, reason? }`.
- **T2 & T3 contracts (roads-02 R9, roads-03 R13/R14)**, `freight.t2` and `freight.t3` in `config.lua` (absent = that tier is not offered):
  - Same `freight` job type; keys `<from>.<to>.<item>.t2` / `<from>.<to>.<item>.t3`, titles `[T2] Freight: ...` / `[T3] Freight: ...`, `tier = 2` / `tier = 3`. One per shortage of any trade good with a known weight, only on routes of at least that tier's `minDistance` m between the two regions' resolved destinations:
    - **T2**: `t2.minDistance` = 1500 m (e.g. heartlands <-> scarlett_meadows ~2405 m, bayou_nwa <-> great_plains ~3566 m). Qty `clamp(ceil(level * t2.qtyPerLevel), t2.minQty, min(t2.maxQty, floor(t2.maxLoad / weight)))`: capped by the t2 wagon's SLOTS (`t2.maxQty` = 30) and load in grams (`t2.maxLoad` = 300000, so whiskey at 15 kg caps at 20; salt/cloth 10-30, whiskey 10-20). Pay is `floor(floor(t1Qty x quote x premium) x t2.payMultiple)` with `payMultiple` 3 and hard cap `payCapMultiple` 4 (~3x T1, never > 4x). Rep `t2.repDelta` (4; T1 2). `deadline_s = deadlineBase + route m x deadlinePerMeter` (900 s + 1 s/m, ~55 min); `cooldown_min = max(t2.cooldownMin, deadline in minutes)`. Own board cap `t2.maxOffers` (2), listed after T1.
    - **T3 (R14)**: `t3.minDistance` = 3000 m (strictly > T2; e.g. heartlands <-> bayou_nwa ~3538 m, bayou_nwa <-> great_plains ~3566 m). Qty `minQty` 20, `maxQty` 60, `qtyPerLevel` 60, `maxLoad` 500000 (matches the t3 Freight wagon's 60 slots / 500 kg; salt/cloth 20-60, whiskey 20-33). Pay is `payMultiple` 6 (= 2x matching T2 pay, ~6x T1) with hard cap `payCapMultiple` 7 (<= 7x T1). Rep `t3.repDelta` (6). `deadline_s = 1200 + route m x 1.0` (~79 min for 3566 m); `cooldown_min = max(t3.cooldownMin, deadline in minutes)`. Own board cap `t3.maxOffers` (2), listed after T2.
    - `validateOffer` re-derives the T2/T3 qty, route length and deadline, requires `level` finite in (0, 1], and bounds `reward` by `payCapMultiple x t1Qty x base x rewardCapMultiple` (`bad_level`, `bad_qty`, `bad_route`, `bad_deadline`, `bad_reward`).
  - `locked = true` on **every** T2 and T3 offer: fh_quests calls `offers(region_id)` with no player (one shared board per rotation), so a per-player lock cannot be computed there and the board does not show `locked` anyway (not an offer field it reads). The title/text say what is needed; the real check is at accept.
  - **Kill switches (roads-03 R13/R14):** `freight.t2.enabled` and `freight.t3.enabled` (lane-local, default `true`). Off (`false` or any value other than `true`/absent, fail closed): that tier's offers are hidden and `accept` refuses a stale offer that was listed earlier with `fh_freight_tier_disabled` (in `validateOffer`, before the accept lock and before any fh_progression call). T1 cannot be switched off. `F.tierEnabled(cfg, tier)`.
  - **Regional tier gate (accept, roads-03 R13/R14):** `F.TIER_GATES` / `F.gateFor(cfg, tier)` give each gated tier `{ minRegionTier }` (T2: 2, T3: 3; T1 has no row, is never gated and calls no fh_progression export). Accept needs `exports.fh_progression:getTier(src, origin_region) >= minRegionTier`, origin = the offer's `from_region`: rep in a region opens that region's board (bayou_nwa tier 3 accepts bayou-origin T3 even while heartlands is tier 1). No global `canUnlock` is called (`contracts_t2` / `contracts_t3` are not used by freight). `F.checkRegionTier`.
    Soft dependency, **fail closed**: fh_progression not `started`, `getTier` missing or throwing, or not a finite number -> `fh_locked` (the reason is logged). `getTier` can yield, so the citizenid is re-checked after it: changed -> `fh_no_player`. The accept lock is released on every refusal.
    `validateOffer` binds the origin: `region_id` must equal `from_region` (gated tiers must carry it, T1 may omit it) and `from_region` is bound to the key, so a forged `region_id` (`fh_freight_bad_region`) or moved origin (`fh_freight_bad_key`) cannot dodge the gate.
  - **Wagon-tier fit (accept):** the wagon's tier comes from `exports.fh_cargo:getWagon(id).tier` and `FhCargoRules.TIERS` (fh_cargo `shared/cargo_rules.lua`, a read-only server script here; fh_cargo is now a hard dependency). T2 needs tier >= `t2.minWagonTier` (2) and T3 needs tier >= `t3.minWagonTier` (3, t3 Freight wagon; t1/t2 refused), and an EMPTY wagon of that tier must hold the load (slots: one per stack, or one per unit for non-stackables; `qty x weight <= maxWeight`) -> else `fh_freight_wagon_too_small`; tier unreadable -> `fh_freight_wagon_unknown` (T2/T3 fail closed; T1 skips the tier check). `canFit` then checks the real current load.
  - Pay, delivery, loss, abandon: unchanged (fh_quests engine pays the offer's `rewards` once on `'complete'`).
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
- [ ] T2: `fh_trade_shortage scarlett_meadows trade_salt 0.5`; the heartlands board also lists `[T2] Freight: 15x Salt Sack to scarlett_meadows`. Heartlands rep tier 1: accept -> `fh_locked` (R13: the gate reads rep in the offer's origin region, heartlands here). `freight.t2.enabled = false` + restart: no `[T2]` offers; back to `true`: listed again. Rep tier 2 (rep >= 100), `/fh_wagon t1` beside you: `fh_freight_wagon_too_small`; `/fh_wagon t2`: accepted, 15 salt in the wagon. `stop fh_progression`: T2 accept -> `fh_locked`, T1 still accepted.
- [ ] T3: `fh_trade_shortage bayou_nwa trade_salt 0.5`; the heartlands board lists `[T3] Freight: 30x Salt Sack to bayou_nwa` (~3538 m >= 3000 m; scarlett_meadows ~2405 m has no T3). Heartlands rep tier 2: accept -> `fh_locked`; rep tier 3 + `/fh_wagon t2`: `fh_freight_wagon_too_small`; rep tier 3 + `/fh_wagon t3`: accepted, 30 salt in the wagon. `freight.t3.enabled = false` + restart: no `[T3]` offers and stale T3 accept -> `fh_freight_tier_disabled`.

## nearestPost(src) (roads-04 R17)

`exports.fh_trade:nearestPost(src) -> { id, label, region, x, y, z, radius } | nil`: the trade post the player's ped is inside (same radius and disabled-region gate as selling). Used by fh_cargo's wagon post menu. Never throws.
