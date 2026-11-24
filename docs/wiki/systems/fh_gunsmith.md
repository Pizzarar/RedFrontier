# Gunsmith: restoring worn weapons

Restore the condition of a worn weapon with gun parts, at a workbench on your plot.

## How to restore
1. Open the container holding the weapon (chest, wagon or saddlebag).
2. Stand at a **workbench** on your own plot (within 3 m).
3. Type `/fh_restore <slot>` with the weapon's slot in that open container.

Each gun part restores **20 condition**. How far you can go depends on the weapon's stars: 1 star to 60, 2 stars to 80, 3 stars to 100 (a weapon with no stars counts as 1 star). It uses the fewest parts that reach the cap, or all you have.

## Where gun parts come from
Outlaw camps drop gun parts (see [Zones](fh_zones.md)). The fence sells **Gunsmith Parts** — a separate illicit item that does not repair guns (see [Fence](fh_fence.md)).

The workbench must be built first (see [Homestead](fh_homestead.md)). Weapon condition shows in the item's info. Visual wear is data-only for now.

See also: [Crafting](crafting.md) · [Zones](fh_zones.md) · [Wiki index](../README.md)

Sources:
- `server/resources/[fh]/fh_gunsmith/README.md`
- `server/resources/[fh]/fh_gunsmith/server/main.lua`
- `server/resources/[fh]/fh_crafting/shared/craft_rules.lua`
