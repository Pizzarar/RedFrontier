# fh_gunsmith (spec L5, plan crafting-01 C3)

`/fh_restore <slot>`: restores the worn weapon sitting in the world container the player has OPEN — a chest, wagon or
saddlebag placed near a gunsmith station — consuming `gun_parts` (+20 quality each, fewest needed) up to the star cap
(1/2/3 stars = 60/80/100; no stars = 1 star). Math: `FhCraftRules.restore` (fh_crafting). Order: write quality, then
consume parts; a failed consume rolls the write back. Removal is `fh_crafting` `invTake` (fh_core carried `removeItem`, core-03). Visual wear is data-only:
`_SET_WEAPON_DEGRADATION` is unproven in fh_core/docs/natives.md. Quality shows in item info.

## Command

| Command | Who | Behaviour |
|---|---|---|
| `/fh_restore <slot>` | player | Restore the item in that slot of the OPEN container if it has a quality. The container must accept bulky (chest / wagon / saddlebag), the player must be within reach of it, and it must sit within 3.0 m of a workbench on the player's OWN plot (`getStations`). Success: `Restored to <n>% quality using <k> gun parts.` The server console is refused. |

Refusals (code strings): `fh_nothing_open` (`Open a chest, wagon or saddlebag first.`), `fh_size_class` (`That
container cannot hold a rifle.`), `fh_out_of_reach` (`You are too far from that container.`), `fh_no_coords` (`That
container has no location.`), `no_station` (`You need to be at a gunsmith station.`), `bad_slot` (`Usage:
/fh_restore <slot>`), `no_weapon` (`Nothing in that slot.`), `no_quality` (`That item has no quality to restore.`),
`at_cap` (`That weapon is already at its best quality.`), `no_parts` (`You need gun parts.`), `no_set_info` (`Writing
item quality is not available yet.`), `no_remove` (`Removing items is not available yet.`). Other reasons
(`fh_not_registrable`, ...) fall through as `Restore failed: <reason>`.

The rifle is read from the pane the player has open (`fh_core` `openRef` + `view`, the same pattern as
`fh_core/server/saddlebag.lua`); the slot indexes that container's slots. `gun_parts` are still consumed from the
carried inventory (`fh_crafting` `invCount` / `invTake`, core-03 carried refs).

## Exports

None. It consumes `fh_core` exports (`openRef`, `view`, `setItemInfo`), `fh_crafting` exports (`getStations`,
`invCount`, `invTake`), and loads `'@fh_crafting/shared/craft_rules.lua'` (restore math), `'@fh_core/config.lua'`
(`FhConfig`, for reach distances) and `'@fh_core/shared/containers.lua'` (the bulky + reach gates, read from
`FhContainers.accepts` / `FhContainers.canReach`).

## Events

| Kind | Event | Payload |
|---|---|---|
| Emits (client) | `fh_gunsmith:conditionChanged` | `(slot, quality, spikeGated)` after a successful restore only |
| Consumes (client) | `fh_gunsmith:conditionChanged` | `client/wear.lua`: while `spikeGated == false` it logs that the degradation native is unverified (data-only) |

The server passes `fh_spike_gated` down because it is a server-only convar (`set`). No other events.

## Config keys

No `config.lua` in this resource:

| Source | Key | Meaning |
|---|---|---|
| `fh_crafting/shared/craft_rules.lua` | `PART_VALUE = 20` | Quality restored per `gun_parts`. |
| `fh_crafting/shared/craft_rules.lua` | `STAR_CAPS = { 60, 80, 100 }` | Quality cap per star rating; missing/invalid stars = 1 star (60), ratings round and clamp to 1..3. |
| convar (server.cfg) | `fh_spike_gated` | Default `true`; `false` makes the client log the data-only fallback instead of applying the unverified native. |
| `fh_crafting/config.lua` | `stationMaxDist`, `devStations` | Station reach and dev stations, via the `fh_crafting` station adapter (`getStations`); `stationTypeMap` maps `gunsmith` to the H3 `workbench`. |

The restore is not a recipe: `fh_crafting/shared/recipes.lua` has no gunsmith entry (the `gunsmith` station type is
reserved for future recipes). Tonics belong to `fh_crafting`.

## Restore maths

- Cap: 1 star 60, 2 stars 80, 3 stars 100; worn loot has no `stars`, so it is capped at 60.
- Parts: `ceil((cap - quality) / 20)`, limited by the parts held; the new quality never passes the cap.
- Refusals before any write: no open container, non-bulky container type, player out of reach / no container coords,
  container not near a gunsmith station, bad slot, no item, no quality, already at/above cap, no parts, no
  `setItemInfo` contract. On a failed part removal the quality write is rolled back; a failed rollback is logged at
  error level (`ERROR rollback failed ... quality raised, parts not taken`).

## Pending contracts

- **@homestead H2 `/fh_build`** (not on main yet): H3 stations are real, but a workbench exists only once built.
  Restore reach is `fh_crafting` `getStations(citizenid)` filtered to `workbench` (own plot only, coordinates compared
  with the open container's `view.coords`, vector3 or table); before the homestead slot load finishes it is `{}` and
  restore refuses `no_station`. Use `fh_dev 1` dev stations until H2 lands.
- **idea-612 (tonic caps in fh_buffs)**: does not affect restore; listed because the same lane's apothecary waits on it.

Resolved: core-03 carried add/remove (idea-615) and `setItemInfo(ref, slot, info, expectName)` (idea-689); restore
passes the weapon item name as `expectName`. `no_set_info` now appears only when fh_core lacks the export.
