# Hunting and pelts

Skinning, selling pelts and the Legendary Bear hunt are built. **None of it is checked in game yet** (unverified).

## Skinning
- Kill an animal, stand within 5 m, and use the **Skin** option. A 4-second progress bar runs, then you get a pelt.
- Only skin with that option. The game's own skinning gives no pelt.
- Bulky pelts go in your saddlebag, then a wagon. Cargo pelts need a wagon within 8 m, or the skin is refused and the carcass stays.
- Skin the same carcass twice and you get one pelt.

## Pelts
One pelt item per animal. Each pelt has a **star rating** (1-3).

| Size class | Animals |
|---|---|
| bulky (saddlebag OK) | rabbit, fox, coyote, deer, boar, wolf |
| cargo (wagon or chest only) | bear, bison, elk, moose, alligator |

The Legendary Bear pelt is cargo and always 3 stars. Its trophy is a bulky keepsake. See [Items](../items.md).

## Quality
The spot you hit the animal decides the stars:
- **Head or vital:** 3 stars.
- **Body:** 2 stars, with a 10% chance of one star less.
- **Limb or gut:** 1 star. Hitting the animal 2 or more times, or killing it with explosives, also counts as 1 star.

## Selling
- The Trapper is in the Heartlands. Press `E` (unverified) within 2 m to open the sell menu.
- It lists the pelts in your saddlebag and in a nearby wagon. Pelts in your backpack can't be sold. Trophies aren't bought.
- A pelt's price is its base value times a star multiplier: 1 star 0.4, 2 stars 1.0, 3 stars 1.8. Legendary pelts are multiplied by 4 on top.
- Example: a deer has a base value of 14. See [Economy](fh_economy.md).

## The Legendary Bear
One hunt per character, three clues in the Heartlands. Your progress is saved, so you can log out and carry on.
1. **Rumour:** ask the Trapper about it. It costs $25.
2. **Tracks:** inspect the bear tracks.
3. **Carcass:** inspect the mauled carcass. The bear appears.
4. Kill and skin it. Only you can skin your bear. You get the pelt and the trophy. If your saddlebag and wagon are both full, the trophy is skipped.

Miss a clue and you can't skip ahead. The Whitlock family quest asks for this hunt. See [Quests](quests.md). Bring the trophy home to your [Homestead](fh_homestead.md) trophy wall.

Marker positions are guesses (unverified).

See also: [Economy](fh_economy.md) · [Wiki index](../README.md)

Sources:
- `server/resources/[fh]/fh_hunting/README.md`
- `server/resources/[fh]/fh_hunting/config.lua`
- `server/resources/[fh]/fh_hunting/shared/animals.lua`
