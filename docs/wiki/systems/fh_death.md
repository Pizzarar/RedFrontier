# Death and the drop bag

Soft death: you don't lose everything.

## When you die
- **Hotbar:** stays with you.
- **Backpack and saddlebag:** move into a **drop bag** where you died. If both are empty, no bag is made.
- Each life drops once. You count as alive again after at least 5 seconds dead and once your health is back.

## Getting it back
- Walk up to the bag and press `E` (unverified, see [Controls](../controls.md)). Only you can open it, and you must be close (3.5 m).
- A bag nobody empties is **deleted after 30 minutes**, and what it held is lost.
- Bags survive a server restart.

## Known limits
- Logging out before your death registers drops nothing.
- You can put items back into your own bag; they expire with it.
- Insurance and a doctor fee are planned and not built.
- Not yet tested in game.

See also: [Core: containers](fh_core.md) · [Tips](../tips.md) · [Wiki index](../README.md)

Sources:
- `server/resources/[fh]/fh_death/README.md`
- `server/resources/[fh]/fh_death/config.lua`
- `server/resources/[fh]/fh_death/client/main.lua`
