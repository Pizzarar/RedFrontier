# fh_tailor

Fitted outfits as progression (progression-03). You start in a basic set, buy whole outfits (plus a few safe single
items) at tailors and general stores, and earn some only through other systems (@hunting legendary coats, @quests
rewards). rsg-character keeps face and body only; fh_tailor never edits it.

Implemented catalog-style tailor/general-store clothing progression — Thanks to Red Dead Redemption 2 (single-player
tailors and catalogs) by Rockstar Games (design idea only; no assets or text copied).

## Status

- T1 (this): pure logic + server. Catalog, per-shop stock, ownership, buy, grant, starter set, equip, saved outfits.
- `Config.FittedOutfits = false` until the @spikes S1 probe passes. Off: everything above works and persists; nothing
  is applied to the ped (T2 client apply, ox_lib menus).
- Config ships one placeholder starter outfit per sex and one placeholder shop. Real catalog content is T3.

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
`[%w_:.-]`, at most 32 chars, e.g. `hunting:legendary_bear`. The entry must fit the character's sex (pass the sex
variant), else `wrong_sex`. A granted row is never removed by a refused buy (a refusal only deletes its own `buy` row).

**`charge_unavailable` keeps the outfit** (lead decision, same rule as fh_hands: never charge twice). When the
fh_economy export throws, it is unknown whether money moved. The buy returns `true, { ..., unverified = true }`, the
ownership row stays, and the server logs an `ALERT` line with citizenid, entry, price and shop; the fh_ledger charge
row tells an admin whether it was paid. At worst the clothes were free; the player is never charged a second time.

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
  `bad_label`.
- Grant: `invalid_citizenid`, `unknown_citizenid`, `invalid_source`.

## Money rules (Tier A)

See the header of `server/tailor.lua`. In short: one operation per character at a time (buy never waits: `tailor_busy`);
the ownership row is claimed before the charge, so a retry or a concurrent buy is never charged twice; any charge
refusal removes that claim again; `fh_charge_busy` is retried with the character re-checked before each attempt.
