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

H2 / H8 keys:

- `GrantOrder`: where skinned items go, tried in order and filtered by the fh_core size-class rules. Default `pocket = { 'backpack', 'saddlebag', 'wagon' }`, `bulky = { 'saddlebag', 'wagon' }`, `cargo = { 'wagon' }`.
- `MeatItem` (`'raw_meat'`), `MeatSizeClass` (`'pocket'`), `MeatPerSize` (`{ pocket = 1, bulky = 2, cargo = 3 }`): H8 raw meat grant alongside every skinned pelt, keyed by the animal's `size_class` (rsg-core item `raw_meat`, `rsg-core/shared/items.lua:151`).
- `SkinDurationMs` (4000): client progress bar before the request is sent.
- `SkinCooldownMs` (1000): server, one skin request per player per this many ms; extra ones are ignored.
- `SkinPromptDistance` (2.5): rsg-target reach; the server re-checks `SkinRange`.
- `DeleteCarcass` (true): delete the carcass after a grant (it is marked skinned either way).
- `ClaimPruneMs` (30000): server, forget skinned-claim entries whose carcass no longer exists.
- `TrackRadius` (150.0), `TrackIntervalMs` (250): client tracking of live animals (last damage bone, weapon hits).
- `DeadCacheSeconds` (900): keep a dead animal's shot data this long, by netId.
- `SellCooldownMs` (500): server, per-player per-event throttle for the sell menu and sale requests.
- `Trapper` (H3): `{ region_id = 'heartlands', label, coords, SellRange = 4.0, PromptDistance = 2.0 }`. Coordinates are approximate and unverified; `region_id` is the fh_economy ledger region.
- `LegendaryBear`: removed. The bear moved to `data/legendaries/heartlands.lua` unchanged (see Legendaries). `Trapper.coords` is still the heartlands rumour point.
- `ExplosiveWeapons`: cause-of-death weapons that count as explosive (1 star). Unverified names.
- `NativeQualityStars`, `NativeCleanlinessStars`: result maps for the `'native'` source.

## Items

One pelt per animal, stars in the item's `info.stars` (the §4.1 quality field), never in the id. Registered at start
through `fh_core:registerItems` (again whenever `fh_core` restarts).

