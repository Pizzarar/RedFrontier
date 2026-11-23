# Tips

- **Your hotbar is safe when you die.** Only the backpack (and saddlebag) drop. Keep what you can't lose in the five hotbar slots. See [Death](systems/fh_death.md).
- **Hotbar weight is capped at 8 kg**, inside your total carry weight. See [Core](systems/fh_core.md).
- **Go back for your bag.** It lasts 30 minutes by default, then it is deleted with everything in it. Only you can open it.
- **Big loot needs a ride.** Bulky items (Worn Rifle, Small Safe) can't go in the backpack. Use a saddlebag, wagon or your homestead chest. Cargo items need a wagon or chest. See [Items](items.md).
- **Your homestead chest is for you alone.** One chest on your plot, owner only. Unclaiming a plot leaves the chest contents in place. See [Homestead](systems/fh_homestead.md).
- **The outlaw camp has four outlaws.** They wake when you come within 45 m. After you clear it, it resets in 10 minutes. See [Zones](systems/fh_zones.md).
- **Ctrl + click** moves an item to the other panel quickly. See [Controls](controls.md).
- **Big game needs a wagon.** Bear, bison, elk, moose, alligator and legendary pelts are cargo. A wagon must be within 8 m or the skin is refused and the carcass stays. See [Hunting](systems/fh_hunting.md).
- **Aim for the head.** Head and vital hits give a 3 star pelt, gut or limb shots 1 star. A 3 star pelt pays 1.8x base, a 1 star 0.4x.
- **Food and water are only buffs.** Running out makes you sluggish (never lethal). Eat, fill your canteen with `/refill` and wash with `/wash` in water. See [Survival](systems/survival.md).
- **Cargo blocks fast travel** while you carry it or while your loaded wagon is within 30 m. See [Roads](systems/roads.md).
- **Clearing a camp raises faction heat by 25** (an illicit sale is set to add 10 but the code comment says it is not wired yet). Heat fades while you lay low outside that faction's territory. `/paybounty` pays it off.
- **Check the jobs board** with `/jobs`. It changes every 60 minutes and a finished job has a 60 minute cooldown. See [Quests](systems/quests.md).
- **Crafting needs a station on your own plot.** Build one with `/fh_build`, then `/fh_craft <recipe>`. See [Crafting](systems/crafting.md).
- **Buffs of the same kind refresh, they don't add.** Different buffs stack. See [Buffs](systems/fh_buffs.md).

See also: [Wiki index](README.md)

Sources:
- `server/resources/[fh]/fh_death/README.md`
- `server/resources/[fh]/fh_death/config.lua`
- `server/resources/[fh]/fh_core/config.lua`
- `server/resources/[fh]/fh_homestead/README.md`
- `server/resources/[fh]/fh_zones/config.lua`
- `server/resources/[fh]/fh_buffs/README.md`
- `server/resources/[fh]/fh_inventory/DOCS.md`
- `server/resources/[fh]/fh_hunting/README.md`
- `server/resources/[fh]/fh_survival/README.md`
- `server/resources/[fh]/fh_cargo/README.md`
- `server/resources/[fh]/fh_heat/README.md`
- `server/resources/[fh]/fh_quests/README.md`
- `server/resources/[fh]/fh_crafting/README.md`
