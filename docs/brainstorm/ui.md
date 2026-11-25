# Brainstorm Summary · UI (`ui`)

> Rolling team brief (< ~5k tokens). Updated on every decision.

## Who's here
- Brainstorm: UI
- Lead: ★ UI3
- Workers: 0

## Done when
- fh_ui on local main with U1-U4 PASS, specs green, `## UI` card in OWNER-TESTS.md, `decision ui playtest-ready <hash>` logged.

## Decided
- Plan: docs/plans/ui-fh_ui-shell.md (U1 shell → U2 buff HUD + bag timer ∥ U3 fixture screens → U4 test card).
- Inventory stays in fh_inventory's own NUI; fh_ui never renders containers.
- Contract: `fh:ui:open/close/update {screen,data}` in; `fh:ui:action` out, relayed as `fh:<lane>:ui_<action>`; no authority in fh_ui.
- Screens with no producing lane yet use fixtures + `fh_ui_demo`; reuse `fh_spike_gated`, no new flag.
- @quests contract = fh_quests README @ quests-q1 d277f55 (on local main b53979a since Q1-Q5 merge): `fh:quests:sync` v1 snapshot {journal[], board{region_id,epoch,expires_at,offers[{id,job_type,title,text,rewards,accepted}]}} + emitted events. Server actions: acceptOffer(src,offer_id), abandon(src,quest_id). ox_lib menus in Q3/Q4 are fallback until @ui wires jobs board + journal.
- Overlord rules: vs worktree units, merge after PASS + rebase + run-specs green, one lane at a time, OWNER-TESTS `## UI` only, no push, log playtest-ready.

## Open
- Insurance dialog live: blocked on fh_death L4 insurance block.
- Station/crafting menus live: blocked, fh_crafting has no client surface yet.
- @guide handbook + tutorial prompts: no schema yet.
- `ui playtest-ready <hash>` still to log after the last live screen.

## In flight
- Done: shell U1-U4 (1ccf7b5), plan 2 fence/jobs/journal, idea-715 (60ec4aa), plan 3 giver dialogue idea-722 (53bf1c7, docs 814075a).
- Plan 4: docs/plans/ui-live-trade-heat.md (T1 trade post ∥ T2 trapper ∥ T3 heat HUD -> T4 test card). Handed to UI2 rn-8c7a9bce2671 2026-11-24 (Red3: use quota, no parking). Dispatched: T1 rn-ee8719325f84, T2 rn-2f2273ccb86b, T3 rn-a7e00dec968c; Roa3 (fh_trade, fh_heat) + Hun2 pinged.
- idea-690 archived: satisfied by U2 buff HUD.
- SPEC seeded: docs/lanes/ui/SPEC.md (Done-when checklist; tick as plans land).
- PASS merged d19a22e: T3 heat HUD live (837390b) + idea-854 survival HUD (881aaaa). T1 held: contracts lint 2 findings (fh:trade:sell/buy handlers lost their sender) -> fix. T2+T4 wait on hunting-l1.
- PASS merged 8ca4067: T1 tradepost (c51335e + contracts fix 59eb13f) + idea-849 fieldguide (5c7c850, 0c1028d). Guide lead + Roa3 pinged. Left: T2 trapper + T4 card after hunting-l1.
- PASS merged d8f2103: T2 trapper re-port on hunting-02 (99b2057) + T4 owner card steps 25-29. Plan 4 ui-live-trade-heat COMPLETE.
- Plan 5 ui-tailor-catalog (idea-1003, progression-03 T4): T4a PASS 0/0/1, merged f16213f (tailor + wardrobe screens on T2b act* exports). T4b PASS, merged a22db9f (mirror preview + tailor stops open fh_ui screens, ox_lib menus removed). T4c+T4d merged 56e66b7 (owner steps UI 30-36, saddlebag Wardrobe button). Plan 5 ui-tailor-catalog COMPLETE.
- Plan 6 ui-inbox-03 (idea-1007 locked offers, idea-1021 all-region trappers, idea-1023 wagonyard screen): I2 PASS 0/0/3, merged. I1 PASS 0/0/0 a007399, I3 PASS + delta PASS 386e04c (Roa4 OK), queued for slots.
