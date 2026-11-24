# Regions

Two regions exist so far.

## Heartlands (Valentine)

- **Factions:** Valentine Law and Heartland Outlaws.
- **Homestead plots:** four fixed plots, `heartlands_01` to `heartlands_04`. See [Homestead](systems/fh_homestead.md).
- **Outlaw camp:** one Tier 1 camp, the Heartlands Outlaw Camp. See [Zones](systems/fh_zones.md).
- **Trapper:** one pelt sell point and the start of the legendary bear hunt. See [Hunting](systems/fh_hunting.md).
- **Trade post:** the Valentine Trade Post. See [Roads](systems/roads.md).
- **Jobs board:** hunt, camp-clear and bounty offers, plus freight to Scarlett Meadows. See [Quests](systems/quests.md).
- **Reputation tiers:** tier 2 at 100 rep, tier 3 at 400 rep. Tier 2 unlocks `contracts_t2`, `wagon_t2`, `fence_rare_stock` and `hire_hand`; tier 3 unlocks `fence_treasure_leads`. See [Progression](systems/progression.md).
- **Cold:** no region is cold yet, so the warmth need does not apply. See [Survival](systems/survival.md).

## Scarlett Meadows (Rhodes)

- **Factions:** Rhodes Law and the Lemoyne Raiders.
- **Homestead plots:** four fixed plots, `scarlett_meadows_01` to `scarlett_meadows_04`. See [Homestead](systems/fh_homestead.md).
- **Outlaw camp:** one Tier 1 camp, the Lemoyne Raiders Camp. See [Zones](systems/fh_zones.md).
- **Trade post:** the Rhodes Trade Post. See [Roads](systems/roads.md).
- **Jobs board:** freight offers to haul goods to the Heartlands. Hunt, camp-clear and bounty offers are Heartlands-only for now. See [Quests](systems/quests.md).
- **Trapper and reputation tiers:** not here yet.

Tiers are named T1, T2 and T3. Only T1 has content.

Freight contracts run between the two regions: a shortage in one region becomes a haul job on the other region's board. See [Roads](systems/roads.md).

All coordinates in the code are approximate and still to be checked in game, so this wiki does not list them.

See also: [Wiki index](README.md)

Sources:
- `server/resources/[fh]/fh_core/shared/regions.lua`
- `server/resources/[fh]/fh_homestead/config.lua`
- `server/resources/[fh]/fh_zones/config.lua`
- `server/resources/[fh]/fh_progression/config.lua`
- `server/resources/[fh]/fh_trade/config.lua`
- `server/resources/[fh]/fh_hunting/README.md`
- `server/resources/[fh]/fh_quests/README.md`
- `server/resources/[fh]/fh_survival/README.md`
