# fh_cargo

Lane L6 (spec §5, M4), blocks R1 and R2 (wheel break + repair): wagon tiers, cargo loading, fast-travel veto. Uses `fh_core` exports only.

- `shared/cargo_rules.lua`: pure rules (no natives), specced in `spec/cargo_rules_spec.lua`. Tier table, ownership,
  reach, capacity, cargo-only check, fast-travel verdict.
- `server/main.lua`: thin wiring (gathers positions and container views, calls the rules, then ONE `fh_core:move`).
- `config.lua`: wagon models per tier (**unverified in game**), reach, spawn offset.

## Config keys (`config.lua`, `FhCargoConfig`)

| Key | Default | Meaning |
|---|---|---|
| `Models` | `t1 cart01`, `t2 wagon02x`, `t3 supplywagon` | Model per tier (unverified in game) |
| `Reach` | `5.0` m | Player to own wagon for load/unload |
| `FastTravelReach` | `30.0` m | A wagon with cargo this close blocks fast travel |
| `SpawnAheadMetres` | `4.0` | `/fh_wagon` spawn offset in front of the admin |
| `Prices` | `t1 150`, `t2 600`, `t3 1800` | Buy price per tier (whole dollars, R16). t1 < t2 < t3, under fh_economy `maxCharge` (specced) |
| `BuyChargeRetries` | `1` | `fh_charge_busy` from fh_economy is retried this many times, then refused |
| `BuyRetryMs` | `250` | Wait before that retry |

Tier numbers are not config: they live in `shared/cargo_rules.lua` (`TIERS`).

## Rep-unlock gate (R8, roads-02)

t2/t3 wagons are gated on regional rep via `fh_progression`: `spawnWagon` calls `exports.fh_progression:canUnlock(src,
'wagon_t2')` / `'wagon_t3'` (the id lives in `shared/cargo_rules.lua` `UNLOCKS`). t1 is always allowed. Fail closed:
if fh_progression is not started, `canUnlock` throws, or it returns `false`, the spawn is refused and the reason is
surfaced to the player (`fh_locked` when no reason is available, otherwise the returned reason, e.g. `tier_too_low`).
Soft dependency only: there is no `dependencies` entry for fh_progression.

## Tiers

| Tier | Slots | Max weight (g) | Speed cap (m/s, empty) |
|---|---|---|---|
| `t1` cart | 15 | 120 000 | 8.0 |
| `t2` wagon | 30 | 300 000 | 7.0 |
| `t3` freight | 60 | 500 000 | 6.0 |

A full wagon is slowed by 40% (`speedLimit(tier, weight)`). The cap applies to a broken wagon (R2, `client/main.lua`); an unbroken one is not capped yet.
Each wagon is an fh_core `wagon` container, stash `fh:wagon:<citizenid>:<tier>` (one per character per tier, so
respawning a wagon keeps its cargo). Tier caps are passed to `registerContainer`; they sit inside fh_core's wagon default.

## Commands

| Command | Who | What |
|---|---|---|
| `/fh_wagon <tier>` | `group.admin` | Dev: request a wagon (`t1`/`t2`/`t3`, or `cart`/`wagon`/`freight`) 4 m in front of you |
| `/fh_cargo load\|unload <slot> [amount]` | player | Move cargo between your OWN wagon and the container you have open (chest). Server checks owner, reach to wagon and container, cargo class, weight, slots |

Only `cargo` items move (spec §4.1). Cargo cannot live in a backpack, so loading starts from an open chest.

## Exports

| Export | Returns |
|---|---|
| `canFastTravel(src)` | `ok, reason`. Blocked (`fh_cargo_carried`) while carrying cargo, or (`fh_cargo_wagon_near`) while your own wagon holding cargo is within `FastTravelReach` (30 m). Emits `fh:cargo:fasttravel_blocked`. No fast-travel system exists: whoever adds one must call this |
| `spawnWagon(src, tier, coords)` | `wagonId` or `nil, reason`. t2/t3 are gated on fh_progression `canUnlock` (see "Rep-unlock gate"); t1 always allowed |
| `nearestWagon(src, coords, range)` | Container ref `{ type = 'wagon', id = 'fh:wagon:...' }` (what `fh_core` `move` accepts) of the nearest LIVE wagon within `range` m of `coords` (nil = the player's ped) that `src` may load into (v1: owner only), else `nil`. `range` must be > 0 and is capped at 25 m. Bad args return `nil`, never throw. Used by fh_hunting |
| `getWagon(wagonId)` | `{ id, owner, tier, netId, coords }` or `nil` |
| `buyWagon(src, tier, region_id)` | `ok, err[, detail]`. Buy a wagon tier for `src`'s character, charged at `region_id` (the trade post's region). See "Owned wagons" |
| `ownsWagon(who, tier)` | `true`/`false`, or `nil, err` (`fh_bad_tier`, `fh_no_character`, `fh_bad_citizenid`, `fh_db_error`). `who` = server id or citizenid. Reads `fh_wagons` (yields) |
| `ownedTiers(who)` | Owned tier keys in tier order (`{ 't1', 't3' }`), or `nil, err` (as `ownsWagon`). Reads `fh_wagons` (yields) |

