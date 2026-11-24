# Homestead

Homesteads are fixed plots you claim. Four plots exist in the Heartlands and four in Scarlett Meadows. See [Regions](../regions.md). Plot positions are placeholders and not checked in game (unverified).

## Claiming
- Stand inside a plot and use `/fh_claim`. Plots are 25 m in radius.
- One plot per character.
- `/fh_unclaim` releases your plot. Your slots and trophies go with it. Chest contents stay in the chest, and pass to the next owner. See [Controls](../controls.md).

## Your chest
Every plot has one owner-only chest. Walk up and press `E` (unverified). It accepts pocket, bulky and cargo items, so it is where big loot ends up. See [Items](../items.md).

## Building
Use `/fh_build <slot>` inside your plot to build the next tier. `/fh_build` alone lists every slot with its cost.
- **Materials come from your plot chest**, not your pockets. Put lumber and nails in the chest first.
- Money is charged too. If anything fails, you get everything back.
- Nothing in the game hands out lumber or nails yet. Only an admin can (unverified).

| Slot | Tiers | Cost | Needs |
|---|---|---|---|
| Cabin | 1 | $150, 20 lumber | |
| Cabin | 2 | $400, 40 lumber, 20 nails | |
| Fence | 1 | $100, 15 lumber | |
| Workbench | 1 | $60, 10 lumber | |
| Campfire | 1 | $25, 5 lumber | |
| Tanning rack | 1 | $80, 12 lumber | |
| Trophy wall | 1 | $120, 10 lumber | |
| Extra chest 2 | 1 | $40, 8 lumber | cabin 1 |
| Extra chest 3 | 1 | $60, 10 lumber | cabin 2 |

- The fence makes your safe area 10 m bigger.
- Built pieces show as placeholder props (unverified).
- The stations are used by [Crafting](crafting.md). Only you can use the ones on your plot.

## Comfort and trophies
Every built piece adds comfort points. Trophies add more, but only with the trophy wall built: up to 20 points in total, and the best 6 count.
- `/fh_trophy place <item>` takes the trophy out of your chest. `/fh_trophy remove <id>` puts it back.
- `/fh_comfort` shows your number. Homestead gives no buffs itself; the survival system reads the number. See [Survival](survival.md).
- The Legendary Bear trophy is worth 25 comfort. See [Hunting](fh_hunting.md).

See also: [Death](fh_death.md) · [Quests](quests.md) · [Wiki index](../README.md)

Sources:
- `server/resources/[fh]/fh_homestead/README.md`
- `server/resources/[fh]/fh_homestead/config.lua`
- `server/resources/[fh]/fh_homestead/server/main.lua`
- `server/resources/[fh]/fh_homestead/server/build.lua`
- `server/resources/[fh]/fh_homestead/client/main.lua`
- `server/resources/[fh]/fh_homestead/server/comfort.lua`
- `server/resources/[fh]/fh_hunting/README.md`
