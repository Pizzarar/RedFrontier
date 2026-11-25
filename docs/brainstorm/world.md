# Brainstorm Summary · WORLD (`world`)

> Rolling team brief (< ~5k tokens). Updated on every decision.

## Who's here
- Brainstorm: World
- Lead: ★ Wor2
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
- Factions get optional home region (A2) so heat stops using the alphabetically-first region; lawmen listed in every region.
- Plot ids heartlands_01..04 / scarlett_meadows_01..04 kept (DB keys), coords moved off the Valentine grid.
- /where plot = free-claim finder only; town lots show in plain /where as (coming soon) → (town lot) after @homestead H10; @homestead owns a future /where lot (agreed with Hom2).

## Open
- Town lot purchase flow (buy + rep bump) still @homestead; class schema + per-class uniqueness landed H6 281d88a/c90e069.
- Content ladder: world side done (claims/lots/camps/posts in all 15 regions, lootByFaction 8x3). Contracts + questlines → @quests, 15 legendaries → @hunting (queued 2026-11-24).
- Enable the other 11 regions after the owner walks (readiness spec says all 15 ready; flip = `setr fh_regions_enabled` in server.cfg + restart, OWNER-STEPS §5). Walk via fh_tour/fh_mark → world_walk.json → world-04 fixes.

## In flight
- world-01 DONE on main d966dcf (A–D PASS).
- world-02 DONE + MERGED: ff c1ad231 (docs c74e386), pushed 2026-11-24, 90/1620/0. F 8dc260c single-source coords (idea-809 closed). G1 3839c84+9ba59ec: 33 claims + 12 lots in 11 disabled regions, region gate in canClaim and /fh_buylot. E 8b2aa64+fb2a5ba+f4763d8 lootByFaction 8x3. G2 987499b+c1ad231: 33 camps + 14 posts, fh_trade gate for disabled posts. All 11 regions stay enabled=false.
- world-03 DONE + MERGED: ff e437e1c on d492bfe (2026-11-25), 109/2022/0, contracts 0. H 82a6ad8+2924e77, I 333a0f5+f494617, J c2da053+ebad099+03c4ec7, a-life spec setup ba65b0e+7dc5121 (AL2 ack). Owner walk: fh_tour/fh_mark → world_walk.json → world-04.
- world-04 DONE + MERGED (Wor2): ff 7a8a47b on e8ba6f1 (2026-11-25), 122/2231/0, contracts 0, syntax 231/0. M 5cd9baa admin [id] tags (server canSeeIds), N 4d963ec walk sheets (52 places, OWNER-TESTS block), L 46eb416+59278e7 tools/world-walk-apply.py, O 7a8a47b dup id fix: town manzanita_post→manzanita + unique-id spec. All PASS. Now blocked on owner walk; world-05 = apply verdicts + flip regions.
