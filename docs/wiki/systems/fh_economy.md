# Economy: money and reputation

Money is paid in **cash**. Reputation is tracked **per region** (see [Regions](../regions.md)) and can go up or down. Every payment, charge and reputation change is written to a permanent ledger.

## Money in
- Selling pelts to the trapper (see [Hunting](fh_hunting.md)).
- Selling trade goods at a trade post, and freight deliveries (see [Roads](roads.md)).
- Selling to the fence (see [Fence](fh_fence.md)).
- Quest rewards (see [Quests](quests.md)).

## Money out
- Buying from the fence (see [Fence](fh_fence.md)).
- Hired-hand wages (see [Hired hands](fh_hands.md)).
- The legendary-bear rumour at the trapper (see [Hunting](fh_hunting.md)).

## Offline payouts
Money owed to you while you are **offline** is queued and paid when you next log in, so a payout is never lost. Refunds and other "owed" money use the same queue.

## Caps and rules
- One payout, charge or queued credit is capped at 100000.
- Reputation per region stays between -10000 and 10000; one change is capped at 1000.
- A charge never takes your balance below 0.

See also: [Regions](../regions.md) · [Progression](progression.md) · [Wiki index](../README.md)

Sources:
- `server/resources/[fh]/fh_economy/README.md`
- `server/resources/[fh]/fh_economy/config.lua`
- `server/resources/[fh]/fh_hunting/README.md`
- `server/resources/[fh]/fh_fence/config.lua`
