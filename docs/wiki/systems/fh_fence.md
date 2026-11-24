# Fence: the roving trader

A travelling fence moves between two spots in the Heartlands, staying about 20 minutes at each. It buys and sells outside the law: stolen gun and saddlery parts, plus directions to treasure.

## Finding the fence
- Two stops in a fixed loop: the **Roadside Fence** and the **Camp-Edge Fence**. It moves every 20 minutes.
- Stand at the current stop and press `E` (within 6 m) to open its menu. See [Controls](../controls.md).

## What it sells
Common stock is always there; rare stock and treasure leads unlock with your Heartlands tier (see [Progression](progression.md)).

| Stop | Always | Tier 2 | Tier 3 |
|---|---|---|---|
| Roadside Fence | bread $3, water $2 | Gunsmith Parts $90 | Treasure Lead $250 |
| Camp-Edge Fence | bread $3 | Gunsmith Parts $95, Saddlery Fittings $100 | Treasure Lead $300 |

A Treasure Lead is a one-off item with a hint and a spot written on it.

## What it buys
- Gunsmith Parts $30 · Saddlery Fittings $35

Buying is charged to your cash; selling pays you in cash. If anything is refused, nothing is taken.

Positions and the fence's look are placeholders and unverified in game.

See also: [Economy](fh_economy.md) · [Progression](progression.md) · [Wiki index](../README.md)

Sources:
- `server/resources/[fh]/fh_fence/config.lua`
- `server/resources/[fh]/fh_fence/shared/fence_logic.lua`
- `server/resources/[fh]/fh_fence/server/main.lua`
- `server/resources/[fh]/fh_fence/client/main.lua`
