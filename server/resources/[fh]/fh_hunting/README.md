# fh_hunting: pelts and hunting (spec L8)

H1 (data and rules), H2 (skin flow), H3 (trapper sell point), H4 (legendary bear chain) and H5 (trophy comfort contract)
are built: animal table, pelt items, quality rules, price rules, skinning, selling, the three-clue legendary bear hunt and
the trophy comfort lookup. Pure logic lives in `shared/` and is specced with `python tools/run-specs.py`
(`spec/hunting_*_spec.lua`); nothing here is runtime-tested yet.

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
- `SellCooldownMs` (500): server, per-player per-event throttle for the sell menu and sale requests.
- `Trapper` (H3): `{ region_id = 'heartlands', label, coords, SellRange = 4.0, PromptDistance = 2.0 }`. Coordinates are approximate and unverified; `region_id` is the fh_economy ledger region.
- `LegendaryBear` (H4): `{ chain_id, model, rumourPrice, region_id, RumourRange, markers[2|3] { id, label, coords, radius }, spawn.coords }`. Clue 1 is the trapper; clues 2 and 3 are inspectable world markers; the spawn area is where the bear appears. Coordinates approximate and unverified.
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
- `FhHuntingChain`: the H4 legendary-bear state machine (below): `new({cfg, deps})` -> a chain object with
  `buyRumour`, `inspect`, `onAdopted`, `onSkinned`, `state`, `drop`, plus `normalise`, `markerFor`, `distance`,
  `message` and the `STEP_*` / event-name constants.

## Exports (server)

- `getAnimal(model|hash, legendary)`: the animal table entry or nil.
- `getPeltItem(model|hash, legendary)`: pelt item id or nil.
- `price(peltItem, stars)`: payout amount or `nil, err`.
- `getTrophyComfort(itemId)`: comfort number for a trophy item (`trophy_legendary_bear` = 25), nil for pelts, unknown ids and non-strings. Homestead places the trophy and reads this; Hunting fires no trophy events.

## Trapper (H3)

A sell point at `Config.Trapper.coords` (M1 region `heartlands`). The client shows `[E] Sell pelts` within
`PromptDistance`; E asks the server (`fh:hunting:sell_open`), which sends back the sellable pelts in the player's
saddlebag and a nearby wagon with the prices it computed, shown as an ox_lib context menu. Picking one sends
`fh:hunting:sell` `{ container = 'saddlebag'|'wagon', slot, item }`.

The server (`shared/sell.lua`, wired in `server/main.lua`) trusts none of it. It re-reads the player position (within
`SellRange` of the trapper), the container (saddlebag, or a wagon from `fh_cargo:nearestWagon`), the item at that slot
(must match the requested id, must be a pelt in the animal table; trophies are not bought) and the stars
(`info.stars` 1-3; legendary pelts are always 3). The payout is `price.price(base, stars, legendary)`, i.e.
base x `QualityMult[stars]` (1 star 0.4, 2 stars 1.0, 3 stars 1.8) x `LegendaryMult` 4 for legendary. Order: remove the
pelt, then `fh_economy:pay(src, amount, 'hunting:pelt', region_id)`. If the payout fails the pelt is put back with its
info. One sale per player at a time and a short request throttle, so a pelt cannot be paid twice.

Wagon lookup (`shared/wagon.lua`): `exports.fh_cargo:nearestWagon(src, coords, Config.WagonRange)` returns
`{ type = 'wagon', id = 'fh:wagon:<id>' }` or nil (roads-r1). nil, a thrown error or a missing `fh_cargo` all mean "no
wagon": big-game skins are refused and the carcass stays claimable. The adapter reports the player's position as the
wagon position because `fh_cargo` already applied the range.

## Legendary bear (H4)

One Legendary Bear hunt per character, a three-clue chain inside the Heartlands. The state machine is pure
(`shared/chain.lua`, `FhHuntingChain`); `server/main.lua` injects the DB, the rumour charge and `fh_core:requestSpawn`
sides. Chain state persists in `fh_hunting_chains` (one row per `(citizenid, chain_id)`), so a relog resumes where the
character left off.

1. **Clue 1 (rumour):** at the trapper, the client prompt becomes "[E] Ask about the legendary bear" while the
   character is at step 1. The server charges `LegendaryBear.rumourPrice` via `fh_economy:charge` (ledger row, B7) with reason `hunting:rumour` and advances to step 2. Refused if already bought, paid-for, complete, or out of
   range.
2. **Clue 2 (track):** a track marker appears; inspecting it (in range, current step only) advances to step 3.
3. **Clue 3 (carcass):** a carcass marker appears; inspecting it requests the bear through
   `fh_core:requestSpawn` (server decides, a client creates, the server adopts). `spawn_request` is persisted once, so
   the bear is spawned exactly once per chain. If the spawn exhausts its retries, `onSpawnFailed` resets the chain to
   the carcass clue so the player can try again.
4. **Spawn:** on adoption the entity is marked as that character's legendary (so the H2 skin flow reads it as legendary
   and owner-scoped) and `fh:hunting:legendary_spawned` fires once.
5. **Kill and skin:** only the character whose chain spawned the bear may skin it (`fh_not_your_legendary` otherwise).
   The skin flow grants `pelt_legendary_bear` (cargo, always 3 stars, wagon path) and the bulky
   `trophy_legendary_bear`, then `fh:hunting:chain_complete` fires once and the request is despawned (no post-skin
   re-spawn).

Server-side validation for every step: the player must be in range of the right marker for the current step only; wrong
marker, skipped steps and repeated steps are refused (`fh_chain_wrong_marker`, `fh_chain_spawned`, ...). The rumour is
charged exactly once (a busy guard covers the charge yield). The trophy grant is best-effort: the pelt is the primary
grant, so a full saddlebag never fails or double-pays the skin.

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

