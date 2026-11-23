# Buffs

Buffs are timed bonuses. Right now the buff system keeps track of them but has **no visible effects yet**; other systems will apply and use them.

## Rules
- Different buffs stack.
- Applying the same buff again while it is active refreshes the timer and keeps the stronger of the two strengths.
- Each buff has a maximum strength.
- Buffs are lost when you relog or the server restarts.

## Known buffs and maximum strength

| Buff | Max |
|---|---|
| `well_fed` | 1.25 |
| `rested` | 1.20 |
| `warm` | 1.0 |
| `trophy_luck` | 1.15 |
| `homestead_comfort` | 1.10 |

What each buff does is defined by the system that uses it, and none of those are built yet.

See also: [Wiki index](../README.md)

Sources:
- `server/resources/[fh]/fh_buffs/README.md`
- `server/resources/[fh]/fh_buffs/config.lua`
