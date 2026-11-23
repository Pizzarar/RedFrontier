# Brainstorm Summary · QUESTS (`quests`)

> Rolling team brief (< ~5k tokens). Updated on every decision.

## Who's here
- Brainstorm: Quests
- Lead: Quests Lead
- Workers: 0

## Done when
- fh_quests is on local main with all of the following, review PASS and specs green:
  - engine with its API README (tutorial-ready for @guide)
  - jobs board (hunt_request, camp_clear, bounty + @roads freight registration)
  - 3 family questlines
- OWNER-TESTS quests section written; `decision quests playtest-ready <hash>` logged.

## Decided
- 2026-11-23: plan `docs/brainstorm/plans/quests-01-engine-board-families.md`. fh_quests = pure engine/match/board modules + thin server. Steps advance only on whitelisted `fh:*` events with citizenid. Rewards only via fh_economy. State in `fh_quest_state`. Job types register via `registerJobType` (@roads freight uses it). 3 families v1. ox_lib menu/dialogue is the fallback until @ui screens arrive (tracked workaround).
- Q1 (API README) lands first and gets announced to @guide, @ui, @roads.
- Lead: Quests Lead rn-cee29f7cf4ad (Lead - Claude).

## Open
- Q0a @core idea-614: camp_cleared `participants`. Until it lands, camp_clear credits nobody.
- Q0b @hunting: ACCEPTED 2026-11-23. pelt_sold gets `{citizenid,item_id,animal,size_class,quality,price,region_id}` in Hunting H3 (after H2). Until then, hunt_request matches on quality only.
- @ui follow-ups: jobs board real wiring + quest journal/dialogue screen (replace the ox_lib fallback).

## In flight
- PARKED (forge freeze, 2026-11-23): nothing new and no merges until the Overlord lifts it.
- Q1: PASS from the builder (db7bcb6..4a0e7ff, 66 tests / 0 fail). Gemini review (Quests2 rn-5e9c4fb96b1a) is still to come. Not merged.
- DRAINED (lead confirmed; both worktrees clean; nothing pushed). Parked heads:
  - quests-q1 = 4a0e7ff
  - quests-q2 = 9b79f2e WIP on a2390f0. It has migration 0008 (provisional) plus the shared rewards/store/journal/intake modules, all untested. Still to do: their specs, the server/ glue, and the fxmanifest exports.
- Resume order: Q1 review verdict → merge Q1 → announce the README to @guide/@ui/@roads → rebase Q2 → finish Q2.
