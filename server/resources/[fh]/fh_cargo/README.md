# fh_cargo

Lane L6 (spec §5, M4), block R1: wagon tiers, cargo loading, fast-travel veto. Uses `fh_core` exports only.

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

A full wagon is slowed by 40% (`speedLimit(tier, weight)`). Nothing applies the cap to the vehicle yet (R2).
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
- Wheel break / repair is R2; contracts and delivery are R4.
