# Inventory

fh_inventory is the inventory screen, a fork of rsg-inventory that follows the fh_core container rules.

## Your inventory

- Two parts: the **hotbar** (5 slots, 8 kg cap) and the **backpack** (the rest).
- Default 25 slots and 35 kg total carry weight.
- Open with `I`, show the hotbar with `Z`, use hotbar slots with `1`-`5`. Keys can be rebound in the game's key settings. See [Controls](../controls.md).
- While the inventory is open you can still use push-to-talk.

## What you can do

Drag to move, swap or merge; Shift + drag moves half; Ctrl + click moves to the other panel; double click uses an item. Right-click for Use, Give, Drop, Trash and more. A search box filters a panel and the Sort button orders it.

- **Give:** pick the nearby player, the amount, confirm.
- **Trash:** asks for confirmation; the item is gone for good.

When a move is refused (too heavy, wrong size class, too far), the game tells you why. Size class rules are in [Core](fh_core.md) and [Items](../items.md).

See also: [Wiki index](../README.md)

Sources:
- `server/resources/[fh]/fh_inventory/README.md`
- `server/resources/[fh]/fh_inventory/DOCS.md`
- `server/resources/[fh]/fh_inventory/shared/config.lua`
