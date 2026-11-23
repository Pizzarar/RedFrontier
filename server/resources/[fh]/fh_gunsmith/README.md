# fh_gunsmith (spec L5, plan crafting-01 C3)

`/fh_restore <slot>`: restores the worn weapon sitting in the world container the player has OPEN — a chest, wagon or
saddlebag placed near a gunsmith station — consuming `gun_parts` (+20 condition each, fewest needed) up to the star cap
(1/2/3 stars = 60/80/100; no stars = 1 star). Math: `FhCraftRules.restore` (fh_crafting). Order: write condition, then
consume parts; a failed consume rolls the write back. Removal is `fh_crafting` `invTake` (B7 `removeItem`-backed); until
that lands it refuses with `no_remove` (Workaround, replaced by C5b). Visual wear is data-only:
`_SET_WEAPON_DEGRADATION` is unproven in fh_core/docs/natives.md. Condition shows in item info.

## Command

| Command | Who | Behaviour |
|---|---|---|
| `/fh_restore <slot>` | player | Restore the item in that slot of the OPEN container if it has a condition. The container must accept bulky (chest / wagon / saddlebag), the player must be within reach of it, and it must sit near a gunsmith station. Success: `Restored to <n>% condition using <k> gun parts.` The server console is refused. |

Refusals (code strings): `fh_nothing_open` (`Open a chest, wagon or saddlebag first.`), `fh_size_class` (`That
container cannot hold a rifle.`), `fh_out_of_reach` (`You are too far from that container.`), `fh_no_coords` (`That
container has no location.`), `no_station` (`You need to be at a gunsmith station.`), `bad_slot` (`Usage:
/fh_restore <slot>`), `no_weapon` (`Nothing in that slot.`), `no_condition` (`That item has no condition to restore.`),
`at_cap` (`That weapon is already at its best condition.`), `no_parts` (`You need gun parts.`), `no_set_info` (`Writing
item condition is not available yet.`), `no_remove` (`Removing items is not available yet.`). Other reasons
(`fh_not_registrable`, ...) fall through as `Restore failed: <reason>`.

The rifle is read from the pane the player has open (`fh_core` `openRef` + `view`, the same pattern as
`fh_core/server/saddlebag.lua`); the slot indexes that container's slots. `gun_parts` are still consumed from the
carried inventory (`fh_crafting` `invCount` / `invTake`); block C5b swaps that to `@core` B7.

## Exports

None. It consumes `fh_core` exports (`openRef`, `view`, `setItemInfo`), `fh_crafting` exports (`stationAt`,
`invCount`, `invTake`), and loads `'@fh_crafting/shared/craft_rules.lua'` (restore math), `'@fh_core/config.lua'`
(`FhConfig`, for reach distances) and `'@fh_core/shared/containers.lua'` (the bulky + reach gates, read from
`FhContainers.accepts` / `FhContainers.canReach`).

## Events

| Kind | Event | Payload |
|---|---|---|
| Emits (client) | `fh_gunsmith:conditionChanged` | `(slot, condition, spikeGated)` after a successful restore only |
| Consumes (client) | `fh_gunsmith:conditionChanged` | `client/wear.lua`: while `spikeGated == false` it logs that the degradation native is unverified (data-only) |

The server passes `fh_spike_gated` down because it is a server-only convar (`set`). No other events.

## Config keys

No `config.lua` in this resource:

| Source | Key | Meaning |
|---|---|---|
| `fh_crafting/shared/craft_rules.lua` | `PART_VALUE = 20` | Condition restored per `gun_parts`. |
| `fh_crafting/shared/craft_rules.lua` | `STAR_CAPS = { 60, 80, 100 }` | Condition cap per star rating; missing/invalid stars = 1 star (60), ratings round and clamp to 1..3. |
| convar (server.cfg) | `fh_spike_gated` | Default `true`; `false` makes the client log the data-only fallback instead of applying the unverified native. |
| `fh_crafting/config.lua` | `stationMaxDist`, `devStations` | Station reach and dev stations, via the `fh_crafting` station adapter (`stationAt`). |

The restore is not a recipe: `fh_crafting/shared/recipes.lua` has no gunsmith entry (the `gunsmith` station type is
reserved for future recipes). Tonics belong to `fh_crafting`.

## Restore maths

- Cap: 1 star 60, 2 stars 80, 3 stars 100; worn loot has no `stars`, so it is capped at 60.
- Parts: `ceil((cap - condition) / 20)`, limited by the parts held; the new condition never passes the cap.
- Refusals before any write: no open container, non-bulky container type, player out of reach / no container coords,
  container not near a gunsmith station, bad slot, no item, no condition, already at/above cap, no parts, no
  `setItemInfo` contract. On a failed part removal the condition write is rolled back; a failed rollback is logged at
  error level (`ERROR rollback failed ... condition raised, parts not taken`).

## Pending contracts

- **@homestead H3 station API** (`isNearStation`/`getStations`/`stationAt`): not on main yet; `fh_crafting` falls back
  to `devStations` while `fh_dev 1`. Removed by block C5.
- **@core B7 `removeItem(ref, item, amount)`** (+ idea-615 carried refs): `invTake` refuses `no_remove` until the export
  lands, so `gun_parts` cannot be consumed yet. C5b swaps this in.
- **@core `setItemInfo(ref, slot, info)` (idea-689)**: not built yet. `fh_gunsmith` calls it only when the export
  exists; otherwise it refuses `no_set_info` before any parts are taken, so restore cannot write a raised condition in
  game until this contract lands.
- **idea-612 (tonic caps in fh_buffs)**: does not affect restore; listed because the same lane's apothecary waits on it.
