# Brainstorm Summary · QUESTS (`quests`)

> Rolling team brief (< ~5k tokens). Updated on every decision.

## Who's here
- Brainstorm: Quests
- Lead: ★ Que2
- Workers: 0

## Done when
- fh_quests is on local main with all of the following, review PASS and specs green:
  - engine with its API README (tutorial-ready for @guide)
  - jobs board (hunt_request, camp_clear, bounty + @roads freight registration)
  - 3 family questlines
- OWNER-TESTS quests section written; `decision quests playtest-ready <hash>` logged.

## Decided
- 2026-11-23: dead ox_lib dependency dropped from fh_quests fxmanifest (q6 37e3ce2, ff on main; Check-Haiku PASS, specs 74/1414/0).
- 2026-11-23: last ox_lib workaround CLOSED: giver dialogue on fh_ui (@ui idea-722, main 53bf1c7 + docs 814075a); server-side reach kept, ui_* relays screen-guarded. fh_quests has no tracked workarounds left.
- 2026-11-23: ox_lib board/journal workaround CLOSED: @ui W2 (47a1761) jobs board, W3 (6eb752e) /journal + abandon, W4 (db06ed0) deleted server/menu.lua, jobs_menu.lua -> client/board.lua, OWNER-TESTS Q5 reworded.
- 2026-11-23: plan `docs/brainstorm/plans/quests-01-engine-board-families.md`. fh_quests = pure engine/match/board modules + thin server. Steps advance only on whitelisted `fh:*` events with citizenid. Rewards only via fh_economy. State in `fh_quest_state`. Job types register via `registerJobType` (@roads freight uses it). 3 families v1. ox_lib menu/dialogue is the fallback until @ui screens arrive (tracked workaround).
- Q1 (API README) lands first and gets announced to @guide, @ui, @roads.
- Lead: Quests Lead rn-cee29f7cf4ad (Lead - Claude).
- Q0a DONE: core idea-614 on local main b63a340. camp_cleared carries `participants` (players within activationRadius at clear; `{}` if none or on error). Q3 intake.lua already reads it. Sent Que2 rn-97a2281b22df the stale README lines (90, 246) plus a spec ask.

## Open
- Q0b DONE on main: fh_hunting/shared/sell.lua:157 emits pelt_sold with animal/size_class/quality/region_id. Closed by q7 4978178: hunt_request requires the animal (wrong-animal spec), stale text fixed.

## In flight
- MERGED 2026-11-23 (Que2): Q1-Q5 + Q0a follow-up on local main b53979a (q1 2296099, q2 d2173f3, q3 ff8031d, q4 738ad8a, q5 b53979a); migration 0007_quest_state; venv specs 35/681/0. Plan quests-01 complete. Not pushed.
- THAWED 2026-11-23 (C2 cutover 15:11:45Z). Rules: no push, one lane merges at a time, never write the owner's name.
- Plan handed to the Overlord rn-01cad4e19b2b, who spawns the lane lead. The resume steps are in the plan's "Resume after forge thaw" section.
- Heads: origin/quests-q1 4a0e7ff (review PASS, merge first); origin/quests-q2 9b79f2e (WIP; the migration renumbers against main, which is at 0005).
- Review PASS (not merged; merges held on lupa): Q1 quests-q1 d277f55 | Q2 quests-q2 3473813 | Q3 quests-q3 f802188 | Q4 quests-q4 c9455b5 | Q5 quests-q5 0adc9aa (stacked chain; specs never run yet).
