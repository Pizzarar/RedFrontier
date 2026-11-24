# fh_inventory (RedFrontier fork of rsg-inventory)

Fork of [rsg-inventory](https://github.com/Rexshack-RedM/rsg-inventory) by Rexshack-RedM at
`a151ee4c27a8d251ae69e85f92f83bdd9175b13c`, still GPL-3 (`LICENSE`). Everything marked `-- FH:` in the code is ours;
`git log --follow` from commit 671f2b7 (the unchanged move) shows every change. The upstream README follows the
fork notes below.

## What the fork changes

- **Stands in for rsg-inventory.** `provide 'rsg-inventory'` plus `shared/fh_provide.lua`, which aliases every export
  as `rsg-inventory:<fn>`, so rsg-core, rsg-character and RSG scripts keep calling it by the old name.
- **fh_core rules are the veto.** The manifest loads `@fh_core/config.lua`, `shared/items.lua`, `containers.lua` and
  `rules.lua` into this resource (`FhConfig`, `FhItems`, `FhContainers`, `FhRules`). Every add, move, swap and
  layout write is checked by `FhRules` before anything changes. The player inventory is two sections: **equipped**
  (the hotbar, `FhConfig.Containers.equipped.slots`, sets `Config.HotbarSlots`) and **backpack** (the rest).
  Size classes decide what goes where (e.g. cargo is refused in the backpack, accepted in a chest).
- **World containers need coords.** A stash, drop or shop with no coords, or out of reach, can't be opened or used.
  Every ground drop is a `drop_bag` and persists (`Config.Drop.Persist`).
- **fh_core owns fh containers.** Only fh_core (or this resource) can register, reshape, clear or delete a
  container that fh_core registered, or call the `Fh*` exports (`server/fh_api.lua`). Game code calls fh_core's
  exports (`move`, `transferAll`, `registerContainer`, `open`, `createDropBag`, ...), never these.
- **Saddlebag player pane (B6f, dark).** Convar `fh_saddlebag_pane` (server only, default `false`, set in
  `server/server.cfg`; `true`/`1`/`yes`/`on` turn it on, read on every call so turning it off live snaps every pane
  back). When on, the open event carries a third argument `{ saddlebagPane = true }` and the screen shows a
  backpack/saddlebag toggle; when off, the open event is the unchanged two-argument rsg form. The server alone decides
  which pane is active (`Pane[src]`): `'player'` in move/split/sort/give/trash/drop means that pane, gated by
  `exports.fh_core:saddlebagPane` before every action and once a second (a failure snaps back to the backpack and the
  action is refused). Use and shop buy/sell are refused on the saddlebag pane. Closing the inventory, leaving or a
  character switch resets to the backpack. Specced in `spec/saddlebag_pane_spec.lua`.
- **Runtime-registered items** resolve through `RSGCore.Shared.Items` (`FhItems.sharedLookup`), so an item fh_core
  pushed with its `size_class` is classed correctly here.

## Fail-closed behaviour (on purpose)

When the rules can't place something, the mutation is refused and nothing changes:

- **Non-fh stashes refuse items.** A stash registered by plain `RegisterStash` without an fh type gets view type
  `stash`, which `FhRules` doesn't know, so `AddItem`, moves and transfers into it fail, and a non-fh stash with no
  coords can't be opened at all. No vendored resource uses stashes today; anything that needs a stash registers it
  through `exports.fh_core:registerContainer`.
- **`Fh*` refs never create containers.** An unknown id, a shop, `newdrop`, a non-fh stash or a ref whose `type`
  doesn't match the container's fh type is refused with `fh_unknown_container`.
- **`SetInventory` is all-or-nothing.** The whole layout must pass (`FhCheckLayout`): valid slots, known items,
  size classes per section, section and total weight. Otherwise it returns `false, reason`, logs the refusal and
  leaves the inventory as it was.
- **Locked fields.** `SetItemData` refuses `name`, `slot`, `amount`, `weight`, `unique` and `type`.
- **Reasons** are `fh_*` locale keys (`locales/en.json`), shown to the player when a drag is refused.

Allowed without a veto (they only remove items or rewrite info): decay, trash, sort, `RemoveItem`,
`SetItemInfo`, shop Sell, `WeaponDefaults` info backfill, and coin conversion (`ConvertCoins`, same value).

## Not verified yet

- `GetInvokingResource()` for internal and net-event calls: `FhCallerAllowed` accepts both `nil` and this
  resource's own name.
- `provide` + export aliasing in a live boot (whether every `exports['rsg-inventory']:X` call lands here).

---

## Upstream README (rsg-inventory)

Slot/weight inventory for the RSG Framework (rsg-core) with a hotbar, persistent stashes, ground drops, shops with persistent stock, category filters, automatic coin exchange and a legacy-compatible API so existing RSG scripts keep working.

**Version:** 3.4.0 · **Requires:** `rsg-core` 3.5.0 or newer, `oxmysql` · **ox_lib:** not required

> Developers: see **[DOCS.md](DOCS.md)** for the full API, data formats and integration examples.

---

## Features

- **Slot + weight inventory** — player slots/weight come from rsg-core PlayerData (fallbacks in config).
- **Hotbar** — first 5 slots, shown with `Z`, used with `1`–`5`.
- **Drag & drop** — move, swap, merge, split (amount box), Shift-drag for half, Ctrl-click quick move.
- **Right-click menu** — Use, Give, Drop, Move to / Take, Split, Buy / Sell, Copy serial — each with One / Half / All / Amount… (Give opens the player picker below). **Trash** permanently destroys items after a warning and confirmation.
- **Give with a player picker** — Give lists the players within `Config.GiveDistance` (character name, server ID and distance), you choose the exact recipient, enter the quantity and confirm. The list refreshes while it is open; if the chosen player walks away or leaves, the choice is cancelled. The server re-checks the recipient, distance, item and quantity.
- **Ground drops** — dropping creates a bag prop (`p_bag01x`) other players can open; empty or expired drops are removed automatically.
- **Persistent stashes** — stored in the `inventories` table, saved on close, when idle, on resource stop and on txAdmin shutdown; idle stashes are unloaded from memory.
- **Stash action buttons** — a script can add up to 3 of its own buttons to a stash header (e.g. "Bundle Sets" on an rsg-cards box) and handle the click on the server.
- **Player search** — open another player's inventory from the server (e.g. lawman / robbery scripts).
- **Shops** — created by other resources; buy by dragging out, sell by dragging in; optional persistent stock, restocking, max stock, quality-scaled sell price and minimum quality.
- **Category filter chips** — based on each item's `category` in rsg-core shared items.
- **Search box + Sort button** — filter either panel by name; Sort merges stacks and orders by category and name (your hotbar keeps its order; shops and ground piles can't be sorted).
- **Capacity bonuses** — satchels, horses or wagons can add slots / weight through an export (see below).
- **Item decay** *(optional)* — chosen items or categories lose quality over time and can spoil away.
- **Stash history** — every put / take in a stash is logged (who, what, when) and kept for `Config.Stash.HistoryDays`.
- **Admin viewer** — `/viewinv [id]` opens any player's inventory from any distance.
- **Nearby drop sync** — ground drops are only sent to players close to them; optional persistence across restarts.
- **Coin exchange** — every 100 cents / blood cents become 1 dollar / blood dollar automatically.
- **Metadata-aware stacking** — stacks only merge when `info` matches (quality, serial, etc.).
- **Weapons** — serial and quality added automatically; using a weapon hands off to rsg-weapons; a weapon leaving your inventory is removed from your hands.
- **Crash-safe** — player ↔ stash / player ↔ player moves write both sides at once, so a crash can't duplicate or lose an item.
- **Server-authoritative** — distance, dead / last stand / handcuffed checks, cooldowns; players can't open stashes from the client.
- **Item box** — NUI popup for added / removed / used items, position configurable.
- **Logging** through `rsg-log`.
- **Localised:** en, de, el, es, fr, ja, nl, pl, pt-br, ro, ru.
- **Auto-creates its database tables** (`Config.AutoDatabase`; manual `install.sql` still provided).

---

## Installation

1. Download and place `rsg-inventory` in your resources folder (replace any older rsg-inventory).
2. Ensure start order in `server.cfg`:
   ```cfg
   ensure oxmysql
   ensure rsg-core
   ensure rsg-inventory
   ```
3. Put item images (PNG, named after the item's `image` field) in `html/images/`.
4. **Database** — the `inventories` and `shop_stock` tables are created automatically on first start. For a manual install, set `Config.AutoDatabase = false` and import `install.sql`.
5. Restart the server.

Existing data loads as-is: player items stay in `players.inventory`, stashes in `inventories`.

---

## Configuration

All options are in `shared/config.lua`.

| Option | Default | Description |
|---|---|---|
| `Config.ItemBox` | `true` | Show the item image box on add / remove / use |
| `Config.ItemBoxPosition` | `'right'` | `top`, `bottom`, `top-left`, `top-right`, `bottom-left`, `bottom-right`, `left`, `right` |
| `Config.Notifications` | `true` | rsg-core notifications for rejected actions (too heavy, no money, too far…) |
| `Config.ItemNotifications` | `false` | Also show a toast for every item change |
| `Config.Debug` | `false` | Print why moves / purchases are rejected to the server console |
| `Config.AutoDatabase` | `true` | Create the database tables on start. Set `false` and import `install.sql` to install manually |
| `Config.ImagePath` | `nui://rsg-inventory/html/images/` | Item image folder |
| `Config.PlayerSlots` / `PlayerMaxWeight` | `25` / `35000` | Fallbacks if PlayerData has no slots / weight |
| `Config.HotbarSlots` | `5` | First N slots are the hotbar |
| `Config.UseKeyMapping` | `true` | Register the keys with `RegisterKeyMapping` so players can rebind them. `false` polls `Config.Keys` instead |
| `Config.MappedKeys` | I, Z, 1–5 | Default key names for open, hotbar and slots |
| `Config.BlockNativeControls` | `true` | Keep blocking the game's own satchel menu (`I`) and weapon select (`1`–`5`) |
| `Config.Keys` | I, Z, 1–5 | RedM control hashes: fallback polling and native blocking |
| `Config.UseCooldown` | `500` | ms between item uses |
| `Config.Stash.DefaultSlots` / `DefaultMaxWeight` | `50` / `1000000` | Defaults for new stashes |
| `Config.Stash.MaxSlots` / `MaxWeight` | `300` / `10000000` | Upper clamp for any stash |
| `Config.Stash.SaveInterval` | `5` | Minutes idle before a changed stash is saved |
| `Config.Stash.UnloadAfter` | `30` | Minutes idle before a stash is unloaded from memory |
| `Config.Stash.History` / `HistoryDays` | `true` / `14` | Log who put / took what in stashes, and how many days to keep |
| `Config.Drop.Slots` / `MaxWeight` | `30` / `1000000` | Ground drop capacity |
| `Config.Drop.Prop` | `p_bag01x` | Drop prop model |
| `Config.Drop.OpenDistance` | `2.0` | Distance to see a drop when opening the inventory |
| `Config.Drop.RenderDistance` | `50.0` | Prop spawn distance |
| `Config.Drop.Lifetime` | `15` | Minutes before an untouched drop is removed |
| `Config.Drop.SyncDistance` / `SyncInterval` | `120.0` / `3` | Drops are only sent to players this close (keep above `RenderDistance`), refreshed every N seconds |
| `Config.Drop.Persist` | `false` | Keep drops across restarts (table `inventory_drops`; their timer restarts on load) |
| `Config.Capacity` | `50` / `100000` | Cap for a single capacity bonus (`MaxBonusSlots` / `MaxBonusWeight`) |
| `Config.Decay` | disabled | Item decay: `Enabled`, `Interval` (minutes), `Stashes`, and `Items` / `Categories` rules `{ rate, remove }` |
| `Config.GiveDistance` | `3.0` | Max distance for giving items; players inside it appear in the Give list |
| `Config.GiveMaxPlayers` | `12` | Most players shown in the Give list (closest first) |
| `Config.Trash.Enabled` | `true` | Show the right-click Trash option (permanent delete with confirmation) |
| `Config.CoinConversion` | cent→dollar, blood_cent→blood_dollar | Set `false` to disable |
| `Config.CategoryLabels` | `{}` | Display names for categories (e.g. `ammo_pistol = 'Pistol Ammo'`) |
| `Config.ShopRestockMinutes` | `60` | Shop restock + stock save interval |

---

## How to use

### Controls
| Input | Action |
|---|---|
| `I` | Open / close inventory |
| `Z` | Show hotbar |
| `1`–`5` | Use hotbar slot |

The three keys above are defaults: players can rebind them in the game's key settings ("Open inventory", "Show hotbar", "Use hotbar slot N").

| Input | Action |
|---|---|
| Drag | Move / swap / merge (amount box, `0` = whole stack) |
| Shift-drag | Move half a stack |
| Ctrl-click | Quick move to the other panel |
| Right-click | Options menu |
| Double-click | Use item |
| Drag onto **Use** / **Give** | Use, or open the Give player picker (the amount box pre-fills the quantity) |
| Search box | Show only items whose name matches (works together with the category chips) |
| **Sort** | Merge stacks and order by category / name (your own inventory, or an open stash) |

### Ground
Opening the inventory near a drop shows that drop on the right. Otherwise the right panel is the ground — drop items there to create a bag.

### Shops
Drag an item out of the shop to buy it (amount box, default 1). Drag an item onto the shop to sell it, if the shop buys that item. Sell price scales with item quality.

### Commands
| Command | Permission | Description |
|---|---|---|
| `/giveitem [id] [item] [amount]` | admin | Give an item to a player |
| `/clearinv [id]` | admin | Clear a player's inventory |
| `/viewinv [id]` | admin | Open a player's inventory from any distance (logged) |
| `/stashlog [stash] [amount]` | admin | Print the latest actions in a stash to the server console |

---

## Quick developer examples

```lua
-- a wearable satchel that adds 10 slots and 15 kg (server side; re-apply when the player loads / equips it)
exports['rsg-inventory']:AddCapacityBonus(src, 'satchel', 10, 15000)
exports['rsg-inventory']:RemoveCapacityBonus(src, 'satchel') -- overflow items move to free slots or the ground
```

```lua
-- give / take items
exports['rsg-inventory']:AddItem(src, 'bread', 2)
exports['rsg-inventory']:RemoveItem(src, 'bread', 1)

-- open a stash
exports['rsg-inventory']:OpenStash(src, 'house_12', { label = 'House Storage', slots = 50, maxWeight = 200000 })

-- open a stash with a header button, and handle the click (server)
exports['rsg-inventory']:OpenStash(src, 'crate_7', { label = 'Crate', actions = { { id = 'empty', label = 'Empty Crate' } } })
AddEventHandler('rsg-inventory:stashAction', function(src, stashId, actionId)
    if stashId ~= 'crate_7' or actionId ~= 'empty' then return end
    -- your own checks, then do the work
end)

-- create and open a shop
exports['rsg-inventory']:CreateShop({ name = 'general', label = 'General Store',
    items = { { name = 'bread', price = 0.5, amount = 50 } } })
exports['rsg-inventory']:OpenShop(src, 'general')
```

Full reference: **[DOCS.md](DOCS.md)**.

---

## Locales
`en`, `de`, `el`, `es`, `fr`, `ja`, `nl`, `pl`, `pt-br`, `ro`, `ru` in `locales/`. Language follows the `rsg:locale` convar.

## Support
If you like this script: https://buymeacoffee.com/rexshack

## Client error reporting

The fh_core dev client-error return (`FH.safe` and friends, `fh:dev:clientError`) is deliberately **not** applied to this resource: the fork's diff from upstream rsg-inventory stays minimal (docs/decisions/inventory.md). Its client errors appear only in the RedM client log.
