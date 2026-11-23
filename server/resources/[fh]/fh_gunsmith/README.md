# fh_gunsmith (spec L5, plan crafting-01 C3)
`/fh_restore <slot>`: at a gunsmith station (fh_crafting `isNearStation`), consumes gun_parts (+20 condition each, fewest
needed) up to the star cap (1/2/3 stars = 60/80/100; no stars = 1 star). Math: `FhCraftRules.restore` (fh_crafting).
Order: write condition, then consume parts; a failed consume rolls the write back. Removal is `fh_crafting` `invTake`
(B7 `removeItem`-backed); until that lands it refuses with `no_remove` (Workaround, replaced by C5).
Visual wear is data-only: `_SET_WEAPON_DEGRADATION` is unproven in fh_core/docs/natives.md. Condition shows in item info.
Reasons: no_station, bad_slot, no_weapon, no_condition, at_cap, no_parts, no_remove, write_failed.
