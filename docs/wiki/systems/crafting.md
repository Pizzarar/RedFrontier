# Crafting

Reload ammo and brew tonics. You need a station, and you craft on your own plot only.

## How to craft
Type `/fh_craft <recipe>`. With no recipe it lists every recipe id. You get `Done: <label>.` on success, or `Missing: <n>x <item> (have <n>)` if you are short. It is all or nothing: if any step fails, what was taken is put back.

## Recipes
| Recipe | Station | Needs | Makes |
|---|---|---|---|
| `ammo_revolver` | reload | 1 gunpowder, 2 lead, 2 brass casings | 1 revolver ammo box |
| `ammo_rifle` | reload | 2 gunpowder, 2 lead, 2 brass casings | 1 rifle ammo box |
| `tonic_vigor` | apothecary | 2 American ginseng, 1 wild mint | 1 Vigor Tonic |
| `tonic_steady` | apothecary | 2 oregano, 1 red sage | 1 Steady Tonic |

## Stations
Reload counts as a **workbench** and apothecary as a **campfire** at your homestead, so you have to build one first (see [Homestead](fh_homestead.md)). You must stand within 3 m. The stations only exist once built; build them with `/fh_build`.

## Tonics
Use a tonic from your inventory. It is only used up if the buff applies.
- **Vigor Tonic:** 1.15 for 10 minutes.
- **Steady Tonic:** 1.10 for 5 minutes.

## Gun restore
Worn guns can be restored with Gun Parts, each worth 20 condition. How far you can restore depends on stars: 1 star up to 60, 2 stars up to 80, 3 stars up to 100. A gun already at its cap refuses. The `/fh_restore` command belongs to the gunsmith, not to this page.

## Known limits
- The shop doesn't sell the inputs yet (lumber, nails, lead, casings, gunpowder and herbs), and Gun Parts are not in the camp loot yet. Until then they need an admin to give them.
- Herb gathering is not built.
- Not yet tested in game.

See also: [Items](../items.md) · [Buffs](fh_buffs.md) · [Wiki index](../README.md)

Sources:
- `server/resources/[fh]/fh_crafting/README.md`
- `server/resources/[fh]/fh_crafting/config.lua`
- `server/resources/[fh]/fh_crafting/shared/recipes.lua`
- `server/resources/[fh]/fh_crafting/shared/craft_rules.lua`
