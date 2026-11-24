# Core: items, containers and the saddlebag

fh_core is the rulebook for what you can carry and where. Other systems ask it; none of them touch your inventory directly.

## Size classes and containers

Items are `pocket`, `bulky` or `cargo` (see [Items](../items.md)). Each container accepts some classes only.

| Container | Accepts | Slots | Weight cap |
|---|---|---|---|
| Hotbar (equipped) | pocket | 5 | 8 kg |
| Backpack | pocket | the rest of your slots | your total carry weight minus the hotbar |
| Saddlebag | pocket, bulky | 20 | 60 kg |
| Wagon | pocket, bulky, cargo | 60 | 500 kg |
| Chest | pocket, bulky, cargo | 50 | 1000 kg |
| Drop bag | pocket, bulky | 30 | 1000 kg |
| Fence stash | pocket, bulky | 20 | 200 kg |

World containers must be within reach: 3.5 m (wagons 5 m). A container with no position can't be opened.

## Saddlebag

You have one saddlebag per character. Use `/saddlebag` on or next to a horse (the nearest horse within 4 m is picked; you must be within 3.5 m to open). `/saddlebag in|out <slot> [amount]` moves a stack between the container you have open and the saddlebag; that is how a bulky item goes from a chest into the saddlebag. See [Controls](../controls.md).

Known limits: any horse opens your saddlebag for now (the bag is not tied to one horse), and the list of accepted horse models is a guess that is not yet checked in game.

## Item condition and stars

The item registry carries two per-item fields: **condition** (0-100, how worn a weapon is) and **stars** (1-3, the quality of a pelt). Weapons and pelts keep these; a gunsmith caps a restore by stars (see [Gunsmith](fh_gunsmith.md)). See [Items](../items.md).

## Private server

RedFrontier runs as a private server for the owner and up to five friends. You join by invitation — the owner adds your ID to the allowlist — not from a public server list.

## Spawning

Camp outlaws and bag props are created by a nearby player's game and then confirmed by the server. You don't need to do anything.

See also: [Inventory](fh_inventory.md) · [Death](fh_death.md) · [Fence](fh_fence.md) · [Gunsmith](fh_gunsmith.md) · [Wiki index](../README.md)

Sources:
- `server/resources/[fh]/fh_core/README.md`
- `server/resources/[fh]/fh_core/config.lua`
- `server/resources/[fh]/fh_core/shared/items.lua`
- `server/resources/[fh]/fh_core/client/saddlebag.lua`
