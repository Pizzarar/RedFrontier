# Buffs

Buffs are timed bonuses. Different buffs stack; applying the same one again refreshes its timer and keeps the stronger value. Each buff has a maximum strength.

## Buffs today

| Buff | Max | Applied by |
|---|---|---|
| `well_fed` | 1.25 | Eating food ([Survival](survival.md)) |
| `hydrated` | 1.0 | Drinking from a canteen |
| `rested` | 1.20 | Resting (bedroll or homestead bed) |
| `clean` | 1.0 | Washing |
| `warm` | 1.0 | Standing near a fire |
| `tonic_vigor` | 1.15 | Vigor Tonic ([Crafting](crafting.md)) |
| `tonic_steady` | 1.10 | Steady Tonic |
| `trophy_luck` | 1.15 | Defined; nothing applies it yet |
| `homestead_comfort` | 1.10 | Defined; nothing applies it yet |

Survival turns missing food, water, rest and cleanliness into sluggishness; tonics boost you for a few minutes. Buffs are lost when you relog or the server restarts.

See also: [Survival](survival.md) · [Crafting](crafting.md) · [Wiki index](../README.md)

Sources:
- `server/resources/[fh]/fh_buffs/README.md`
- `server/resources/[fh]/fh_buffs/config.lua`
- `server/resources/[fh]/fh_survival/shared/needs.lua`
- `server/resources/[fh]/fh_crafting/shared/craft_rules.lua`
