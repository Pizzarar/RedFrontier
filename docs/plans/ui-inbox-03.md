# ui-inbox-03 · locked quest offers, all-region trappers, wagon-yard screen

Ideas: idea-1007 (@quests), idea-1021 (@hunting Hun2), idea-1023 (@roads Roa3). Lead: UI3 rn-6551e91acd85.

## Decided
- **Primitives checked:** fh_ui shell contract (`fh:ui:open/close/update`, relay `fh:<lane>:ui_<action>`, `M.actions` allowlists), jobs board screen (plan 2), `fh_ui/shared/places.lua` blips + `/where`, fh_quests `locked={min_tier}` + `FhQuestsConfig.showLockedOffers` (README:376), fh_hunting `trappers = FhHuntingSell.trappers(...)` (server/main.lua:204), fh_cargo Wagon post API (README:128, roads-04 R16/R17 on main). No new vs/skill primitive.
- All three dependencies are on main (quests-03 9c461b4, hunting-03 2ec45d2, roads-04 2414784/abbf600).
- Server authority stays with producers: fh_quests `acceptOffer` already refuses `fh_offer_locked`; fh_cargo owns `fh:cargo:ui_<action>` handlers and calls `buyWagon` with the relay net src.
- I1 flips `showLockedOffers=true` in the same commit as the screen (quests asked: "flip the flag when the UI lands").
- I3 removes the fh_cargo ox_lib wagon post menu in the same commit (no dead code), keeping the trade post prompt/detection.

## Plan

| Block | Touches | Clashes with |
|---|---|---|
| I1 jobs board renders locked offers greyed "Needs tier N", no accept button; flip `showLockedOffers` | fh_ui html/screens (jobs board), fixtures + spec, fh_quests config.lua (1 line) + README | I3 on fh_ui fixtures.lua (rebase at merge) |
| I2 places.lua trapper blips + `/where trapper` list every enabled-region trapper (from fh_hunting trappers data, fallback to cfg.Trapper) | fh_ui shared/places.lua (+ whatever reads it), spec | none |
| I3 `wagonyard` screen (buy tiers with price/locked/owned, call owned tier, stow) replacing the fh_cargo ox_lib wagon post menu | fh_ui relay/fixtures/screens/index/README, fh_cargo server ui handlers + client prompt swap + README, OWNER-TESTS | I1 on fixtures.lua |

All three run in parallel (the only shared file, fixtures.lua, is an append-only rebase at merge). Merge order: whichever passes first; the later one rebases.

## In flight
- Dispatched 2026-11-25: I1 rn-9976c4397910 (Sonnet), I2 rn-d033b04c639e (Gemini), I3 rn-b882b630ce60 (Gemini). Reviews: I1 -> Review - Gemini; I2/I3 -> Review - Sonnet.
- Roa4 OK for I3 with conditions (relayed to rn-b882b630ce60): only {action,tier} from client; post via fh_trade:nearestPost, buy via FhCargoPost.buy->buyWagon; error codes unchanged; cargo_post_spec green + guard specs; update Roads OWNER-TESTS 41/43/44/46 in same commit; grep proof if menu_action removed. Sign-off on diff + review line.
- Hun2 OK for I2 (relayed to rn-d033b04c639e): FhRegions.isEnabled filter; any read-only export in a NEW fh_hunting server file (hunting-lows edits main.lua PlayerLoaded + legendaries.lua). Show before merge.
- I3 built 19c28d8 (worker archived at 151k after finishing; Roa4 conditions addressed in its note). Review - Sonnet rn-f2a34834910a.
- I1 fe63ba4+1eb5921 (reason labels mapped, unknown never echoed); Review - Gemini rn-51b442491f83. I2 912561b (getTrappers export in new fh_hunting/server/trappers_export.lua + fh:ui:trappers callback); Review - Sonnet rn-9eb0005f28f3.
- I3 PASS 0/0/2 (rn-f2a34834910a), Roa4 OK + wants chat fallback fold -> rn-16114153e1d4 (rebase on main too). I1 FAIL 1/1/2 (spec after T.finish, compounded opacity) -> fix rn-15d062bf7c93. I2 PASS 0/0/3 (rn-9eb0005f28f3), awaiting Hun2 OK.
- I1 fix a007399 -> re-review Gemini rn-1d8c63c67e1a. I3 rebased 24ae103 + fold 386e04c -> delta review Sonnet rn-111e62251d86. I2 Hun2 OK, rebased 05fac44 (=), gates 148/2778/0, slot asked; lows -> TASKS ui-i2-lows.
- I1 PASS 0/0/0 a007399 (rn-1d8c63c67e1a), rebased 9ad8433. I3 delta PASS 0/0/0 386e04c (rn-111e62251d86), rebased 4fcb5d6. Both slot-asked behind I2; Roa4 sent diff+review line; Que4 FYI.
- I2 MERGED (a0e2c54 + docs; PASS 0/0/3 rn-9eb0005f28f3, Hun2 OK). Gates 148/2791/0, G5 0 unknown, contracts 0, syntax 277/0. Lows -> TASKS ui-i2-lows.
