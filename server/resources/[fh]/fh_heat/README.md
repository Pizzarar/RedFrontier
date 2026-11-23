# fh_heat: faction heat (spec L7, roads R5)

Per-character, per-faction heat 0-100 (factions from fh_core `shared/regions.lua`). Server-authoritative, persisted in
`fh_heat` (`server/migrations/0008_fh_heat.sql`). NOT runtime-tested yet (no Cfx key).

## Rules (`shared/heat_rules.lua`, specced in `spec/heat_rules_spec.lua`)

- `add` / `clamp`: 0..100, rounded to 2 decimals.
- **Sources** (data in `config.lua` `sources`): `camp_clear` 25, `illicit_sale` 10 (scaled by an optional multiplier).
- **Lay low**: `decayPerMinute` (2.0), ticked every `decayTickSeconds`, only while the player is NOT inside a territory
  of that faction.
- **Thresholds** (`watched` 25, `wanted` 50, `hunted` 75): `level(heat)`.
- **Bounty**: `bountyPerPoint` money per heat point, rounded up; pay all or some points.

## Exports (server)

| Export | Returns |
|---|---|
| `get(src, faction)` | heat, or `nil, err` |
| `set(src, faction, value)` | `true, new` / `false, err` (fh_core admin `fh_heat` delegates here once @core B7 merges) |
| `add(src, faction, amount, reason)` | `true, new` / `false, err`; fh_trade calls this for illicit sales |
| `addSource(src, faction, key[, mult])` | same, amount from `config.sources[key] * mult` |
| `getAll(src)` | `{ [faction] = { heat, level } }` for the HUD (@ui) |
| `level(src, faction)` | threshold name or `nil` |
| `payoff(src, faction[, points])` | `true, pointsPaid, cost` / `false, err, cost`; points omitted = all, more than heat is capped |

Errors: `fh_unknown_faction`, `fh_no_character`, `fh_bad_amount`, `fh_unknown_source`, `fh_no_heat`,
`fh_insufficient_funds`, `fh_economy_unavailable`, `fh_unknown_region`, `fh_payoff_busy`, `fh_payoff_error`,
`fh_payoff_refunded` (the heat reset failed after the charge; the exact amount was credited back, safe to retry),
`fh_payoff_refund_failed` (charged, heat reset AND refund failed: `[fh_heat] ERROR payoff cid=.. faction=.. amount=..`
logged for a manual fix; do not retry);
fh_economy `charge` codes pass through.

## Events

Payloads follow `fh_core/docs/events.md`: one table argument, `src` first. Emits (server, built by
`rules.changeEvents`):

| Event | Payload |
|---|---|
| `fh:heat:changed` | `{ src, citizenid, faction, old, value, delta, level, reason }` on every change; `level` = new threshold name or nil; `reason` = source key, `set`, `decay` or `bounty_payoff` |
| `fh:heat:threshold` | `{ src, citizenid, faction, old_level, level, value }` when the level changes |

Example consumer: `AddEventHandler('fh:heat:threshold', function(e) if e.level == 'wanted' then ... end end)`.
R6 (roadblocks / ambush / chase) listens to `fh:heat:threshold`, see "Roadblocks" below.
Consumes: `fh:zones:camp_cleared` `{ camp_id, region_id, loot }`. The event names no player, so every player standing in
a territory of that region gets `camp_clear` heat with that territory's faction.

## Bounty payoff

`/paybounty` lists heat and cost; `/paybounty <faction> [points]` pays (chat fallback; @ui can call `payoff`).
Only an omitted `points` means "all"; a non-numeric, 0, negative, NaN/inf or more-than-your-heat value is refused
with a message and nothing is charged (`rules.parsePoints`).

- **Charge**: `exports.fh_economy:charge(src, amount, reason, region_id)` -> `false, 'fh_insufficient_funds'`, never
  negative. `region_id` (ledger column is NOT NULL): the region of the territory the player stands in, else the
  faction's home region (first region by id listing the faction); none -> `fh_unknown_region`, no charge
  (`rules.chargeRegion`). `charge` lands with @core B7; until then payoff fails gracefully with `fh_economy_unavailable`.
- **One at a time**: a payoff holds an in-flight lock per (citizenid, faction) across the charge and the heat reset
  (`rules.runPayoff`). A second request while one is in flight gets `fh_payoff_busy` and is never charged. The lock is
  always released (success, refusal, early return, error), and only after any refund resolved.
