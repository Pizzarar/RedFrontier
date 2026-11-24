# quests-02 · Content ladder (idea-839, goes with idea-498)

## Idea
Fill fh_quests out: 8 contract types across all 15 regions, plus 2 new family questlines. The engine stays as it is.

## Words (verbatim)
- Owner (via hub): "more"
- Que2 leans (2026-11-24): "Engine needs no change; each new contract type = a registerJobType in shared/jobtypes.lua + DATA + specs. Existing: hunt_request (=pelt order), camp_clear, bounty, freight (@roads). New: supply run, escort, survey/stake, rescue." / "Region coverage reads FhRegions/world data ... offers must skip disabled regions automatically (no per-region hardcoding)." / "Families: 2 new (states without one), same shape as Hale/Marrow/Whitlock, givers via fh_ui dialogue (idea-722). Original names only." / "Blocks with a parallel table; specs-first. Review - Sonnet while Gemini is down."

## Decided
- **Primitives checked:** `registerJobType` (server/jobtypes.lua); `M.BUILDERS` + `M.DATA` (shared/jobtypes.lua:16,81); the bounty pattern (quest-owned local event `fh:quests:bounty_down` + fh_core `requestSpawn`, shared/jobtypes.lua:13); `FhRegions.isEnabled` (fh_core/shared/regions.lua:721); the intake whitelist `engine.INTAKE` (shared/engine.lua:24); fh_ui giver dialogue (idea-722, 53bf1c7); emitters on main (`grep TriggerEvent('fh:`). Nothing new is needed in vs or skills.
- **Correction to "no engine change":** each type's own events already enter through `Q.eventSet()` (job-type events). Supply run reuses an existing cross-resource event, so `fh:trade:sold` gets one line in `engine.INTAKE`. That is the whole engine diff.
- **Region gate bug (found while planning):** server/api.lua:160,174 check only that a region *exists* (`regions()[id]`). They never check that it is enabled. So once DATA covers all 15 regions, offers would show in disabled ones. C0 fixes this with `FhRegions.isEnabled`. Enabled today: heartlands, scarlett_meadows, bayou_nwa, great_plains. world-02 G turns on the rest, with no edits in quests.
- **No cross-lane asks.** The 4 new types advance on events that exist today or on quest-owned local events, built the same way as the bounty watcher.

| Type | Advances on | Emitter | Status |
|---|---|---|---|
| hunt_request | `fh:hunting:pelt_sold` (animal/size/quality/region) | fh_hunting sell.lua:157 | exists |
| camp_clear | `fh:zones:camp_cleared` (participants) | fh_zones (b63a340) | exists |
| bounty | `fh:quests:bounty_down` | fh_quests watcher | exists |
| freight | @roads `registerJobType` (fh_trade/server/freight.lua) | fh_trade | exists |
| supply_run | `fh:trade:sold` `{src, region, post, item, amount}` (key is `region`, not `region_id`; intake resolves citizenid from src) | fh_trade server/main.lua:144 | new type, existing event |
| survey | `fh:quests:point_reached` `{citizenid, offer_key, region_id, point}` | new fh_quests server reach-watcher | new |
| escort | `fh:quests:escort_arrived`; fails on `fh:quests:escort_lost` (ped dead/despawned) | fh_quests watcher + `requestSpawn` + client follow task | new |
| rescue | `fh:quests:captive_freed` (captive reached after the linked camp clears) | fh_quests watcher + `requestSpawn` at an fh_zones camp | new |

- **Families:** all 3 existing families are in heartlands (new_hanover). The 2 new ones go to **Lemoyne** (scarlett_meadows or bayou_nwa) and **West Elizabeth** (great_plains). Both regions are enabled today. Same file shape as `data/families/hale.lua`, givers through fh_ui dialogue. Names and story are original; the builder picks them, with no real-world, film or game names.
- Original content throughout. No plugin or parity inspiration, so no Credits line is needed.
- Rules: specs-first; run specs only with `~/.venvs/rf/bin/python tools/run-specs.py`. Review is Sonnet while Gemini is down. No push; one lane merges at a time; commits to main only in a merge slot. Never write the owner's name.

