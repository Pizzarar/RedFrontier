# Controls

There is no central keymap. Each system defines its own keys, so this page lists every key with the file it comes from. Keys tagged **(unverified)** have not been confirmed in game yet.

## Keys

| Key | What it does | Source |
|---|---|---|
| `I` | Open the inventory. Rebindable in the game's key settings | `server/resources/[fh]/fh_inventory/shared/config.lua:23` |
| `Z` | Show the hotbar. Rebindable | `server/resources/[fh]/fh_inventory/shared/config.lua:24` |
| `1`-`5` | Use hotbar slot 1 to 5. Rebindable | `server/resources/[fh]/fh_inventory/shared/config.lua:25` |
| `E` (unverified) | Open your dropped belongings bag | `server/resources/[fh]/fh_death/client/main.lua:5` |
| `E` (unverified) | Open your homestead chest | `server/resources/[fh]/fh_homestead/client/main.lua:5` |
| `E` (unverified) | Open the outlaw camp stash (only after the camp is cleared) | `server/resources/[fh]/fh_zones/client/main.lua:9` |

Each `E` prompt shows a text hint (`[E] Dropped belongings`, `[E] Homestead chest`, `[E] Outlaw camp stash`) when you stand within 2 m.

## Chat commands

| Command | What it does | Source |
|---|---|---|
| `/fh_claim` | Claim the homestead plot you are standing in | `server/resources/[fh]/fh_homestead/server/main.lua:143` |
| `/fh_unclaim` | Release your plot | `server/resources/[fh]/fh_homestead/server/main.lua:148` |
| `/saddlebag` | Open the saddlebag of the horse you ride, or the nearest horse within 4 m | `server/resources/[fh]/fh_core/client/saddlebag.lua:29` |
| `/saddlebag in <slot> [amount]` | Move a stack from the open container into your saddlebag | `server/resources/[fh]/fh_core/client/saddlebag.lua:29` |
| `/saddlebag out <slot> [amount]` | Move a stack from your saddlebag into the open container | `server/resources/[fh]/fh_core/client/saddlebag.lua:29` |

## Inside the inventory

| Input | Action |
|---|---|
| Drag | Move, swap or merge. The amount box sets the quantity (0 or empty = whole stack) |
| Shift + drag | Move half a stack |
| Ctrl + click | Quick move to the other panel |
| Double click | Use the item |
| Right-click | Menu: Use, Give, Drop, Trash, Move to / Take, Buy / Sell, Copy serial |

Source: `server/resources/[fh]/fh_inventory/DOCS.md` (section 18).

See also: [Inventory](systems/fh_inventory.md) · [Wiki index](README.md)

Sources:
- `server/resources/[fh]/fh_inventory/shared/config.lua`
- `server/resources/[fh]/fh_inventory/DOCS.md`
- `server/resources/[fh]/fh_death/client/main.lua`
- `server/resources/[fh]/fh_homestead/client/main.lua`
- `server/resources/[fh]/fh_zones/client/main.lua`
- `server/resources/[fh]/fh_homestead/server/main.lua`
- `server/resources/[fh]/fh_core/client/saddlebag.lua`
