# Hunting and pelts

Skinning, selling pelts and 15 legendary hunts (one per region) are built. **None of it is checked in game yet** (unverified).

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
| cargo (wagon or chest only) | bear, bison, elk, moose, alligator, and all 15 legendaries |

Every legendary pelt is cargo and always 3 stars. Each legendary hunt also yields a bulky trophy keepsake. See [Items](../items.md).

## Quality
The spot you hit the animal decides the stars:
- **Head or vital:** 3 stars.
- **Body:** 2 stars, with a 10% chance of one star less.
- **Limb or gut:** 1 star. Hitting the animal 2 or more times, or killing it with explosives, also counts as 1 star.

## Selling
- The Trapper is in the Heartlands. Press `E` (unverified) within 2 m to open the sell menu.
- It lists the pelts in your saddlebag and in a nearby wagon. Pelts in your backpack can't be sold. Trophies aren't bought.
- A pelt's price is its base value times a star multiplier: 1 star 0.4, 2 stars 1.0, 3 stars 1.8. Legendary pelts are multiplied by 4 on top.
- Legendary pelt base values follow `round(plain species value * 4/3)` (for example, bear 45 becomes 60 for the Legendary Bear).
- Example: a deer has a base value of 14. See [Economy](fh_economy.md).

## Legendary hunts
There is one legendary animal per region across all 15 regions, each with its own three-clue chain. Each character gets one hunt per legendary, and hunts in different regions can run at the same time. Your progress is saved, so you can log out and carry on.

**Region gate:** only legendaries in **enabled** regions are active (currently 4: Heartlands, Scarlett Meadows, Bayou Nwa and Great Plains). In disabled regions, no rumour prompt or clue marker appears and the hunt cannot be started or advanced. If an enabled region is later disabled, any hunt in progress freezes in place (it is not reset) and resumes when the region is enabled again.

1. **Rumour:** buy the rumour at the region's rumour point ($25 for every legendary). The Legendary Bear's rumour is hosted at the Heartlands Trapper.
2. **Tracks:** inspect the track marker.
3. **Final clue:** inspect the third clue marker (such as a carcass or sign). The legendary animal appears.
4. **Kill and skin:** only the character whose hunt spawned the legendary can skin it. You get its 3-star cargo pelt (needs a wagon within 8 m) and its bulky trophy. If your saddlebag and wagon are both full, the trophy is skipped while the pelt is still granted.

Miss a clue and you can't skip ahead. The Whitlock family quest asks for the Legendary Bear hunt. See [Quests](quests.md).

### Trophies
Every legendary drops a bulky trophy worth **25 comfort** on your [Homestead](fh_homestead.md) trophy wall. The trophy wall caps total trophy comfort at 20 points across the best 6 trophies. Trophies are not bought by the Trapper.

### All 15 legendaries
All rumour, marker and spawn positions (as well as outfit and scale presets) are guesses and not checked in game (unverified).

| Region | Enabled | Legendary | Species | Pelt base value |
|---|---|---|---|---|
| Heartlands | yes | Legendary Bear | Bear | 60 |
| Scarlett Meadows | yes | Legendary Red Clay Stag | Deer | 19 |
| Bayou Nwa | yes | Legendary Mossback Gator | Alligator | 73 |
| Great Plains | yes | Legendary Dusthorn Bison | Bison | 53 |
| Big Valley | no | Legendary Copperhide Deer | Deer | 19 |
| Bluewater Marsh | no | Legendary Brackhide Boar | Boar | 16 |
| Cholla Springs | no | Legendary Cinderjaw Coyote | Coyote | 11 |
| Cumberland Forest | no | Legendary Greyhowl Wolf | Wolf | 27 |
| Gaptooth Ridge | no | Legendary Sandveil Fox | Fox | 11 |
| Grizzlies East | no | Legendary Frostmane Moose | Moose | 67 |
| Grizzlies West | no | Legendary Palehorn Elk | Elk | 51 |
| Hennigan's Stead | no | Legendary Saltbrush Buck | Deer | 19 |
| Rio Bravo | no | Legendary Canyonback Boar | Boar | 16 |
| Roanoke Ridge | no | Legendary Coalhorn Moose | Moose | 67 |
| Tall Trees | no | Legendary Embercoat Coyote | Coyote | 11 |

See also: [Economy](fh_economy.md) · [Homestead](fh_homestead.md) · [Wiki index](../README.md)

Sources:
- `server/resources/[fh]/fh_hunting/README.md`
- `server/resources/[fh]/fh_hunting/config.lua`
- `server/resources/[fh]/fh_hunting/shared/animals.lua`
- `server/resources/[fh]/fh_hunting/shared/plain_animals.lua`
- `server/resources/[fh]/fh_hunting/shared/legendaries.lua`
- `server/resources/[fh]/fh_hunting/shared/chain.lua`
- `server/resources/[fh]/fh_hunting/shared/trophies.lua`
- `server/resources/[fh]/fh_core/shared/regions.lua`
- `server/resources/[fh]/fh_homestead/README.md`
