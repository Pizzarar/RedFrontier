# @ui SPEC · fh_ui shared NUI shell

Lanes ship data/events, @ui ships screens. No authority in fh_ui; producers own `fh:<owner>:ui_<action>` handlers. Readability first, light Hypnospace surrealism (one accent).

## Done when
- [x] Shell + relay + passive HUD (buffs, bags) + fixture screens + OWNER-TESTS `## UI` (U1-U4, 1ccf7b5)
- [x] Fence shop live (idea-601), jobs board + quest journal live (ui-wiring-fence-quests)
- [x] Giver dialogue screen replaces ox_lib (idea-722, 53bf1c7)
- [x] Trade post + trapper screens replace ox_lib menus; heat HUD live (docs/plans/ui-live-trade-heat.md; c51335e, d19a22e, 99b2057)
- [ ] Insurance dialog live (blocked: fh_death L4 insurance block)
- [ ] Station/crafting menus live (blocked: crafting client surface undecided)
- [ ] @guide handbook + tutorial prompts (blocked: no schema)
- [ ] No ox_lib menus/dialogs left in [fh] resources (except action progress bars)
- [ ] `ui playtest-ready <hash>` logged after the last live screen