- **Persisted or refunded**: the heat reset is written with `MySQL.query.await`; the payoff succeeds only once that
  write landed. If the write fails (memory is rolled back) or anything after the charge throws, the exact charged
  amount is credited back with `exports.fh_economy:pay(src, amount, refundReason, region_id)` (same region as the
  charge) while the lock is still held -> `fh_payoff_refunded`. If that also fails -> `fh_payoff_refund_failed` +
  ERROR log. A refund needs the player online (fh_economy `no_player`), so a drop mid-payoff can end there.
  Other heat changes (gains, decay, admin set) stay fire-and-forget writes.
- If the player dropped while the payoff yielded, its cache entry is cleared afterwards (all payoff changes are
  persisted), unless the character is online again.

## Decay loop

Each decay tick and each player within it runs under `rules.safeTick` (pcall): an error is logged
(`[fh_heat] ERROR decay ...`) and the loop keeps running.

## Roadblocks, night ambush, chase (R6)

Pure decisions: `shared/roadblock_rules.lua` (specced in `spec/roadblock_rules_spec.lua`); natives and spawning:
`server/roadblocks.lua`; hostile AI: `client/main.lua`. Config: `FhHeatConfig.roadblock / ambush / chase`.

**Roadblock (always on).** When a player's level for a faction RISES onto or past `roadblock.minLevel` (`wanted`) the
server picks the chokepoint nearest the player (preferring chokepoints of the player's region, within
`maxPlayerDistance`) and requests `ped.count` faction peds in a line across it with
`exports.fh_core:requestSpawn` (kind `ped`, tag `fh_heat:roadblock:<faction>:<n>`). The spawning client makes them
hostile (`fh:spawn:adopted`, same pattern as fh_zones). Guards: one live roadblock per player+faction,
`cooldownSeconds` per player+faction, `maxConcurrent` server-wide. It is cleared (peds `despawn`ed) after
`despawnMinutes`, when that player's level drops below `minLevel` (threshold event or the sweep), when the player
drops, and on resource stop. Chokepoint coordinates are approximate and **unverified**.

**Night ambush + mounted chase (gated).** Both run ONLY when convar `fh_spike_gated` is `false` (default `true`, read
on every use). Gated: no-op, one log line per threshold event (`night ambush skipped: fh_spike_gated=true ...`).
Rows 5-6 in `fh_core/docs/spike-gated.md`; flipped by S2 `spk_chase` RESULT.
- Ambush: at `ambush.minLevel` (`hunted`) during `nightFrom`..`nightTo` game hours, peds ring the player at `radius`.
- Chase: at `chase.minLevel` while the player is mounted/in a vehicle (server natives unverified), rider peds + horses
  spawn `behind` metres back; the target's client seats each rider (`fh:heat:chase`, `TaskMountAnimal`).
  No wagon pursuit: `requestSpawn` has no wagon kind until M4.
Ungated, a sweep every `tickSeconds` also evaluates players already above the level.

Events (one table, `src` first): `fh:heat:roadblock_spawned` `{ src, citizenid, faction, roadblock_id, chokepoint_id,
region_id, level, peds, expires_at }`; `fh:heat:roadblock_cleared` `{ src, citizenid, faction, roadblock_id,
chokepoint_id, reason }` (`heat_dropped` / `expired` / `player_dropped` / `resource_stop`). Ungated only:
`fh:heat:ambush_spawned`, `fh:heat:chase_started` (`group_id`), `fh:heat:ambush_cleared`, `fh:heat:chase_cleared`.

### In-game test checklist (not runtime-tested; no Cfx key yet)
1. `exports.fh_heat:set(src, "outlaws", 55)` (or the fh_core admin `fh_heat`) outlaws heat to 55 near the heartlands: one roadblock of 4 outlaw peds
   appears at the nearest chokepoint, hostile, and `fh:heat:roadblock_spawned` fires. Heat 30 -> 55 again: no second one.
2. Read the real coords/heading at the spot, fix `chokepoints`, drop `unverified`.
3. Drop heat below 50 (set 20): roadblock peds vanish, `roadblock_cleared` reason `heat_dropped`.
4. Raise to 55 again inside `cooldownSeconds`: nothing spawns, log says `cooldown`. Different faction: independent.
5. Wait `despawnMinutes` (set 1 to test): `expired`. Disconnect with one live: `player_dropped`, peds gone.
6. `restart fh_heat`: peds gone. Spawn 5 roadblocks as different players: the 5th is refused (`max_concurrent`).
7. Gated (default): heat 80 at night: log line for ambush and chase, nothing spawns. `set fh_spike_gated false`,
   ride a horse at night with hunted heat: ring ambush, then riders behind that mount and attack.

## Install

Apply migration 0008, `ensure fh_heat` (already in `server/server.cfg`, after fh_zones).
