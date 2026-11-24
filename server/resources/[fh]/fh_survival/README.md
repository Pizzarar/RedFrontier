# fh_survival

Survival needs as timed buffs (plan `docs/brainstorm/plans/survival-01-needs.md`). Food, water, rest, cleanliness
and (in cold regions) warmth are positive `fh_buffs` buffs. What is missing is turned into a sluggish level 0-3.
**Never lethal:** this resource never reads or writes health. It does not use rsg-core hunger/thirst/cleanliness metadata.

Status: S2 server core, S3 actions (food, canteen, wash, warmth), S4 rest/comfort and S5 client sluggish effect.

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
- `exports.fh_survival:setHeatSource(id, coords, radius?)` -> boolean: add/replace a live heat source (campfire) that gives `warm`. `coords` = `{x, y, z?}`.
- `exports.fh_survival:removeHeatSource(id)` -> true.
Logic lives in `shared/needs.lua` (`FhSurvivalNeeds`) and `shared/items.lua` (`FhSurvivalItems`), both pure and specced.

## Items and actions (S3)
Items are defined in `shared/items.lua` and registered with `exports.fh_core:registerItems` on resource start and again whenever `fh_core` restarts (no guard; a refusal is logged with its error code and item name). Names are lowercase `[a-z0-9_]` and each def is a full §4.1 definition (`illicit` explicit).
| Item | Effect |
|---|---|
| `fh_jerky` | consumed, `well_fed` 1.0 for 50% of the configured duration |
| `fh_biscuit` | consumed, `well_fed` 1.0 for 35% |
| `fh_stew` | consumed, `well_fed` 1.15 for 100% |
| `fh_canteen` | spends one charge (`info.charges`, max `CanteenMax`), gives `hydrated` 1.0. No `charges` key = fresh = full. Empty refuses |

Base rsg-core/loot consumables (`rsg-core/shared/items.lua`) are also consumed through the same S3 path. They are
**not** defined by `fh_core:registerItems` — fh_survival only registers their useable callback (`CreateUseableItem`,
again on `rsg-core` restart) and skips (one log line) any row whose item is not yet in `RSGCore.Shared.Items`, so a
`@crafting`/`@hunting` item is a one-row add later. Fractions are on the jerky/biscuit/stew scale (see
`shared/items.lua` for the per-row justification); no new config keys are needed (durations still come from `Durations`).
| Item | Effect |
|---|---|
| `bread` | consumed, `well_fed` 1.0 for 35% |
| `canned_beans` / `canned_salmon` | consumed, `well_fed` 1.0 for 60% |
| `canned_apricots` | consumed, `well_fed` 1.0 for 40% |
| `cooked_meat` / `jerky_meat` | consumed, `well_fed` 1.0 for 50% |
| `stew` | consumed, `well_fed` 1.0 for 100% |
| `stew_veg` | consumed, `well_fed` 1.0 for 85% |
| `water` | consumed, `hydrated` 1.0 for 100% |
| `coffee` | consumed, `hydrated` 1.0 for 60% |
Commands (client, any player): `/refill` (canteen back to full) and `/wash` (`clean`, once per `WashCooldownSeconds`). Both need standing in water:
server-side zone check against `WaterZones` by default; `WaterCheck = 'native'` trusts the client's `IsEntityInWater` (unverified, see `fh_core/docs/natives.md`).
Warmth: every `HeatCheckSeconds` a player within `HeatRadius` of a `Campfires` entry (or a `setHeatSource` source) gets `warm` 1.0 for the full `warm` duration.
Warm is only a bonus: `ColdRegions` stays `{}`.

## Rest and comfort (S4)
Server: `restBedroll(src)` (rested 1.0), `restAtBed(src)` (needs a homestead `bed` station nearby; magnitude 1.0 + comfort x `ComfortK`, capped at `RestedCap`). Both return `ok, magnitude|err`. Net event `fh:survival:restBed` (client asks; server re-checks proximity). Bedroll item `bedroll` (usable) is defined in `shared/items.lua` `ITEMS` and registered with the S3 items by `server/actions.lua` through `fh_core:registerItems`; `server/rest.lua` only registers its usable callback (again on `rsg-core` restart).
Homestead exports `isNearStation(src,'bed')` (H3) and `getComfort(citizenid)` (H4) are called directly by `server/homestead_adapter.lua` (fh_homestead is a declared dependency); if fh_homestead is not started the adapter reports no bed and comfort 0.

## Events
- Emits (server -> client) `fh:survival:state`, payload `{ level = 0..3, missing = { 'food', 'water', 'rest', 'clean', 'warmth' } }`
  (`missing` = need names, in that fixed order, `warmth` only when in a cold region). Sent on the first tick after load and
  whenever level or missing changes (not every tick). For @ui: level 0 = fine, 3 = worst.