## Plan
| Block | Touches | Clashes with | Kind |
|---|---|---|---|
| C0 Split + gate: move `M.DATA` to `data/regions/<region_id>.lua` (one file per region, all 15, empty tables OK), move each builder to `shared/jobtypes/<type>.lua` registering into BUILDERS; gate offers and accept on `FhRegions.isEnabled` (api.lua:160,174 + offers). Spec: a disabled region with DATA yields 0 offers; flipping `enabled` shows them with no code change; every FhRegions id has a data file | shared/jobtypes.lua, server/api.lua, fxmanifest, new data/regions/, shared/jobtypes/ | everything below (do first) | Root cause |
| C1 supply_run: builder + DATA schema `{post, item, amount, money, rep}`; `fh:trade:sold` added to engine.INTAKE; spec on the real payload (src→citizenid, `region` key, wrong post/item/amount) | shared/jobtypes/supply_run.lua, engine.lua (1 line) | none after C0 | Root cause |
| C2 survey + shared reach-watcher: `server/watch.lua` polls only players holding a survey/escort/rescue job (coarse tick, server coords), emits `fh:quests:point_reached`. Spec: pure distance/visit-order logic | shared/jobtypes/survey.lua, server/watch.lua (new), shared/watch_rules.lua (new) | C3, C4 reuse watch | Root cause |
| C3 escort: `requestSpawn` escortee, client follow task, arrival → `escort_arrived`, death/despawn → `escort_lost` → job failed | shared/jobtypes/escort.lua, server/watch.lua, client/escort.lua | C4 (watch.lua): run C3 and C4 in sequence or keep separate sections | Root cause |
| C4 rescue: captive spawned at an fh_zones camp id; freed when the holder reaches it after that camp's `camp_cleared` lists them | shared/jobtypes/rescue.lua, server/watch.lua | C3 | Root cause |
| C5 content fill: DATA for all 8 types × 15 regions (camps from fh_zones/config.lua ids; coords marked `TODO-verify-in-game`). Spec: every enabled region offers ≥1 of each type it has data for; ids are unique | data/regions/*.lua | C1–C4 schemas (start after their schema lands, or per-region files in parallel) | Root cause |
| C6 two family questlines (Lemoyne, West Elizabeth): data files + givers.lua entries + fh_ui dialogue lines; steps use only intake events (e.g. supply_run/pelt_sold/camp_cleared/talk) | data/families/<new>.lua ×2, shared/givers.lua, client/givers.lua | none (parallel with C1–C5) | Root cause |
| C7 README job-type table + OWNER-TESTS quests section for the 4 new types + 2 families | fh_quests/README.md, OWNER-TESTS.md | other lanes' OWNER-TESTS sections: rebase carefully | Root cause |

Order: C0 → (C1 ∥ C2 ∥ C6) → C3 → C4 → C5 → C7. C5 can start per region once C1/C2 schemas are fixed.
Done-check per block: venv specs green, review PASS (Sonnet), merged in a slot, hash logged.
**Done when:** 8 types registered; a disabled region shows 0 offers and enabled ones show the full set; 2 new families playable through fh_ui dialogue; OWNER-TESTS updated; `decision quests content-ladder-ready <hash>`.

## Open
- The escort client follow task (RedM native behaviour) is the riskiest piece. If it's flaky in-game, fall back to "meet the escortee at the destination". Decide after the owner's playtest, not now.
- Region coords stay `TODO-verify-in-game` until world-02 G verifies them.

## Out of scope
- Engine/match changes beyond the one INTAKE line. New UI screens (the board and journal already exist through @ui). Reputation or economy balance passes. @roads freight internals.

## Lead
Que2 (rn-97a2281b22df).
