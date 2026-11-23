# Items

Every item has a **size class**. It decides where the item can go.

| Size class | Fits in |
|---|---|
| pocket | everything: hotbar, backpack, saddlebag, wagon, chest, drop bag, fence stash |
| bulky | saddlebag, wagon, chest, drop bag, fence stash (not the hotbar or backpack) |
| cargo | wagon and chest only |

An item with no size class is a pocket item. Weights are in grams.

Some items carry extra data: **condition** (0-100) and **stars** (1-3, the quality of a pelt).

## Items you can meet today

| Item | Size class | Weight | Where it comes from |
|---|---|---|---|
| Worn Rifle | bulky | 4000 g | Outlaw camp stash. Condition 20-45 |
| Small Safe | bulky | 25000 g | Outlaw camp stash |
| Pelts (12) and a trophy | bulky or cargo | see [Hunting](systems/fh_hunting.md) | Not obtainable yet: skinning is not built |

Other items come from the base game's item list and have no special rules, so they are pocket items.

See also: [Core: containers](systems/fh_core.md) · [Wiki index](README.md)

Sources:
- `server/resources/[fh]/fh_core/README.md`
- `server/resources/[fh]/fh_core/config.lua`
- `server/resources/[fh]/fh_zones/config.lua`
- `server/resources/[fh]/fh_hunting/README.md`
