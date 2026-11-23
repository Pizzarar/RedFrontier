# Hunting and pelts

Status: the data and rules exist. **Skinning, selling pelts, the Legendary Bear hunt and trophies are not built yet.** You can't get a pelt in game today.

## Pelts
One pelt item per animal. Each pelt has a **star rating** (1-3).

| Size class | Animals |
|---|---|
| bulky (saddlebag OK) | rabbit, fox, coyote, deer, boar, wolf |
| cargo (wagon or chest only) | bear, bison, elk, moose, alligator |

The Legendary Bear pelt is cargo and always 3 stars. Its trophy is a bulky keepsake.

## Quality
The spot you hit the animal decides the stars:
- **Head or vital:** 3 stars.
- **Body:** 2 stars, with a 10% chance of one star less.
- **Limb or gut:** 1 star. Hitting the animal 2 or more times also counts as 1 star.

## Value
A pelt's price is its base value times a star multiplier: 1 star 0.4, 2 stars 1.0, 3 stars 1.8. Legendary pelts are multiplied by 4 on top.

See also: [Items](../items.md) · [Economy](fh_economy.md) · [Wiki index](../README.md)

Sources:
- `server/resources/[fh]/fh_hunting/README.md`
- `server/resources/[fh]/fh_hunting/config.lua`
- `server/resources/[fh]/fh_hunting/shared/animals.lua`
