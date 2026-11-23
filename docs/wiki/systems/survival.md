# Survival

Eat, drink, rest, stay clean. These are **never lethal**: your health is never touched. Miss needs and you just get sluggish.

## Needs
Each need is a timed buff. Keep them up.

| Need | Buff | Lasts |
|---|---|---|
| Food | `well_fed` | 60 min |
| Water | `hydrated` | 45 min |
| Rest | `rested` | 120 min |
| Clean | `clean` | 90 min |
| Warmth | `warm` | 20 min (only counts in cold regions; none exist yet) |

## Sluggish levels
Missing needs add up to a level from 0 (fine) to 3 (worst): one missing is level 1, two is 2, three or more is 3. By default you get a short notice line (`level N/3`), at most once a minute. A stamina/movement version exists but is off by default (unverified in game). A new character gets 10 minutes before sluggish can start. Needs you had when you logged out come back with the time that was left, and the clock does not run while you are offline.

## How to fix each need
- **Food:** jerky (50% of the food time), biscuit (35%), stew (100%, and a stronger buff).
- **Water:** use a canteen. It holds 5 charges, and one use spends one charge and gives `hydrated`. An empty canteen refuses. Stand in water and type `/refill` to fill it.
- **Clean:** stand in water and type `/wash`. You can wash once every 5 minutes.
- **Rest:** use a bedroll, or a bed at your homestead (needs a bed station nearby; a better-furnished home rests you a little stronger, up to 1.20).
- **Warm:** stand within 4 m of a campfire. Two seeded fires exist, at the heartlands homestead and the outlaw camp (approximate positions).

"Standing in water" is checked against two seeded spots on the Dakota River (approximate; they are marked owner-verifiable in the config). The native in-water check is unverified.

## Known limits
- No cold region is set up, so warmth is only a bonus for now.
- `hydrated` and `clean` need caps in the buffs resource; until that is in, the game logs a warning and the other needs keep running.
- Not yet tested in game.

See also: [Buffs](fh_buffs.md) · [Homestead](fh_homestead.md) · [Tips](../tips.md) · [Wiki index](../README.md)

Sources:
- `server/resources/[fh]/fh_survival/README.md`
- `server/resources/[fh]/fh_survival/config.lua`
