# fh_tailor

Fitted outfits as progression (progression-03). You start in a basic set, buy whole outfits (plus a few safe single
items) at tailors and general stores, and earn some only through other systems (@hunting legendary coats, @quests
rewards). rsg-character keeps face and body only; fh_tailor never edits it.

Implemented catalog-style tailor/general-store clothing progression — Thanks to Red Dead Redemption 2 (single-player
tailors and catalogs) by Rockstar Games (design idea only; no assets or text copied).

## Status

- T1: pure logic + server. Catalog, per-shop stock, ownership, buy, grant, starter set, equip, saved outfits.
- T2 (this): client apply behind `Config.FittedOutfits`, tailor stops per town, and stopgap `ox_lib` shop + wardrobe
  menus (replaced by the @ui catalog screen in T4).
- `Config.FittedOutfits = false` until the @spikes S1 probe passes. Off: everything above works and persists; the
  client applies nothing to the ped, so `rsg-character` stays unchanged.
- Config ships tailor stops per town and one placeholder starter outfit per sex. Real catalog content is T3.

## Data

Migration `server/migrations/0020_fh_tailor.sql` (the server also runs the same idempotent DDL at start):

| Table | Holds |
|---|---|
| `fh_tailor_owned` | one row per owned catalog id (PK citizenid + entry_id); `source` = `buy`, `starter` or the grant tag |
| `fh_tailor_state` | `starter_at` (starter set granted once), worn look (`worn_outfit` + comma-joined `worn_items`) |
| `fh_tailor_outfits` | saved outfits, slots 1..`maxSavedOutfits`: outfit id + up to `maxItems` single item ids |

Ownership is a list of catalog ids, not inventory items: clothes take no bag weight.

## Catalog and stock

Entry: `{ id, label, sex = male|female|any, kind = outfit|item, preset (outfit) | component (item), price, min_tier,
shops = {...} | size = n, earned_only }`. Shop: `{ id, label, region_id, size, coords, radius }`.

An entry is for sale at a shop when it is not `earned_only`, the shop is in its `shops` list (or `shop.size >= size`,
default 1), it fits the character's sex and `exports.fh_progression:getTier(src, shop.region_id) >= min_tier`.

## Server exports

All return `ok, result`: on failure `false, code` (see Codes). Every refusal of a buy means nothing was taken.

| Export | Returns on success |
|---|---|
| `buy(src, shopId, entryId)` | `true, { entry_id, price, unverified? }` |
| `grant(citizenid, entryId, source)` | `true, 'granted'` or `true, 'already_owned'` (idempotent, works offline) |
| `equip(src, outfitId, itemIds?)` | `true, { outfit, items, fitted }` (saves the worn look) |
| `saveOutfit(src, slot, label?, outfitId, itemIds?)` | `true` |
| `wearSaved(src, slot)` | `true, { outfit, items, fitted }` |
| `getStock(src, shopId)` | `true, { shop = { id, label, region_id, size }, tier, rows = { { id, label, kind, sex, price, min_tier, owned } } }` |
| `getWardrobe(src)` | `true, { owned = { { id, label, kind, source } }, worn, saved = { [slot] = { label, outfit, items, valid } }, fitted, maxItems, maxSaved }` |
| `message(code)` | player-facing text for any code below (unknown: `Refused: <code>`) |

`grant` is for rewards from other systems (@hunting, @quests). It accepts **any catalog id**, not only `earned_only`
ones, so a quest can also reward an outfit that shops sell (lead decision, progression-03 T1). `source` is a short tag,
`[%w_:.-]`, at most 32 chars, e.g. `hunting:legendary_bear`; internal sources `buy` and `starter` are refused
(`invalid_source`). The entry must fit the character's sex (pass the sex
variant), else `wrong_sex`. A granted row is never removed by a refused buy (a refusal only deletes its own `buy` row).

**`charge_unavailable` keeps the outfit** (lead decision, same rule as fh_hands: never charge twice). When the
fh_economy export throws, it is unknown whether money moved. The buy returns `true, { ..., unverified = true }`, the
ownership row stays, and the server logs an `ALERT` line with citizenid, entry, price and shop; the fh_ledger charge
row tells an admin whether it was paid. At worst the clothes were free; the player is never charged a second time.

### Player-action exports (use these for any player-driven call)

The raw exports above (`buy`, `equip`, `saveOutfit`, `wearSaved`, `getStock`, `getWardrobe`) are **trusted server-side
calls: no range check, no debounce** (rewards, admin tools, tests). A resource relaying a player's action (e.g. the
@ui catalog screen) must call the `act*` wrappers, which apply exactly the guards the net events apply. Same
`ok, res | false, code` shapes as the core call they wrap.

| Export | Guards, then calls |
|---|---|
| `actBuy(src, shopId, entryId)` | `buy` (range, lock and charge rules live in the core) |
| `actStock(src, shopId)` | `unknown_shop`, `out_of_range`, then `getStock` |
| `actWardrobe(src)` | `not_at_wardrobe`, then `getWardrobe` |
| `actEquip(src, outfitId, items?)` | `not_at_wardrobe`, `too_fast`, then `equip` |
| `actSave(src, slot, label?, outfitId, items?)` | `not_at_wardrobe`, `too_fast`, then `saveOutfit` |
| `actWear(src, slot)` | `not_at_wardrobe`, `too_fast`, then `wearSaved` |