- Consumes (client -> server, S3): `fh:survival:refill` and `fh:survival:wash`, each with one boolean (client's in-water flag, read only when `WaterCheck = 'native'`).
- Emits (server -> client, S3): `fh:survival:notify` (string message; the client shows it through `ox_lib:notify`).
- Consumes: `RSGCore:Server:PlayerLoaded` (restore), `RSGCore:Server:OnPlayerUnload` and `playerDropped` (save),
  `onResourceStart` (boot check, pick up online players), `onResourceStop` and `txAdmin:events:serverShuttingDown`
  (save everyone, non-yielding), `fh:buffs:applied` (refresh the cached snapshot used on drop).
- Reads (not events): `exports.fh_buffs:get(src)`; writes: `exports.fh_buffs:apply(src, id, magnitude, duration)` on restore (S2) and for food/canteen/wash/campfire (S3: `well_fed`, `hydrated`, `clean`, `warm`) and on rest (S4: `rested`).
- Consumes (client -> server, net) `fh:survival:restBed` (no payload; server re-checks bed proximity). Also `onResourceStart` of `rsg-core` (re-register its usable callback).
- Buffs show in the U2 HUD via `fh:buffs:sync` already.

## Persistence
On drop/unload/resource stop, remaining seconds and magnitude per active need are saved to `fh_survival_needs`. On load
they are re-applied (duration = min(saved remaining, configured max), never extended; offline time does not count down).
A character with **no row** gets `LoginGraceSeconds` before sluggish can start. A row (even empty) means no grace.
fh_buffs may clear its state before our `playerDropped` handler runs, so the save falls back to a cached snapshot. The cache
is filled right after restore, on every tick and on every `fh:buffs:applied`, so a drop before the first tick keeps restored buffs.

Lifecycle rules (Tier A):
- Each load takes a fresh token; a drop clears it. After the DB read resumes, the load is applied only if its token is still
  current and the player is still loaded as the same citizenid (`FhSurvivalNeeds.loadIsCurrent`). Otherwise it is discarded:
  no record, no buffs (covers drop mid-load and character switch on the same src).
- A drop pops the record before the DB write yields, so OnPlayerUnload + playerDropped write once.
- Resource stop / server shutdown reads every snapshot synchronously and dispatches non-yielding `MySQL.update` calls.
- If the login DB read failed, an empty snapshot is never written over the stored row (`FhSurvivalNeeds.shouldSave`);
  buffs gained since login are still written.

## Config keys (`config.lua`, `FhSurvivalConfig`)
`TickSeconds` (15), `LoginGraceSeconds` (600), `Durations`, `ColdRegions` (`{ region_id = true }`, empty: no cold region exists yet),
`LevelMap` (missing count -> level), `SluggishEffect` (`'notify'` | `'native'`). S3 keys: `CanteenMax` (5), `WashCooldownSeconds` (300), `WaterCheck` (`'zones'` | `'native'`), `WaterZones` and `Campfires` (`{x,y,z?,radius?}` lists), `HeatRadius` (4.0), `HeatCheckSeconds` (10). S4 keys: `ComfortK` (0.01), `RestedCap` (1.20). S5 keys: `SluggishText`, `SluggishRegen`, `SluggishClipset` (nil), `SluggishDeadeyeHash` (nil), `SluggishNotifyCooldownMs` (60000).
Seeded defaults (approximate, owner-verifiable, all 2D): `WaterZones` (-250,760,r40) and (-140,790,r40) on the Dakota River near the
heartlands homestead (-300,790,118) / outlaw camp (-145,845,117); `Campfires` (-300,790,r8) homestead and (-145,845,r8) camp.
Native mode never runs unless `WaterCheck = 'native'`: the client does not call `IsEntityInWater` in zones mode.
The player's region is `FhRegions.territoryAt(x, y).region` from the server-side ped position; outside every territory it is nil (no warmth need).

## DB tables
`fh_survival_needs(citizenid PK, needs JSON text, updated_at unix s)` from `server/migrations/0012_survival_needs.sql`.

## Tests
`python tools/run-specs.py spec/survival_needs_spec.lua spec/survival_items_spec.lua spec/survival_rest_spec.lua` (pure logic). Syntax: `python tools/run-specs.py --syntax "server/resources/[fh]/fh_survival"`.

## In-game checklist (S2)
1. Boot console: `[fh_survival] unknown_buff hydrated` / `clean` appear until @core adds caps; nothing else errors.
2. Server console `fh_buff <serverId> well_fed 1.0 600` (fh_buffs helper); `fh:survival:state` arrives on the next tick.
3. Fresh character: level stays 0 for 10 min even with nothing applied. After that, level rises with each missing need.
4. Apply `well_fed`, relog: it is re-applied with the remaining time. Restart the server: same.
5. Health never changes at any level.

## Sluggish effect (S5, `client/effects.lua`, `shared/effects.lua`)
Consumes `fh:survival:state`. `notify` (default): one chat line `<text> (level N/3)` when the level changes to a non-zero level,
at most once per `SluggishNotifyCooldownMs`; no natives. `native` (opt-in, unverified in game): stamina recharge multiplier by level
(`SluggishRegen`, clamped 0.1..1.0, never fully stopped), dead-eye multiplier only if `SluggishDeadeyeHash` is set, and a movement
clipset at level 3 only if `SluggishClipset` is set. Effects are reset at level 0 and on resource stop. Natives and hashes: `fh_core/docs/natives.md`.
Pure mapping `FhSurvivalEffects.params(level, mode, cfg)` is covered by `spec/survival_effects_spec.lua`.