| Size class | Items |
|---|---|
| bulky (saddlebag OK) | `pelt_rabbit`, `pelt_fox`, `pelt_coyote`, `pelt_deer`, `pelt_boar`, `pelt_wolf`, `trophy_<id>` (e.g. `legendary_bear` -> `trophy_legendary_bear`; one per region in [Legendaries](#legendaries-hunting-02) / `data/legendaries/*.lua`) |
| cargo (wagon or chest only) | `pelt_bear`, `pelt_bison`, `pelt_elk`, `pelt_moose`, `pelt_alligator`, `pelt_<id>` (always 3 stars; e.g. `legendary_bear` -> `pelt_legendary_bear`; one per region in [Legendaries](#legendaries-hunting-02) / `data/legendaries/*.lua`) |

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
- `getTrophyComfort(itemId)`: comfort number for any legendary trophy item (`trophy_<id>`, e.g. `legendary_bear` -> `trophy_legendary_bear`, 25 from `data/legendaries/*.lua`; see [Legendaries](#legendaries-hunting-02)), nil for pelts, unknown ids and non-strings. Homestead places the trophy and reads this; Hunting fires no trophy events.

## Trapper (H3)

A sell point at `Config.Trapper.coords` (M1 region `heartlands`). The client shows `[E] Sell pelts` within
`PromptDistance`; E asks the server (`fh:hunting:sell_open`), which opens the fh_ui `trapper` screen (`fh:ui:open`) with
the sellable pelts in the player's saddlebag and a nearby wagon and the prices it computed. Picking one relays
`fh:hunting:ui_sell` `{ src, screen = 'trapper', action = 'sell', payload = { container = 'saddlebag'|'wagon', slot, item } }`
through `fh_ui`, and the server replies with `fh:ui:update` (fresh rows + inline notice).

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

## Legendaries (hunting-02)

One legendary per region, each a pure-data file `data/legendaries/<region_id>.lua` that returns one entry (or nothing for a stub). The schema, its validation and the loader rules live in the header of `shared/legendaries.lua`; add a region's hunt by filling its file, no code change. Pelt values follow `round(plain species value * 4/3)` (the bear's 45 -> 60); the owner tunes them after the playtest.

| region | enabled | id | label | species | pelt value |
|---|---|---|---|---|---|
| heartlands | yes | `legendary_bear` | Legendary Bear | `a_c_bear_01` | 60 |
| scarlett_meadows | yes | `legendary_redclay_stag` | Legendary Red Clay Stag | `a_c_deer_01` | 19 |
| bayou_nwa | yes | `legendary_mossback_gator` | Legendary Mossback Gator | `a_c_alligator_01` | 73 |
| great_plains | yes | `legendary_dusthorn_bison` | Legendary Dusthorn Bison | `a_c_buffalo_01` | 53 |
| big_valley | no | `legendary_copperhide_deer` | Legendary Copperhide Deer | `a_c_deer_01` | 19 |
| bluewater_marsh | no | `legendary_brackhide_boar` | Legendary Brackhide Boar | `a_c_boar_01` | 16 |
| cholla_springs | no | `legendary_cinderjaw_coyote` | Legendary Cinderjaw Coyote | `a_c_coyote_01` | 11 |
| cumberland_forest | no | `legendary_greyhowl_wolf` | Legendary Greyhowl Wolf | `a_c_wolf` | 27 |
| gaptooth_ridge | no | `legendary_sandveil_fox` | Legendary Sandveil Fox | `a_c_fox_01` | 11 |
| grizzlies_east | no | `legendary_frostmane_moose` | Legendary Frostmane Moose | `a_c_moose_01` | 67 |
| grizzlies_west | no | `legendary_palehorn_elk` | Legendary Palehorn Elk | `a_c_elk_01` | 51 |
| hennigans_stead | no | `legendary_saltbrush_buck` | Legendary Saltbrush Buck | `a_c_deer_01` | 19 |
| rio_bravo | no | `legendary_canyonback_boar` | Legendary Canyonback Boar | `a_c_boar_01` | 16 |
| roanoke_ridge | no | `legendary_coalhorn_moose` | Legendary Coalhorn Moose | `a_c_moose_01` | 67 |
| tall_trees | no | `legendary_embercoat_coyote` | Legendary Embercoat Coyote | `a_c_coyote_01` | 11 |

All coordinates are unverified in game (`TODO-verify-in-game` in each file). A region's `enabled` flag comes from `fh_core` regions (`FhRegions.isEnabled`), read live.

**Gate.** While a legendary's region is disabled, the rumour, both markers and the spawn refuse with `fh_chain_region_closed` ("There is no legendary hunt here."), and the client draws no prompt or marker there. A chain in progress freezes: its state is kept as it is (not reset) and resumes when the region is enabled again. Each character has one chain per legendary, so two hunts in two regions can run at once.

## Regional trappers (hunting-03 C1)

Each `data/legendaries/<region>.lua` carries a `trapper = { label, coords }` field; the trapper sells pelts and hosts that region's rumour. Heartlands falls back to `Config.Trapper` (same coords). The list is built by `shared/sell.lua` (`M.trappers`).

| region | enabled | trapper label | coords (x, y, z) |
|---|---|---|---|
| heartlands | yes | Trapper | -299, 792, 118.2 |
| scarlett_meadows | yes | Scarlett Meadows Trapper | 1265, -1305, 77 TODO-verify-in-game |
| bayou_nwa | yes | Bayou Nwa Trapper | 2175, -1120, 25 TODO-verify-in-game |
| great_plains | yes | Great Plains Trapper | -865, -1335, 44 TODO-verify-in-game |
| big_valley | no | Big Valley Trapper | -1814, -440, 120 TODO-verify-in-game |
| bluewater_marsh | no | Bluewater Marsh Trapper | 2300, -600, 20 TODO-verify-in-game |
| cholla_springs | no | Cholla Springs Trapper | -3703, -2573, 70 TODO-verify-in-game |
| cumberland_forest | no | Cumberland Forest Trapper | -810, 1340, 130 TODO-verify-in-game |
| gaptooth_ridge | no | Gaptooth Ridge Trapper | -5514, -2928, 90 TODO-verify-in-game |
| grizzlies_east | no | Grizzlies East Trapper | 1675, 1900, 200 TODO-verify-in-game |
| grizzlies_west | no | Grizzlies West Trapper | -1300, 1600, 240 TODO-verify-in-game |
| hennigans_stead | no | Hennigans Stead Trapper | -2275, -2485, 60 TODO-verify-in-game |
| rio_bravo | no | Rio Bravo Trapper | -2000, -3000, 55 TODO-verify-in-game |
| roanoke_ridge | no | Roanoke Ridge Trapper | 2975, 600, 38 TODO-verify-in-game |
| tall_trees | no | Tall Trees Trapper | -1795, -1600, 150 TODO-verify-in-game |

A trapper shows (prompt, blip) and buys only while its region is enabled (`FhRegions.isEnabled`, read live). A sale within range of a trapper in a closed region refuses `fh_region_closed` ("The trapper here is not buying yet."); out of range of every trapper refuses `fh_too_far`. A sale pays and records `pelt_sold.region_id` (and the `fh_economy:pay` ledger region) for the trapper you stand at, not always heartlands.

## Legendary coats (hunting-03 C2)

Completing a legendary chain grants two `fh_tailor` wardrobe entries: `coat_<legendary_id>_male` and `coat_<legendary_id>_female` (e.g. `coat_legendary_bear_male`), via `exports.fh_tailor:grant(citizenid, id, source)`. The source tag is `hunting:<legendary id minus legendary_>`, e.g. `hunting:bear` (the longer `hunting:legendary:<id>` form exceeded fh_tailor's 32-char source cap). The grant fires on the completion transition only (`shared/coats.lua`, wired in `server/main.lua`).

- `wrong_sex` (the entry for the other sex) is expected from one of the two calls and is ignored.
- Any other refusal (`unknown_entry`, `invalid_source`, ...) is logged once per (coat id, code) and never breaks completion. `unknown_entry` is expected until @progression adds the catalog ids.
- Login backfill: one query for the character's completed chains, then a grant per legendary (idempotent, so no duplicates on relog).
- `fh_tailor` missing or stopped is a silent no-op.

## Legendary bear (H4)

One Legendary Bear hunt per character, a three-clue chain inside the Heartlands (the same chain runs for every legendary in the table above; the steps below use the bear as the example). The state machine is pure
(`shared/chain.lua`, `FhHuntingChain`); `server/main.lua` injects the DB, the rumour charge and `fh_core:requestSpawn`
sides. Chain state persists in `fh_hunting_chains` (one row per `(citizenid, chain_id)`), so a relog resumes where the
character left off.

1. **Clue 1 (rumour):** at the trapper, the client prompt becomes "[E] Ask about the legendary bear" while the
   character is at step 1. The server charges the entry's `rumour.price` via `fh_economy:charge` (ledger row, B7) with reason `hunting:rumour` and advances to step 2. Refused if already bought, paid-for, complete, or out of
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
grants the pelt, then grants `raw_meat` (H8: amount from `MeatPerSize[animal.size_class]`, pocket `GrantOrder` backpack -> saddlebag -> wagon; best-effort so if no container has room the pelt grant still stands and the notification notes that raw meat could not be stowed), then marks it skinned (`fhSkinned` state bag) and deletes it. A refusal or failure on the pelt releases the claim so
the carcass stays skinnable.

## Events

Consumed (requests, client to server):

- `fh:hunting:skin` `{ netId, bone?, hits?, explosive?, nativeQuality?, cleanliness? }`. Only `netId` is required;
  `bone` is a name or number, the rest are quality hints. The server trusts none of it beyond those hints: it re-reads
  the carcass, state and distances, and rate-limits to one request per player per `SkinCooldownMs`.

- `fh:hunting:sell_open` (no payload) (H3, see Trapper). Server replies with `fh:ui:open` for the `trapper` screen; sell actions arrive as server-local `fh:hunting:ui_sell` relayed by `fh_ui` and reply with `fh:ui:update`.

- `fh:hunting:chain_status` (no payload) — the client asks for the current legendary-chain step; the server replies with `fh:hunting:chain_state` `{ step, spawned, completed, chains = { [legendary id] = { step, spawned, completed } } }` (client event, display only; the top-level fields are the bear's, `chains` covers every legendary in an enabled region).
- `fh:hunting:chain_rumour` `{ legendary? }` — buy the rumour (clue 1). `legendary` is the legendary id; omitted means `legendary_bear`.
- `fh:hunting:chain_inspect` `{ marker = 'track'|'carcass', legendary? }` — (`legendary` omitted means `legendary_bear`) inspect a marker (clues 2 and 3). The server re-reads the player position and the marker for the current step.

Consumed (engine): `onResourceStart` (own resource and `fh_core`, to register the items), `playerDropped`.

Emitted (server-only, for @quests and @guide; never sent to clients):

- `fh:hunting:pelt_skinned` `{ src, citizenid, item_id, animal, quality, size_class, meat }`: now, after a grant only (`meat` is the count of `raw_meat` stowed, `0` if skipped for no room).
  Never fired on a refusal.
- `fh:hunting:pelt_sold` `{ citizenid, item_id, animal, size_class, quality, price, region_id }`: H3, after a payout succeeded only. `price` is what `fh_economy:pay` was given.
- `fh:hunting:clue_found` `{ citizenid, chain_id, region_id, legendary, step = 1|2|3 }`: H4, each clue of a legendary
  chain (`chain_id` = `legendary` = the legendary id, `region_id` its region), when it is found (rumour bought, track inspected, carcass inspected).
- `fh:hunting:legendary_spawned` `{ citizenid, chain_id, region_id, legendary }`: H4, when the legendary's spawn is adopted (for any entry in [Legendaries](#legendaries-hunting-02) / `data/legendaries/*.lua`). Fires once per chain.
- `fh:hunting:chain_complete` `{ citizenid, chain_id, region_id, legendary }`: H4, after the legendary pelt is skinned. Fires once per chain.

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

