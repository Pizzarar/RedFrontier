# Brainstorm Summary · ANIMATIONS (`animations`)

> Rolling team brief (< ~5k tokens). Updated on every decision.

## Who's here
- Brainstorm: animations
- Lead: Ani1 · core anims
- Workers: 0

## Done when
- animations-01 A0–A7 PASS and merged; Aub's P0 RESULT applied; owner test steps written for each anim key.

## Decided
- Plan: docs/brainstorm/plans/animations-01-core-anims.md (A0 probe ∥ A1 fh_anim → A2–A5 parallel → A7 flag flip).
- Cosmetic, non-blocking anims. New resource [fh]/fh_anim (play/start/stop exports + fh:anim:play event); server sites add one fire-and-forget TriggerClientEvent.
- Avoid ox_lib anim.scenario (string to TaskStartScenarioInPlace, progress.lua:92); hash scenarios ourselves like rsg-core progress.lua:45. P0 tests both forms.
- Config.Enabled=false until the P0 RESULT; A0 goes to Spikes lead rn-3095b3717f66 (S8 spk_anim).

## Open
- Aub P0 RESULT (A0 card) → A7 (+ A1 low: late dict-load fail cancelling newer same-key anim).
- docs/brainstorm/animations.md is untracked on main; Red4 to commit it with the next brief sweep.

## In flight
- 2026-11-25 A2 skin d21097c PASS 0/0/1, A3 gather/craft/cook 2493545 PASS 0/0/0, A4 eat/drink/refill/wash c051de9 PASS 0/0/0, A5 chest/trough/garden 567b666 PASS 0/0/1 (trough site = T.load feedbag), merged. A7 queue: P0 RESULT, A1 same-key invalidate minor, A5 sender spec asserts, skin ms vs SkinDurationMs.
- 2026-11-25 A0 spk_anim S8 merged 017fa4d (Spikes). A1 fh_anim PASS 0/0/1 9bf0ecc (Gemini rn-64988b9cfbf6), merged; minor (stale same-key requestAnimDict fail invalidates newer claim, main.lua:45) folded into A7.
- 2026-11-25 Ani1 rn-61a8094e7415: A0 sent to Spikes lead rn-3095b3717f66; A1 fh_anim building (rn-419497bc280e, Sonnet, branch animations-a1, review Gemini). A3 vs S6: no clash now (crafting-herb-spike 0 ahead), re-check before A3.
- A0 MERGED main 017fa4d (Gemini PASS 0/0/0). Card S8 in [spikes]/TEST-CARDS.md:49; relayed to Aub 2026-11-25. RESULT -> Ani1 + Buddy -> A7.
- A1 9bf0ecc PASS 0/0/1, queued #2 in Red4 slot; rebase + range-diff + re-gate at grant. Then A2-A5 parallel; first to merge drops temp fh:anim:play allowlist.
