# Brainstorm Summary · HUNTING (`hunting`)

> Rolling team brief (< ~5k tokens). Updated on every decision.

## Who's here
- Brainstorm: Hunting
- Lead: ★ Hun2
- Workers: 0

## Done when
- Current plan (hunting-03) blocks merged with reviewer PASS + venv specs green, OWNER-TESTS `## Hunting` updated, and `decision hunting trappers-coats-ready <hash>` logged. (hunting-01 and -02 done.)

## Decided
- hunting-01 (H1-H7) + hunting-02 (15 legendaries, idea-840) + idea-950 + H8 raw_meat (idea-853/914) all merged; main 8681d5e. Lead Hun2 rn-bc5251cf4622.
- Latest plan: docs/brainstorm/plans/hunting-03-trappers-coats.md (2026-11-25): C1 regional trappers (idea-1016) || C2 legendary coats (idea-1004) -> C3 docs.
  - Trappers live in data/legendaries/<region>.lua `trapper`, enabled regions only; sell/pay/pelt_sold use that trapper's region_id; rumour bought at it.
  - Coats: on chain_complete, pcall exports.fh_tailor:grant(cid, coat_<legendary_id>_male|_female, 'hunting:legendary:<id>'); wrong_sex ignored; backfill on player load (grant is idempotent), so no ordering dependency on progression T3.
- Standing contracts: events fh:hunting:pelt_skinned/pelt_sold/clue_found/legendary_spawned/chain_complete (citizenid; chain events also carry region_id, legendary). pelt_sold = {citizenid,item_id,animal,size_class,quality,price,region_id}. getTrophyComfort(itemId) for @homestead. Wagon via exports.fh_cargo:nearestWagon(src,nil,8) + getWagon. requestOfNetId+despawn after a skin. Legendaries = data files, FhRegions.isEnabled gate, cargo 3-star pelts.
- Rules: specs only via ~/.venvs/rf/bin/python tools/run-specs.py; Red3 merge slots; no push; never write the owner's name; lane docs are committed in a merge slot only.

## Open
- Sent idea-1019 to @progression: 30 earned_only coat_<legendary_id>_male|female catalog entries (T3). Pro2 rn-4460126058da.
- Trophy comfort is 25 each × 15; tune with @homestead after the playtest.
- Legendary outfit/tint looks and all trapper/legendary coords: TODO-verify-in-game (owner playtest).
- S4 spk_pelt GO → consider PeltQualitySource='native'.

## In flight
- 2026-11-25 Hun2: idea-1050 chainState export (quests-04 L0) PASS 0/0/0 8bd0743 (rn-0dcd2288e19b, Review-Gemini) after FAIL 1/0/1 38bba7f (readState off the FXServer path, fixed).
- 2026-11-25 Hun2: idea-1040 trapper spec (heartlands nil case) PASS 0/0/1 04bf5f7 (rn-18ae4ac3774e). Hunting build queue empty; @ui I2 trapper export OK-ed.
- 2026-11-25 Hun2: hunting-lows (idea-1025 trapper loader warn/error, idea-1027 backfill DB-error log) PASS 0/0/1 1494cc2 (rn-2026511db6eb, Review-Gemini). Low queued idea-1040.
- 2026-11-25 Hun2: hunting-03 COMPLETE. C3 docs PASS 0/0/0 e2c9b0b (rn-40c2867f9aed, Review-Gemini). C1 db3e791, C2 c9f7829. Lows idea-1025/1027 in review on hunting-lows.
- 2026-11-25 Hun2: hunting-03 C2 legendary coats PASS 0/0/1 e5bfc39 (rn-4225ea3d7cc5, Review-Gemini) after FAIL 1/0/0 6b1449c (dup main.lua block, fixed). Source tag hunting:<id minus legendary_>. C3 docs PASS 0/0/0 e2c9b0b, next slot.
- 2026-11-25 Hun2: hunting-03 C1 regional trappers PASS 0/0/2 136acf5 (rn-8f9ca307dddf, Review-Gemini). C2 coats FAIL 1/1/2 7dc61c6 (source >32 chars, N+1 backfill) -> fixing.
- 2026-11-25 hunting-03 handed to Hun2 (C1 || C2 -> C3). Tell @quests when C1 merges (pelt_sold.region_id now varies).
