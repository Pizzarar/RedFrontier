# fh_hunting: pelts and hunting (spec L8)

H1 (data and rules) is built: animal table, pelt items, quality rules, price rules. The skin flow (H2), trapper sell
point (H3), Legendary Bear (H4) and trophy comfort contract (H5) come in later blocks. Pure logic lives in `shared/`
and is specced with `python tools/run-specs.py` (`spec/hunting_*_spec.lua`); nothing here is runtime-tested yet.

## Config flag

`FhHuntingConfig.PeltQualitySource` in `config.lua`:

- `'roll'` (default): the server maps the last damage bone to a zone (head/vital 3 stars, body 2 stars,
  limb/gut/explosive/multi-hit 1 star). Head and vital are always 3 stars; only the body zone rolls, with a 10% chance
  of dropping one star (`Zones.body.downgradeChance`). Needs no native result.
- `'native'`: read `_GET_PED_QUALITY` / `_GET_PED_DAMAGE_CLEANLINESS` instead (waits on the S4 `spk_pelt` verdict).

Both feed the same `FhHuntingQuality.resolve()`. Other config: `QualityMult` (1 star 0.4, 2 stars 1.0, 3 stars 1.8),
`LegendaryMult` 4, `SkinRange` 5 m, `WagonRange` 8 m, `Zones`, `BoneZones`, `MultiHitMin`.

## Items

One pelt per animal, stars in the item's `info.stars` (the §4.1 quality field), never in the id. Registered at start
through `fh_core:registerItems` (again whenever `fh_core` restarts).

| Size class | Items |
|---|---|
| bulky (saddlebag OK) | `pelt_rabbit`, `pelt_fox`, `pelt_coyote`, `pelt_deer`, `pelt_boar`, `pelt_wolf`, `trophy_legendary_bear` |
| cargo (wagon or chest only) | `pelt_bear`, `pelt_bison`, `pelt_elk`, `pelt_moose`, `pelt_alligator`, `pelt_legendary_bear` (always 3 stars) |

Images reuse rsg-inventory pelt images (`resource_pelt_*`, `good_pelt`, `perfect_pelt`, `legendary_bear_pelt`).

## Pure modules (shared)

- `FhHuntingAnimals`: `list`, `get(model|hash|key, legendary)`, `sizeClass`, `itemDefs()`, `joaat`.
- `FhHuntingQuality`: `resolve(input, cfg)` returns `ok, stars, detail`; `plausibility(check, cfg)` returns `ok, reason`
  (`fh_already_claimed`, `fh_not_dead`, `fh_too_far`).
- `FhHuntingPrice`: `price(itemBase, stars, isLegendary, cfg)`; the amount for `fh_economy.pay`.

## Exports (server)

- `getAnimal(model|hash, legendary)`: the animal table entry or nil.
- `getPeltItem(model|hash, legendary)`: pelt item id or nil.
- `price(peltItem, stars)`: payout amount or `nil, err`.

## Events

Emitted: none yet. No trophy events, ever: @homestead owns trophy placement and reads
`exports.fh_hunting:getTrophyComfort(itemId)` (number, or nil for a non-trophy), added in H5.

Consumed: `onResourceStart` (own resource and `fh_core`, to register the items).

Consumes from other resources: `fh_core:registerItems`; `fh_economy:pay` from H3 on.

## In-game test card

(Filled in by later blocks; the lane's in-game checks go in `OWNER-TESTS.md`, section `## Hunting`.)
