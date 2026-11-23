# fh_heat: faction heat (spec L7, roads R5)

Per-character, per-faction heat 0-100 (factions from fh_core `shared/regions.lua`). Server-authoritative, persisted in
`fh_heat` (`server/migrations/0005_fh_heat.sql`). NOT runtime-tested yet (no Cfx key).

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
`fh_payoff_commit_failed` (charged but the heat reset failed: logged with ERROR for a manual fix);
fh_economy `charge` codes pass through.

## Events

Payloads follow `fh_core/docs/events.md`: one table argument, `src` first. Emits (server, built by
`rules.changeEvents`):

| Event | Payload |
|---|---|
| `fh:heat:changed` | `{ src, citizenid, faction, old, value, delta, level, reason }` on every change; `level` = new threshold name or nil; `reason` = source key, `set`, `decay` or `bounty_payoff` |
| `fh:heat:threshold` | `{ src, citizenid, faction, old_level, level, value }` when the level changes |

Example consumer: `AddEventHandler('fh:heat:threshold', function(e) if e.level == 'wanted' then ... end end)`.
**R6 hook point**: roadblocks / ambush / chase listen to `fh:heat:threshold`. Not implemented here.
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
  always released (success, refusal, early return, error).

## Decay loop

Each decay tick and each player within it runs under `rules.safeTick` (pcall): an error is logged
(`[fh_heat] ERROR decay ...`) and the loop keeps running.

## Install

Apply migration 0005, `ensure fh_heat` (already in `server/server.cfg`, after fh_zones).
