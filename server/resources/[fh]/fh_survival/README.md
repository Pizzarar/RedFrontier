# fh_survival

Survival needs as timed buffs (plan `docs/brainstorm/plans/survival-01-needs.md`). Food, water, rest, cleanliness
and (in cold regions) warmth are positive `fh_buffs` buffs. What is missing is turned into a sluggish level 0-3.
**Never lethal:** this resource never reads or writes health. It does not use rsg-core hunger/thirst/cleanliness metadata.

Status: S2 server core (tick, state event, persistence). Items/actions (S3), rest/comfort (S4) and the client effect (S5) follow.

## Needs
| Need | Buff id | Default duration | Counts as core |
|---|---|---|---|
| food | `well_fed` | 60 min | always |
| water | `hydrated` | 45 min | always |
| rest | `rested` | 120 min | always |
| clean | `clean` | 90 min | always |
| warmth | `warm` | 20 min | only in `ColdRegions` |

`hydrated` and `clean` need caps in `fh_buffs/config.lua` (requested from @core). Until then boot logs `unknown_buff <id>`
once per id and the other needs keep running.

## Exports
None yet (S3/S4 add the apply paths). Logic lives in `shared/needs.lua` (`FhSurvivalNeeds` global on the server).

## Events
- Emits (server -> client) `fh:survival:state`, payload `{ level = 0..3, missing = { 'food', 'water', 'rest', 'clean', 'warmth' } }`
  (`missing` = need names, in that fixed order, `warmth` only when in a cold region). Sent on the first tick after load and
  whenever level or missing changes (not every tick). For @ui: level 0 = fine, 3 = worst.
- Consumes: `RSGCore:Server:PlayerLoaded` (restore), `RSGCore:Server:OnPlayerUnload` and `playerDropped` (save),
  `onResourceStart` (boot check, pick up online players), `onResourceStop` (save everyone).
- Reads (not events): `exports.fh_buffs:get(src)`; writes: `exports.fh_buffs:apply(src, id, magnitude, duration)` on restore only.
- Buffs show in the U2 HUD via `fh:buffs:sync` already.

## Persistence
On drop/unload/resource stop, remaining seconds and magnitude per active need are saved to `fh_survival_needs`. On load
they are re-applied (duration = min(saved remaining, configured max), never extended; offline time does not count down).
A character with **no row** gets `LoginGraceSeconds` before sluggish can start. A row (even empty) means no grace.
fh_buffs may clear its state before our `playerDropped` handler runs, so each tick caches the last snapshot and the save falls back to it.

## Config keys (`config.lua`, `FhSurvivalConfig`)
`TickSeconds` (15), `LoginGraceSeconds` (600), `Durations`, `ColdRegions` (`{ region_id = true }`, empty: no cold region exists yet),
`LevelMap` (missing count -> level), `SluggishEffect` (`'notify'` | `'native'`, used from S5). Sections reserved for S3/S4/S5.
The player's region is `FhRegions.territoryAt(x, y).region` from the server-side ped position; outside every territory it is nil (no warmth need).

## DB tables
`fh_survival_needs(citizenid PK, needs JSON text, updated_at unix s)` from `server/migrations/0006_survival_needs.sql`.

## Tests
`python tools/run-specs.py spec/survival_needs_spec.lua` (pure logic). Syntax: `python tools/run-specs.py --syntax "server/resources/[fh]/fh_survival"`.

## In-game checklist (S2)
1. Boot console: `[fh_survival] unknown_buff hydrated` / `clean` appear until @core adds caps; nothing else errors.
2. Server console `fh_buff <serverId> well_fed 1.0 600` (fh_buffs helper); `fh:survival:state` arrives on the next tick.
3. Fresh character: level stays 0 for 10 min even with nothing applied. After that, level rises with each missing need.
4. Apply `well_fed`, relog: it is re-applied with the remaining time. Restart the server: same.
5. Health never changes at any level.
