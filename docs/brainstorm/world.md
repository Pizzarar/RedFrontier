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

## Open
- Town lot purchase flow (buy + rep bump) still @homestead; class schema + per-class uniqueness landed H6 281d88a/c90e069.
- Content ladder (hub lean): per region 1-3 lots, 3-5 claims, 3-4 camps (~50 camps); 8 contract types; +2 family questlines (one per state); 15 legendaries; 8 faction loot tables x 3 tiers → @quests/@hunting/@crafting. A-Life supplies the rest.
- Fill camp `lootByFaction` 8 factions x 3 tiers (A-Life adds the field; @world owns the data).
- Enable the other 11 regions after the owner walks the first 4.
- idea-809: collapse duplicated camp/post coords into FhRegions (world-01 C workaround). idea-813 (@core): camp ped spawn ground-snap.

## In flight
- world-01 → Wor1 Lead rn-cb1d438f267f. Stack on main 53770c3: 1caa3f4 A (15 regions, 8 factions+kind), b33c68d B (14 named claims, 6 town lots claimable=false), 010470e A2 (faction.home for heat), 7efb410 C (14 camps, 4 posts), 064c54f renames, 920fc70 /where plot skips lots, bc4f404 per-state lawmen + factionLabel, f342821 A-Life spec strings. Gemini PASS 0/0/3, 84/1531/0. Merge slot asked from Red3 (2026-11-24).
- D 02d3194 (wt world-d): ground-snap, isEnabled gate, (unverified) tag, OWNER-TESTS walk-the-claims. Worker PASS 85/1543/0; nit fixes then review, then merge.
- Gaps queued: camp peds spawn at config z (@core idea-813); camp/post coord duplication (Workaround → idea-809).
- Next after world-01 merges: owner walks claims via /where; then plan world-02 (lootByFaction 8x3, idea-809, enable more regions).
