# Roads

Wagons, trade, and the law. Built, but **not checked in game yet** (unverified). Wagons are spawned with an admin command (`/fh_wagon`) today.

## Wagons
Three tiers. A full wagon is slowed by 40%.

| Tier | Slots | Max weight | Top speed (empty) |
|---|---|---|---|
| Cart | 15 | 120 kg | 8.0 m/s |
| Wagon | 30 | 300 kg | 7.0 m/s |
| Freight | 60 | 500 kg | 6.0 m/s |

- One wagon per character per tier. Respawn it and the cargo is still inside.
- `/fh_cargo load` and `/fh_cargo unload` move **cargo** items between your own wagon and the chest you have open. Stand within 5 m. See [Items](../items.md).
- **No fast travel while hauling.** Carrying cargo, or having your loaded wagon within 30 m, blocks it.

## Wheels
- A wagon can break a wheel. Speed, load and leaving the road raise the odds. Going off-road is not detected yet (unverified).
- A broken wagon is limited to 40% of its speed.
- `/fh_repair` needs a hammer and a wagon wheel. It takes 8 seconds. Don't move more than 3 m, or it cancels.

## Trade post
Heartlands has one: the Valentine Trade Post. Use `/tradepost` to sell, or `/tradequote` for prices.

| Good | Base price |
|---|---|
| Salt Sack | $6 |
| Bolt of Cloth | $14 |
| Whiskey Crate (cargo) | $40 |

- Prices drift up to 8% over time, and there are regional differences.
- Shortages raise a good's price. Selling into one eases it.
- Every unit you sell pushes the price down. It recovers over time. About 40 units in one region cut it by half.

## Freight jobs
Shortages in other regions become freight jobs on the `/jobs` board. See [Quests](quests.md).
- Have your wagon within 8 m when you accept. The cargo is loaded for you.
- Deliver within 30 minutes. Reward is the going price plus 25%, and +2 rep.
- Two active contracts at most.
- Only one region exists today, so no freight offers appear yet.

## Heat
Each faction tracks your heat from 0 to 100, separately.
- Clearing a camp adds 25. Selling illicit goods adds 10.
- Levels: Watched at 25, Wanted at 50, Hunted at 75.
- Heat falls 2 per minute while you are outside that faction's territory.
- `/paybounty` shows your heat and what it costs. It is $4 per point. `/paybounty <faction> [points]` pays it.
- **Wanted:** a roadblock of 4 faction guards appears at the nearest chokepoint (positions unverified).
- **Hunted:** night ambushes and mounted chases exist, but are switched off for now (waiting on a test result).

See also: [Economy](fh_economy.md) · [Zones](fh_zones.md) · [Wiki index](../README.md)

Sources:
- `server/resources/[fh]/fh_cargo/README.md`
- `server/resources/[fh]/fh_cargo/config.lua`
- `server/resources/[fh]/fh_trade/README.md`
- `server/resources/[fh]/fh_trade/config.lua`
- `server/resources/[fh]/fh_heat/README.md`
- `server/resources/[fh]/fh_heat/config.lua`