`too_fast`: equip / save / wear share one cooldown per player (`Config.actionDebounceMs`, default 750 ms, 0 = off). A
refused call does not extend the window; a call refused for range does not start it. The net events
(`fh:tailor:buy` / `equip` / `save_outfit` / `wear_saved`) and the `fh:tailor:stock` / `fh:tailor:wardrobe` callbacks
go through the same functions.

## Client exports (preview)

For @ui's mirror screen. Local and cosmetic: nothing is saved or sent to the server.

- `exports.fh_tailor:previewLook(look) -> boolean`: `look = { outfit = id, items = { id, ... } }`, applied with the same
  code path as the saved look (validated against the catalog; unknown ids or wrong kinds return `false`). It works even
  when `Config.FittedOutfits` is `false`: the flag gates applying the *saved* look to the ped, a preview is transient and
  the UI needs it to show stock before S1 clears. Caveat: with the flag off the preset's compatibility with the
  rsg-character face/body is unverified (S1), so always call `revertLook` when the screen closes.
- `exports.fh_tailor:revertLook() -> boolean`: flag on: re-applies the saved (worn) look. Flag off: if something was
  previewed, restores the ped by reloading the character's saved skin through `exports['rsg-character']:ApplySkin()`
  (brief model swap); if nothing was previewed it does nothing and returns `false`.

## Client apply and stopgap menus (T2)

- **Client apply (`client/main.lua`)**: listens to `rsg-character:client:ApplySkin`, `RSGCore:Client:OnPlayerLoaded`,
  `playerSpawned` and `fh:tailor:apply`. When `Config.FittedOutfits = true`, re-applies the character's saved outfit
  preset via `SetPedOutfitPreset` and layers any worn single-item components (`ApplyShopItemToPed` +
  `UpdatePedVariation`), overriding `rsg-character` clothes without editing `rsg-character`. When `Config.FittedOutfits`
  is `false`, the client applies nothing.
- **Tailor stops (`config.lua`)**: per-town stops (`valentine_general`, `emerald_ranch_general`, `rhodes_general`,
  `lagras_general`, `saint_denis_tailor`, `blackwater_tailor`, plus disabled-region towns). Client prompts are gated on
  `FhRegions.isEnabled(shop.region_id)`. Press `[E]` at a tailor stop to open the stopgap `ox_lib` menu (Browse Catalog
  / Open Wardrobe).
- **Homestead wardrobe**: references `fh_homestead` read-only (`fh:homestead:plots` callback on the client,
  `getPlot` + `plotInfo` exports on the server; `fh_homestead` is never edited). Press `[G]` near a homestead chest to
  open the Wardrobe menu, shown only at a chest of one of your own plots (`fh:tailor:own_plots` callback; the plots fetch retries until `fh_homestead` is up; uses `[G]` so `fh_homestead`'s `[E]` chest prompt is untouched).
- **Client-server contract** (server validates everything; client sends only ids):
  - Callbacks: `fh:tailor:worn` (player's worn look when `FittedOutfits` is on), `fh:tailor:stock` (`shopId`, range
    checked), `fh:tailor:wardrobe` (tailor or own homestead range checked).
  - Net events (client -> server): `fh:tailor:buy` `{ shop_id, entry_id }`, `fh:tailor:equip` `{ outfit_id, items }`,
    `fh:tailor:save_outfit` `{ slot, label, outfit_id, items }`, `fh:tailor:wear_saved` `{ slot }`.
  - Net events (server -> client): `fh:tailor:result` `{ action, ok, code?, ... }` (client shows `message(code)` on
    errors), `fh:tailor:apply` `{ outfit, items }`.

## Bus events (server, `TriggerEvent`)

- `fh:tailor:owned` `{ src (nil when offline), citizenid, entry_id, source, price? , shop_id?, region_id? }`: after a
  buy or a new grant (not for `already_owned`, not for the starter set).
- `fh:tailor:equipped` `{ src, citizenid, outfit_id, items, fitted }`: after `equip` / `wearSaved` saved a look.

## Codes

- Charge (core B7, from `exports.fh_economy:charge`): `fh_insufficient_funds`, `fh_charge_busy` (retried up to
  `chargeRetries` times inside the buy first), `ledger_failed`, `removemoney_refused`, `no_player`, `player_changed`,
  `invalid_amount`, `amount_too_large`, `invalid_reason`, `unknown_region`, `charge_refused`.
- Shop: `not_ready`, `tailor_busy`, `tailor_error`, `db_failed`, `unknown_shop`, `unknown_entry`, `out_of_range`,
  `earned_only`, `not_stocked`, `wrong_sex`, `tier_too_low`, `tier_unavailable`, `already_owned`.
- Wardrobe: `not_owned`, `not_outfit`, `not_item`, `too_many_items`, `duplicate_item`, `bad_slot`, `empty_slot`,
  `bad_label`, `not_at_wardrobe`, `too_fast`.
- Grant: `invalid_citizenid`, `unknown_citizenid`, `invalid_source`.

## Money rules (Tier A)

See the header of `server/tailor.lua`. In short: one operation per character at a time (buy never waits: `tailor_busy`);
the ownership row is claimed before the charge, so a retry or a concurrent buy is never charged twice; any charge
refusal removes that claim again; `fh_charge_busy` is retried with the character re-checked before each attempt.
