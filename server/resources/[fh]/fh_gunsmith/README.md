# fh_gunsmith (spec L5, plan crafting-01 C3)

`/fh_restore <slot>`: at a gunsmith station (fh_crafting `isNearStation`), consumes `gun_parts` (+20 condition each,
fewest needed) up to the star cap (1/2/3 stars = 60/80/100; no stars = 1 star). Math: `FhCraftRules.restore`
(fh_crafting). Order: write condition, then consume parts; a failed consume rolls the write back. Removal is
`fh_crafting` `invTake` (B7 `removeItem`-backed); until that lands it refuses with `no_remove` (Workaround, replaced by
C5). Visual wear is data-only: `_SET_WEAPON_DEGRADATION` is unproven in fh_core/docs/natives.md. Condition shows in
item info.

## Command

| Command | Who | Behaviour |
|---|---|---|
| `/fh_restore <slot>` | player | Restore the item in that carried slot if it has a condition. Success: `Restored to <n>% condition using <k> gun parts.` The server console is refused. |

Refusals (code strings): `no_station`, `bad_slot` (`Usage: /fh_restore <slot>`), `no_weapon` (`Nothing in that slot.`),
`no_condition` (`That item has no condition to restore.`), `at_cap` (`That weapon is already at its best condition.`),
`no_parts` (`You need gun parts.`), `no_remove` (`Removing items is not available yet.`). Other reasons (`no_set_info`,
`fh_not_registrable`, ...) fall through as `Restore failed: <reason>`.

Runs on the carried inventory only (`fh_crafting` `invSlot` / `invCount` / `invTake`): equipped (slots 1-5) then
backpack, never a saddlebag, wagon or chest.

## Exports

None. It consumes `fh_crafting` exports (`isNearStation`, `invSlot`, `invCount`, `invSetInfo`, `invTake`) and loads
`'@fh_crafting/shared/craft_rules.lua'` for the restore math.

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
| `fh_crafting/config.lua` | `stationMaxDist`, `devStations` | Station reach and dev stations, via the `fh_crafting` station adapter. |

The restore is not a recipe: `fh_crafting/shared/recipes.lua` has no gunsmith entry (the `gunsmith` station type is
reserved for future recipes). Tonics belong to `fh_crafting`.

## Restore maths

- Cap: 1 star 60, 2 stars 80, 3 stars 100; worn loot has no `stars`, so it is capped at 60.
- Parts: `ceil((cap - condition) / 20)`, limited by the parts held; the new condition never passes the cap.
- Refusals before any write: no station, bad slot, no item, no condition, already at/above cap, no parts. On a failed
  part removal the condition write is rolled back; a failed rollback is logged at error level
  (`ERROR rollback failed ... condition raised, parts not taken`).

## Pending contracts

- **@homestead H3 station API** (`isNearStation`): not on main yet; `fh_crafting` falls back to `devStations` while
  `fh_dev 1` (needs a built gunsmith station otherwise). Removed by block C5.
- **@core B7 `removeItem(ref, item, amount)`**: `invTake` refuses `no_remove` until the export lands (or @core accepts
  carried refs, idea-615). C5.
- **idea-615 (carried-inventory add/remove)**: B7 refuses carried refs (`fh_not_registrable`), so `/fh_restore` refuses
  safely instead of consuming parts.
- **idea-612 (tonic caps in fh_buffs)**: does not affect restore; listed because the same lane's apothecary waits on it.
- **@core carried-item `setInfo` contract**: `fh_crafting` `invSetInfo` always refuses `no_set_info`, so the condition
  write fails before parts are touched (`Restore failed: no_set_info`). Restore cannot succeed in game until this
  contract exists.