## Events (server-local, one table)

| Event | Payload |
|---|---|
| `fh:cargo:fasttravel_blocked` | `{ src, citizenid, reason, wagon }` |
| `fh:cargo:loaded` / `fh:cargo:unloaded` | `{ src, citizenid, wagon, item, count, container }` |
| `fh:cargo:wagon_spawned` | `{ src, citizenid, wagon, tier, netId }` |
| `fh:cargo:wagon_bought` | `{ src, citizenid, tier, price, region }` |
| `fh:cargo:wagon_buy_owed` | `{ src, citizenid, tier, owed, region, reason, err }`: charged, the row could not be written AND the credit refund failed. Also an `ALERT` console line: credit `owed` to `citizenid` by hand |

## In-game check list (spec §9)

1. As admin: `/fh_wagon t2`. A wagon appears 4 m ahead; chat confirms.
   Since R8, t2 needs heartlands tier 2 rep (`fh_rep_region <id> heartlands 100` first); a lower tier refuses `tier_too_low`.
2. Open a homestead chest holding a cargo item (`/fh_give <id> test_cargo_crate`, drop it in the chest). Stand by the wagon, `/fh_cargo load 1`: the crate moves to the wagon.
3. Walk 20 m away, `/fh_cargo load 1` again: refused `fh_out_of_reach`. A second character cannot load into your wagon (`fh_not_owner`).
4. Try a non-cargo item (`bread`): refused `fh_not_cargo`. Fill a `t1` past 120 kg: refused `fh_too_heavy`.
5. Fast-travel check from the server console or another resource: `exports.fh_cargo:canFastTravel(src)` returns `false, fh_cargo_wagon_near` while loaded wagon is within 30 m, `true` once unloaded or far away; `fh:cargo:fasttravel_blocked` fires on each block.
6. Stop `fh_inventory`, call `canFastTravel` again: `false, fh_cargo_unknown` (fails closed).
7. `/fh_wagon t2` twice: the old wagon is replaced and its cargo is still there.

## Known gaps / TODO

- Wagon state is in memory (stash contents persist in fh_inventory by id; the wagon entity does not survive a restart).
- Not runtime-tested (no Cfx key yet); natives side unverified.
- Contracts and delivery are R4.
- **TODO(B7 @core):** `removeItem(ref, item, amt)` is not exported by fh_core yet: `/fh_repair` finishes with `fh_core_no_removeitem` until it lands. `registerItems` is used as-is and failure only prints a warning.
- **TODO(R2 off-road):** no verified road/off-road native, so the client never sends the `fh:cargo:offroad_hint`; every wagon counts as on-road. Break numbers (`WHEEL` in `cargo_rules.lua`) are untuned guesses.

## Owned wagons (R16, roads-04)

Players own wagon tiers they bought; `/fh_wagon` stays the admin dev bypass (no ownership check, no charge). Calling and
stowing an owned wagon at a trade post is R17.

**Table** `fh_wagons` (`server/migrations/0021_fh_wagons.sql`; number may change at merge): `citizenid`, `tier`
(`t1`/`t2`/`t3`), `bought_at`; PRIMARY KEY (`citizenid`, `tier`) = one row per owned tier.

**`buyWagon(src, tier, region_id)`** (flow in `server/wagon_buy.lua`, pure, specced in `spec/cargo_buy_spec.lua`):

1. `tier` via `parseTier` (`t2`, `wagon`, `2`, ...) else `fh_bad_tier`; config price else `fh_no_price`; `region_id` a
   non-empty string else `fh_unknown_region`; character loaded else `fh_no_character`. The citizenid is captured here.
