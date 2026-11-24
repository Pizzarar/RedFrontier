# Items

Every item has a **size class**. It decides where the item can go.

| Size class | Fits in |
|---|---|
| pocket | everything: hotbar, backpack, saddlebag, wagon, chest, drop bag, fence stash |
| bulky | saddlebag, wagon, chest, drop bag, fence stash (not the hotbar or backpack) |
| cargo | wagon and chest only |

An item with no size class is a pocket item. Weights are in grams.

Some items carry extra data: **condition** (0-100) and **stars** (1-3, the quality of a pelt). A weapon restored at a gunsmith station is capped by its stars: 1 star 60, 2 stars 80, 3 stars 100.

## Items you can meet today

| Item | Size class | Weight | Where it comes from |
|---|---|---|---|
| Worn Rifle | bulky | 4000 g | Outlaw camp stash. Condition 20-45 |
| Small Safe | bulky | 25000 g | Outlaw camp stash |
| Beef Jerky (`fh_jerky`) | pocket | 150 g | Eat for `well_fed`. Source not listed in the code |
| Hardtack (`fh_biscuit`) | pocket | 120 g | Eat for `well_fed`. Source not listed in the code |
| Tin of Stew (`fh_stew`) | pocket | 400 g | Eat for a stronger `well_fed`. Source not listed in the code |
| Canteen (`fh_canteen`) | pocket | 500 g | Drink for `hydrated`; `/refill` in water |
| Bedroll (`bedroll`) | bulky | 2500 g | Use for `rested`. Source not listed in the code |
| Gun Parts, Lead, Brass Casings | pocket | 150 / 60 / 20 g | Crafting inputs. Gun Parts drop from outlaw camps; Lead and Brass Casings still need an admin `/giveitem` |
| Vigor Tonic, Steady Tonic | pocket | 200 g | Brewed at an apothecary station. Use for a buff |
| Pelts (12) and the legendary bear trophy | bulky or cargo | see [Hunting](systems/fh_hunting.md) | Skin dead animals. Sell to the trapper |
| Salt Sack, Bolt of Cloth | pocket | 1500 / 2500 g | Trade goods, sold at a trade post |
| Whiskey Crate | cargo | 15000 g | Trade good, sold at a trade post. Wagon or chest only |

Other items come from the base game's item list and have no special rules, so they are pocket items.

See also: [Core: containers](systems/fh_core.md) · [Crafting](systems/crafting.md) · [Survival](systems/survival.md) · [Wiki index](README.md)

Sources:
- `server/resources/[fh]/fh_core/README.md`
- `server/resources/[fh]/fh_core/config.lua`
- `server/resources/[fh]/fh_zones/config.lua`
- `server/resources/[fh]/fh_hunting/README.md`
- `server/resources/[fh]/fh_survival/shared/items.lua`
- `server/resources/[fh]/fh_crafting/README.md`
- `server/resources/[fh]/fh_trade/config.lua`
