# fh_cargo

Lane L6 (spec §5, M4), block R1: wagon tiers, cargo loading, fast-travel veto. Uses `fh_core` exports only.

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

Tier numbers are not config: they live in `shared/cargo_rules.lua` (`TIERS`).

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
| `nearestWagon(src, coords, range)` | Container ref `{ type = 'wagon', id = 'fh:wagon:...' }` (what `fh_core` `move` accepts) of the nearest LIVE wagon within `range` m of `coords` (nil = the player's ped) that `src` may load into (v1: owner only), else `nil`. `range` must be > 0 and is capped at 25 m. Bad args return `nil`, never throw. Used by fh_hunting |
| `getWagon(wagonId)` | `{ id, owner, tier, netId, coords }` or `nil` |

## Events (server-local, one table)

| Event | Payload |
|---|---|
| `fh:cargo:fasttravel_blocked` | `{ src, citizenid, reason, wagon }` |
| `fh:cargo:loaded` / `fh:cargo:unloaded` | `{ src, citizenid, wagon, item, count, container }` |
| `fh:cargo:wagon_spawned` | `{ src, citizenid, wagon, tier, netId }` |

## In-game check list (spec §9; needs R0 merged for step 1)

1. As admin: `/fh_wagon t2`. A wagon appears 4 m ahead; chat confirms. Before R0: chat says it cannot spawn wagons yet.
2. Open a homestead chest holding a cargo item (`/fh_give <id> test_cargo_crate`, drop it in the chest). Stand by the wagon, `/fh_cargo load 1`: the crate moves to the wagon.
3. Walk 20 m away, `/fh_cargo load 1` again: refused `fh_out_of_reach`. A second character cannot load into your wagon (`fh_not_owner`).
4. Try a non-cargo item (`bread`): refused `fh_not_cargo`. Fill a `t1` past 120 kg: refused `fh_too_heavy`.
5. Fast-travel check from the server console or another resource: `exports.fh_cargo:canFastTravel(src)` returns `false, fh_cargo_wagon_near` while loaded wagon is within 30 m, `true` once unloaded or far away; `fh:cargo:fasttravel_blocked` fires on each block.
6. Stop `fh_inventory`, call `canFastTravel` again: `false, fh_cargo_unknown` (fails closed).
7. `/fh_wagon t2` twice: the old wagon is replaced and its cargo is still there.

## Known gaps / TODO

- **TODO(R0 @core idea-602):** fh_core `requestSpawn` has no kind `wagon` yet. `/fh_wagon` is written against the
  intended contract and says so at runtime (`fh_core cannot spawn wagons yet`) until R0 merges.
- Wagon state is in memory (stash contents persist in fh_inventory by id; the wagon entity does not survive a restart).
- Not runtime-tested (no Cfx key yet); natives side unverified.
- Wheel break / repair is R2; contracts and delivery are R4.
