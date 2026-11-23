# fh_cargo

Lane L6 (spec §5, M4), blocks R1 and R2 (wheel break + repair): wagon tiers, cargo loading, fast-travel veto. Uses `fh_core` exports only.

- `shared/cargo_rules.lua`: pure rules (no natives), specced in `spec/cargo_rules_spec.lua`. Tier table, ownership,
  reach, capacity, cargo-only check, fast-travel verdict.
- `server/main.lua`: thin wiring (gathers positions and container views, calls the rules, then ONE `fh_core:move`).
- `config.lua`: wagon models per tier (**unverified in game**), reach, spawn offset.

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
| `spawnWagon(src, tier, coords)` | `wagonId` or `nil, reason` |
| `getWagon(wagonId)` | `{ id, owner, tier, netId, coords }` or `nil` |

## Events (server-local, one table)

| Event | Payload |
|---|---|
| `fh:cargo:fasttravel_blocked` | `{ src, citizenid, reason, wagon }` |
| `fh:cargo:loaded` / `fh:cargo:unloaded` | `{ src, citizenid, wagon, item, count, container }` |
| `fh:cargo:wagon_spawned` | `{ src, citizenid, wagon, tier, netId }` |

## Known gaps / TODO

- **TODO(R0 @core idea-602):** fh_core `requestSpawn` has no kind `wagon` yet. `/fh_wagon` is written against the
  intended contract and says so at runtime (`fh_core cannot spawn wagons yet`) until R0 merges.
- Wagon state is in memory (stash contents persist in fh_inventory by id; the wagon entity does not survive a restart).
- Not runtime-tested (no Cfx key yet); natives side unverified.
- Contracts and delivery are R4.
- **TODO(B7 @core):** `removeItem(ref, item, amt)` is not exported by fh_core yet: `/fh_repair` finishes with `fh_core_no_removeitem` until it lands. `registerItems` is used as-is and failure only prints a warning.
- **TODO(R2 off-road):** no verified road/off-road native, so the client never sends the `fh:cargo:offroad_hint`; every wagon counts as on-road. Break numbers (`WHEEL` in `cargo_rules.lua`) are untuned guesses.

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
