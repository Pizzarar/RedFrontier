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
| `E` (unverified) | Open the fence menu when you stand at the fence's current stop | `server/resources/[fh]/fh_fence/client/main.lua:4` |
| `E` (unverified) | At the trapper: sell pelts, or ask about the legendary bear while on that clue | `server/resources/[fh]/fh_hunting/client/main.lua:155` |

Each `E` prompt shows a text hint (`[E] Dropped belongings`, `[E] Homestead chest <n>`, `[E] Outlaw camp stash`) when you stand within 2 m (`server/resources/[fh]/fh_homestead/client/main.lua:116`).

Skinning an animal, the jobs-board notice board and quest givers use the rsg-target prompt (point at the target), not a key listed here.

## Chat commands

| Command | What it does | Source |
|---|---|---|
| `/fh_claim` | Claim the homestead plot you are standing in | `server/resources/[fh]/fh_homestead/server/main.lua:143` |
| `/fh_unclaim` | Release your plot | `server/resources/[fh]/fh_homestead/server/main.lua:148` |
| `/saddlebag` | Open the saddlebag of the horse you ride, or the nearest horse within 4 m | `server/resources/[fh]/fh_core/client/saddlebag.lua:29` |
| `/saddlebag in <slot> [amount]` | Move a stack from the open container into your saddlebag | `server/resources/[fh]/fh_core/client/saddlebag.lua:29` |
| `/saddlebag out <slot> [amount]` | Move a stack from your saddlebag into the open container | `server/resources/[fh]/fh_core/client/saddlebag.lua:29` |
| `/fh_build [slot]` | Build the next tier of a plot slot; no argument lists slots and costs | `server/resources/[fh]/fh_homestead/server/build.lua:355` |
| `/fh_trophy place <item>` / `remove <trophy_id>` | Place or remove a trophy on your plot | `server/resources/[fh]/fh_homestead/server/build.lua:374` |
| `/fh_station <type>` | Is that station (`workbench`, `campfire`, `tanning_rack`) within reach on your plot | `server/resources/[fh]/fh_homestead/server/build.lua:386` |
| `/fh_comfort` | Show your homestead comfort | `server/resources/[fh]/fh_homestead/server/build.lua:394` |
| `/jobs` | Open the jobs board (works anywhere) | `server/resources/[fh]/fh_quests/client/board.lua:11` |
| `/journal` | Open your quest journal | `server/resources/[fh]/fh_quests/client/journal.lua:3` |
| `/refill` | Refill your canteen (stand in water) | `server/resources/[fh]/fh_survival/client/actions.lua:17` |
| `/wash` | Wash to get the `clean` buff (stand in water, 300 s cooldown by default) | `server/resources/[fh]/fh_survival/client/actions.lua:18` |
| `/fh_craft <recipe>` | Craft one recipe at a station on your plot; no argument lists recipes | `server/resources/[fh]/fh_crafting/server/craft.lua:72` |
| `/fh_restore <slot>` | Restore a worn weapon in the open container, using gun parts | `server/resources/[fh]/fh_gunsmith/server/main.lua:83` |
| `/tradepost` | Open the trade post menu (stand within the post radius) | `server/resources/[fh]/fh_trade/client/main.lua:5` |
| `/tradequote` | List trade post prices in chat | `server/resources/[fh]/fh_trade/server/main.lua:224` |
| `/tradesell <item> <amount>` | Sell a trade good at the post | `server/resources/[fh]/fh_trade/server/main.lua:231` |
| `/paybounty [faction] [points]` | Pay off heat with money | `server/resources/[fh]/fh_heat/server/main.lua:211` |

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
- `server/resources/[fh]/fh_fence/client/main.lua`
- `server/resources/[fh]/fh_hunting/client/main.lua`
- `server/resources/[fh]/fh_homestead/server/build.lua`
- `server/resources/[fh]/fh_quests/client/board.lua`
- `server/resources/[fh]/fh_quests/client/journal.lua`
- `server/resources/[fh]/fh_survival/client/actions.lua`
- `server/resources/[fh]/fh_crafting/server/craft.lua`
- `server/resources/[fh]/fh_gunsmith/server/main.lua`
- `server/resources/[fh]/fh_trade/client/main.lua`
- `server/resources/[fh]/fh_trade/server/main.lua`
- `server/resources/[fh]/fh_heat/server/main.lua`
