# Brainstorm Summary · WORLD (`world`)

> Rolling team brief (< ~5k tokens). Updated on every decision.

## Who's here
- Brainstorm: World
- Lead: Wor1 Lead · world-01 real places
- Workers: 1

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
- Factions get optional home region (A2) so heat stops using the alphabetically-first region; lawmen listed in every region.
- Plot ids heartlands_01..04 / scarlett_meadows_01..04 kept (DB keys), coords moved off the Valentine grid.
- /where plot = free-claim finder only; town lots show in plain /where as (coming soon) → (town lot) after @homestead H10; @homestead owns a future /where lot (agreed with Hom2).

## Open
- Town lot purchase flow (buy + rep bump) still @homestead; class schema + per-class uniqueness landed H6 281d88a/c90e069.
- Content ladder (hub lean): per region 1-3 lots, 3-5 claims, 3-4 camps (~50 camps); 8 contract types; +2 family questlines (one per state); 15 legendaries; 8 faction loot tables x 3 tiers → @quests/@hunting/@crafting. A-Life supplies the rest.
- Ambush points per region (deferred, no consumer yet) → idea-837.
- Enable the other 11 regions after the owner walks the first 4 (data for all 11 ships in world-02; flipping a region is a one-line change).

## In flight
- world-01 DONE on main d966dcf (A–D PASS).
- world-02 all PASS on world-g2 (rebased on 3307497, 90/1620/0, syntax 188/0); merge slot asked from Red3 (2026-11-24). F 8dc260c single-source coords (idea-809 closed). G1 3839c84+9ba59ec: 33 claims + 12 lots in 11 disabled regions, region gate in canClaim and /fh_buylot. E 8b2aa64+fb2a5ba+f4763d8 lootByFaction 8x3. G2 987499b+c1ad231: 33 camps + 14 posts, fh_trade gate for disabled posts. All 11 regions stay enabled=false.
