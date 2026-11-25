# Brainstorm Summary · GUIDE (`guide`)

> Rolling team brief (< ~5k tokens). Updated on every decision.

## Who's here
- Brainstorm: Guide
- Lead: Guide lead · wiki W1/W2 merge
- Workers: 0

## Done when
- docs/wiki covers every fh_* system on main with Sources, checker green, no stubs once all lanes are playtest-ready.
- fh_tutorial (guide-02) merged last, on the fh_quests API; skippable, never blocking.
- Logged 'decision guide playtest-ready <hash>'.

## Decided
- 2026-11-23: plan guide-01-wiki (docs/brainstorm/plans/guide-01-wiki.md): W1 pages, W2 tools/check-wiki.py, W3 refresh per lane as each goes playtest-ready. Source of truth = code on main; every page has Sources; controls listed per resource with '(unverified)' kept (no central keymap exists).
- Hunting events for tutorial/wiki: fh:hunting:pelt_skinned/pelt_sold/clue_found/legendary_spawned/chain_complete (payloads in plans/hunting-01-l8.md).

- 2026-11-23: fh_quests contract = README on quests-q1 d277f55 (Q1 PASS, not on main yet). Tutorial = registerQuest kind='tutorial'; steps advance only on intake whitelist + fh:quests:talked. Exports need Q2 (server) before any code runs.

- 2026-11-24: fh_tutorial already on main (f17d3ce, ff783fe; 8 steps, no rewards, client checks -> talk). Plan guide-02 (plans/guide-02-tutorial-gaps.md): T1 add stash/gunsmith/cargo/fence steps; T2 Field Guide content file for an @ui screen (quest journal already exists in fh_ui). Handed to Guide lead rn-2ab38ea7f111.

## Open
- T2 waits on @ui reply to idea-849 (Field Guide screen schema).
- Wiki coverage gaps (fh_alife, fh_hands, fh_gunsmith, fh_fence pages): lead's W3 round 2.

## In flight
- guide-02 T1 (Guide lead) || W3 round 2 (core + coverage gaps). Then T2 after @ui schema.
- PASS wiki W1/W2/W3 merged (main 415a736), playtest-ready logged.
