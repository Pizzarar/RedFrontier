# Brainstorm Summary · WORLD (`world`)

> Rolling team brief (< ~5k tokens). Updated on every decision.

## Who's here
- Brainstorm: World
- Lead: Wor1 Lead · world-01 real places
- Workers: 0

## Done when
- All 15 regions exist as data with 8 factions; enabled regions have named claims, town lots, camps and posts that the owner has walked (verified via /where).
- Town lot / claim home classes are live (with @homestead), and the content ladder is handed to its owning lanes.

## Decided
- 2026-11-24 Owner away, "push whatever you need" (via Red3): leans taken (R13). Plan `docs/brainstorm/plans/world-01-regions.md` (A regions+factions, B real claims, C camps+posts, D ground-snap+enabled gate).
- Hub decisions folded in (RiffBot): two home classes (town lot: bought, ~12-15 m, lawman-safe, rep bump; claim: free, big, raid-exposed). "claims" not "camps". 15 regions, no Guarma. 8 factions: lawmen (per-state skin), rail_mining, settlers, traders, bounty_hunters, swamp gang, mountain gang, desert gang.
- Existing faction ids stay (26 refs): raiders→swamp gang, outlaws→mountain gang, rhodes_law = alias of lawmen. Registry shape is @core §4.4; extend only with optional fields, else request from @core.
- Enabled tonight: heartlands, scarlett_meadows, bayou_nwa, great_plains (verified spawn anchors rsg-character/shared/config.lua:200-203). Other 11 enabled=false.
- Coords: x/y from map, verified=false, runtime ground-snap; /where is the fix-up tool (no new survey cmd).
- A-Life contract (a-life-01): factions get `kind` law|outlaw|neutral; keep regions[].factions, territories[].faction, fh_zones camp fields; optional regions[].ambush nodes in world-01 C.
- Plot ids heartlands_01..04 / scarlett_meadows_01..04 kept (DB keys), coords moved off the Valentine grid.

## Open
- Town lot purchase + one lot AND one claim per character (fh_plots.citizenid UNIQUE): schema change, needs @homestead.
- Content ladder (hub lean): per region 1-3 lots, 3-5 claims, 3-4 camps (~50 camps); 8 contract types; +2 family questlines (one per state); 15 legendaries; 8 faction loot tables x 3 tiers → @quests/@hunting/@crafting. A-Life supplies the rest.
- Fill camp `lootByFaction` 8 factions x 3 tiers (A-Life adds the field; @world owns the data).
- Enable the other 11 regions after the owner walks the first 4.

## In flight
- world-01 → Wor1 Lead rn-cb1d438f267f (spawned 2026-11-24).