2. Busy lock per src AND per citizenid: a second buy while one runs -> `fh_buy_busy` (never charged).
3. Already owned (`fh_wagons` read) -> `fh_already_owned`; read failed -> `fh_db_error`.
4. t2/t3: `fh_progression:canUnlock(src, 'wagon_t2'|'wagon_t3')` (same gate as `spawnWagon`): the returned reason
   (e.g. `tier_too_low`), or `fh_locked` when fh_progression is not started or throws. t1 has no gate.
5. The character is re-checked after every yield (`player_changed` / `fh_no_character`), then
   `fh_economy:charge(src, price, 'wagon_buy', region_id)`. `fh_charge_busy` is retried once after `BuyRetryMs`, then
   refused; every other charge error is returned as is (nothing taken, no row). `fh_economy` not started ->
   `fh_economy_unavailable`. A charge that **throws** has an unknown outcome and fails closed like every other charge
   consumer: `fh_charge_error`, no row, no refund (it could pay twice), and an `ALERT` line with citizenid, tier, price,
   region and the error; check `fh_ledger` for a `wagon_buy` charge and credit by hand if one is there.
6. Only after the charge: `INSERT IGNORE INTO fh_wagons` for the captured citizenid. 1 row -> `true`, emits
   `fh:cargo:wagon_bought`. 0 rows (a concurrent buy already owns it) -> refund, `false, 'fh_already_owned', 'refunded'`.
   DB failure -> refund, `false, 'fh_buy_refunded'`. Refund = `fh_economy:credit(citizenid, price, 'wagon_buy_refund',
   region_id)` (online or queued, to the character who paid). Refund failed -> `false, 'fh_refund_failed'`, `ALERT`
   console line and `fh:cargo:wagon_buy_owed` (never silent).

Errors: `fh_no_player`, `fh_bad_tier`, `fh_no_price`, `fh_unknown_region`, `fh_no_character`, `player_changed`,
`fh_buy_busy`, `fh_already_owned`, `fh_db_error`, `fh_locked` / canUnlock reasons, fh_economy charge codes
(`fh_insufficient_funds`, `fh_charge_busy`, `amount_too_large`, `unknown_region`, `no_player`, `player_changed`,
`removemoney_refused`, `ledger_failed`, ...), `fh_economy_unavailable`, `charge_refused`, `fh_charge_error`, `fh_buy_refunded`,
`fh_refund_failed`, `fh_buy_error`.

**Cargo persists per wagon:** the stash id is `fh:wagon:<citizenid>:<tier>` (`rules.wagonId` / `stashId`), the same on
every spawn. fh_core `registerContainer` -> fh_inventory `RegisterStash` loads the items from the `inventories` row with
that identifier when it is not in memory and `SaveStash` writes them back by the same identifier. Replacing or
despawning a wagon only despawns the entity; fh_cargo never calls `clearContainer` / `deleteContainer` (specced).

## Wheel break and repair (R2)

- **Break roll** (`rules.breakChance` / `rollWheelBreak`, pure, injected RNG): per 1 s server tick, from server-known
  state only: wagon entity velocity (`GetEntityVelocity`, clamped by `sanitizeSpeed`), tier, carried weight. Probability
  rises with speed squared, x4 off-road (owner client's bool hint, accepted only from the owner), up to x2 loaded.
  Never below 1.5 m/s.
- **Broken** wagon: speed cap is 40% of its normal cap (`effectiveSpeedLimit`), pushed to the owner client.
- **Spike gate** (existing convar `fh_spike_gated`, default `true`, no new flag; row 5 of `fh_core/docs/spike-gated.md`):
  gated = broken state + speed cap only, no native; ungated = the client also calls the native wheel break (S3 `spk_wheel`).
- **Items** `hammer` and `wagon_wheel` are registered at start through `exports.fh_core:registerItems` (`rules.ITEMS`).
- `/fh_repair`: own broken wagon within reach, a `hammer` and a `wagon_wheel` in equipped/backpack. An 8 s timed repair
  cancels if you move more than 3 m or leave reach of the wagon. At the end one wheel is consumed with
  `fh_core:removeItem` (all-or-nothing, `false, 'fh_not_enough'`); only then is the wheel fixed.
- `/fh_wheelbreak` (admin): force a break for testing.

| Export | Returns |
|---|---|
| `isWheelBroken(wagonId)` | boolean |
| `getSpeedLimit(wagonId)` | m/s cap incl. load and broken state, or `nil` |

| Event | Payload |
|---|---|
| `fh:cargo:wheel_broken` | `{ src, citizenid, wagon, tier, native }` |
| `fh:cargo:wheel_repaired` | `{ src, citizenid, wagon, tier }` |
