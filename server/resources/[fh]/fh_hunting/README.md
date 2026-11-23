# fh_hunting: pelts and hunting (spec L8)

H1 (data and rules) and H2 (skin flow) are built: animal table, pelt items, quality rules, price rules. The trapper sell
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

H2 keys:

- `GrantOrder`: where a pelt goes, tried in order and filtered by the fh_core size-class rules. Default `bulky = { 'saddlebag', 'wagon' }`, `cargo = { 'wagon' }`.
- `SkinDurationMs` (4000): client progress bar before the request is sent.
- `SkinCooldownMs` (1000): server, one skin request per player per this many ms; extra ones are ignored.
- `SkinPromptDistance` (2.5): rsg-target reach; the server re-checks `SkinRange`.
- `DeleteCarcass` (true): delete the carcass after a grant (it is marked skinned either way).
- `ClaimPruneMs` (30000): server, forget skinned-claim entries whose carcass no longer exists.
- `TrackRadius` (150.0), `TrackIntervalMs` (250): client tracking of live animals (last damage bone, weapon hits).
- `DeadCacheSeconds` (900): keep a dead animal's shot data this long, by netId.
- `ExplosiveWeapons`: cause-of-death weapons that count as explosive (1 star). Unverified names.
- `NativeQualityStars`, `NativeCleanlinessStars`: result maps for the `'native'` source.

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

## Skin approach

Skinning is our own rsg-target "Skin" prompt on a dead, networked animal; we do not intercept the game's built-in
skinning. Evidence (from the H2 research):

- No resource in `[rsg]` or `[fh]` reads the game's loot events (no `GetNumberOfEvents` / `GetEventAtIndex` hits).
- The vanilla pelt never goes into rsg-inventory.
- Vanilla skinning usually removes the carcass before the server could claim it (`[spikes]/spk_pelt/client.lua:75`).

Risk: players can still use the built-in skin action. It yields no `fh_hunting` pelt (and may delete the carcass).

Flow: the client sends one request after the progress bar; the server re-reads the carcass, claims it (test-and-set),
grants the pelt, then marks it skinned (`fhSkinned` state bag) and deletes it. A refusal or failure releases the claim so
the carcass stays skinnable.

## Events

Consumed (requests, client to server):

- `fh:hunting:skin` `{ netId, bone?, hits?, explosive?, nativeQuality?, cleanliness? }`. Only `netId` is required;
  `bone` is a name or number, the rest are quality hints. The server trusts none of it beyond those hints: it re-reads
  the carcass, state and distances, and rate-limits to one request per player per `SkinCooldownMs`.

Consumed (engine): `onResourceStart` (own resource and `fh_core`, to register the items), `playerDropped`.

Emitted (server-only, for @quests and @guide; never sent to clients):

- `fh:hunting:pelt_skinned` `{ src, citizenid, item_id, animal, quality, size_class }`: now, after a grant only.
  Never fired on a refusal.
- Planned, H3: `fh:hunting:pelt_sold` `{ citizenid, item_id, animal, size_class, quality, price, region_id }`.
- Planned, H4: `fh:hunting:clue_found` `{ citizenid, chain_id, step }`, `fh:hunting:legendary_spawned`
  `{ citizenid, chain_id }`, `fh:hunting:chain_complete` `{ citizenid, chain_id }`.

No trophy events, ever: @homestead owns trophy placement and reads `exports.fh_hunting:getTrophyComfort(itemId)`
(number, or nil for a non-trophy), added in H5.

Consumes from other resources: `fh_core:registerItems`, `fh_core:saddlebagOf`, `fh_core:addItem` and the container
rules; `ox_lib` (notify, progress bar) and `rsg-target` on the client; `fh_economy:pay` from H3 on.

## Known gaps

- Bulky pelts go to the saddlebag, not the backpack (fh_core container rule, `fh_core/shared/containers.lua:12`; the
  backpack holds pocket items only). It works without a horse nearby, a simplification.
- Adopted carcasses respawn after deletion: fh_core re-requests an adopted entity that disappears
  (`fh_core/server/spawn.lua:237-239`). Requested from @core (a netId to spawn-request lookup or a "release on death"
  option).
- `findCargoWagon` (`server/main.lua`) is a stub returning nil, so cargo pelts (bear, bison, ...) are refused until
  @core/@roads ship a wagon lookup.

## In-game test card

H2 card (also in `OWNER-TESTS.md`, section `## Hunting`). All unverified in-game.

1. Spawn a test deer: `fh_spawn_ped a_c_deer_01` (note the id it prints). Kill it with a head shot, stand within 5 m, use the rsg-target "Skin" option. Expected: progress bar, then a `pelt_deer` with 3 stars in your saddlebag; the carcass is deleted.
2. Spawn another deer, shoot it in the gut (belly). Skin it. Expected: a `pelt_deer` with 1 star.
3. Kill a bear (no wagon nearby) and try to skin it. Expected: refused with a notification (no wagon), no pelt, the carcass is still there and stays skinnable. Bring a wagon within 8 m and skin again: the pelt goes into the wagon.
4. Spam the Skin option twice on one carcass. Expected: exactly one pelt, the second request is refused or ignored.
5. After skinning a test deer, run `fh_despawn <id>` from step 1: fh_core re-requests an adopted carcass that disappears, so the deer respawns otherwise (see Known gaps).