- `fh:hunting:sell_open` (no payload) and `fh:hunting:sell` `{ container, slot, item }` (H3, see Trapper). Server replies with `fh:hunting:sell_rows` (client event, display only).

- `fh:hunting:chain_status` (no payload) — the client asks for the current legendary-chain step; the server replies with `fh:hunting:chain_state` `{ step, spawned, completed }` (client event, display only).
- `fh:hunting:chain_rumour` (no payload) — buy the rumour from the trapper (clue 1).
- `fh:hunting:chain_inspect` `{ marker = 'track'|'carcass' }` — inspect a marker (clues 2 and 3). The server re-reads the player position and the marker for the current step.

Consumed (engine): `onResourceStart` (own resource and `fh_core`, to register the items), `playerDropped`.

Emitted (server-only, for @quests and @guide; never sent to clients):

- `fh:hunting:pelt_skinned` `{ src, citizenid, item_id, animal, quality, size_class }`: now, after a grant only.
  Never fired on a refusal.
- `fh:hunting:pelt_sold` `{ citizenid, item_id, animal, size_class, quality, price, region_id }`: H3, after a payout succeeded only. `price` is what `fh_economy:pay` was given.
- `fh:hunting:clue_found` `{ citizenid, chain_id = 'legendary_bear', step = 1|2|3 }`: H4, each clue of the legendary
  bear chain, when it is found (rumour bought, track inspected, carcass inspected).
- `fh:hunting:legendary_spawned` `{ citizenid, chain_id }`: H4, when the bear's spawn is adopted. Fires once per chain.
- `fh:hunting:chain_complete` `{ citizenid, chain_id }`: H4, after the legendary pelt is skinned. Fires once per chain.

No trophy events, ever: @homestead owns trophy placement and reads `exports.fh_hunting:getTrophyComfort(itemId)`
(number, or nil for a non-trophy), see Exports.

Consumes from other resources: `fh_core:registerItems`, `fh_core:saddlebagOf`, `fh_core:addItem` and the container
rules; `ox_lib` (notify, progress bar) and `rsg-target` on the client; `fh_economy:pay`, `fh_core:snapshot` and `fh_core:removeItem` (H3), `fh_economy:charge` (H4 rumour); `fh_core:requestSpawn` / `fh_core:despawn` (H4), `fh_core:requestOfNetId` + `fh_core:despawn` (H7, after a successful skin); `fh_cargo:nearestWagon` (roads-r1, not on main yet).

## Known gaps

- Bulky pelts go to the saddlebag, not the backpack (fh_core container rule, `fh_core/shared/containers.lua:12`; the
  backpack holds pocket items only). It works without a horse nearby, a simplification.
- Adopted carcasses respawn after deletion: fh_core re-requests an adopted entity that disappears
  (`fh_core/server/spawn.lua:237-239`). Requested from @core (a netId to spawn-request lookup or a "release on death"
  option).
- `findCargoWagon` (`server/main.lua`) now calls `exports.fh_cargo:nearestWagon`; until `fh_cargo` (roads-r1) is on main
  every cargo pelt is refused (fail closed).
- `fh_core:removeItem` (B7) removes by name with no slot. `removeItem` in `server/main.lua` snapshots the container before and after to find the slot that really lost the pelt; the sale is priced from that pelt, so mixed-star stacks pay correctly. Since core-03 the export also accepts carried refs (`{ type = 'backpack'|'equipped', id = src }`; an offline src gives `fh_player_offline`, and bulky items are still vetoed from the backpack), but the trapper uses only the saddlebag and wagon because pelts never sit in the backpack. If fh_cargo has not registered the wagon stash with fh_core the removal fails closed (`fh_remove_failed`).
- Pelts in the backpack are not sold (bulky and cargo pelts cannot be there); only the saddlebag and a nearby wagon.
- Legendary trophy is best-effort: if the saddlebag and the wagon are both full, the pelt is still granted and the chain
  completes, but the trophy is not stowed (the skin notification says so).
- A legendary bear killed but never skinned, whose carcass is later cleaned up, is re-requested by fh_core (the general
  "adopted carcass respawns" gap above); the chain still counts one spawn, and the post-skin `despawn` prevents the
  common "skin it and another bear appears" case. `legendaryEntities` is cleared on `finishCarcass` and per spawn.

## In-game test card

H2 card (also in `OWNER-TESTS.md`, section `## Hunting`). All unverified in-game.

1. Spawn a test deer: `fh_spawn_ped a_c_deer_01` (note the id it prints). Kill it with a head shot, stand within 5 m, use the rsg-target "Skin" option. Expected: progress bar, then a `pelt_deer` with 3 stars in your saddlebag; the carcass is deleted.
2. Spawn another deer, shoot it in the gut (belly). Skin it. Expected: a `pelt_deer` with 1 star.
3. Kill a bear (no wagon nearby) and try to skin it. Expected: refused with a notification (no wagon), no pelt, the carcass is still there and stays skinnable. Bring a wagon within 8 m and skin again: the pelt goes into the wagon.
4. Spam the Skin option twice on one carcass. Expected: exactly one pelt, the second request is refused or ignored.
5. Sell: stand at the trapper with a 1 star and a 3 star `pelt_deer` in your saddlebag, press E, pick one, then the other. Expected: $6 for the 1 star and $25 for the 3 star, two `hunting:pelt` ledger rows, the pelts gone. Selling from out of range is refused.
6. After skinning a test deer, run `fh_despawn <id>` from step 1: fh_core re-requests an adopted carcass that disappears, so the deer respawns otherwise (see Known gaps).

