# Progression

Your reputation in a region sets your **tier** there, from 1 to 3. Higher tiers open things up. Only heartlands is set up so far.

## Tiers (heartlands)
| Tier | Reputation needed |
|---|---|
| 1 | always (the floor) |
| 2 | 100 |
| 3 | 400 |

Reputation itself is earned and tracked by the economy, not here. This system only reads it. See [Economy](fh_economy.md).

## What tiers unlock
| Unlock | Tier |
|---|---|
| Contracts (`contracts_t2`) | 2 |
| Wagon (`wagon_t2`) | 2 |
| Fence rare stock | 2 |
| Hire a hand | 2 |
| Fence treasure leads | 3 |

These are the unlock names in the config. Other lanes decide how each one shows up in game.

## Good to know
- An unknown region or no loaded character counts as tier 1.
- If reputation can't be read (economy down), you are not granted anything by mistake. The read fails instead of reporting 0.
- Not yet tested in game.

See also: [Regions](../regions.md) · [Wiki index](../README.md)

Sources:
- `server/resources/[fh]/fh_progression/README.md`
- `server/resources/[fh]/fh_progression/config.lua`
