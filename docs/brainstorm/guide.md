# Brainstorm Summary · GUIDE (`guide`)

> Rolling team brief (< ~5k tokens). Updated on every decision.

## Who's here
- Brainstorm: Guide
- Lead: none
- Workers: 0

## Done when
- docs/wiki covers every fh_* system on main with Sources, checker green, no stubs once all lanes are playtest-ready.
- fh_tutorial (guide-02) merged last, on the fh_quests API; skippable, never blocking.
- Logged 'decision guide playtest-ready <hash>'.

## Decided
- 2026-11-23: plan guide-01-wiki (docs/brainstorm/plans/guide-01-wiki.md): W1 pages, W2 tools/check-wiki.py, W3 refresh per lane as each goes playtest-ready. Source of truth = code on main; every page has Sources; controls listed per resource with '(unverified)' kept (no central keymap exists).
- Hunting events for tutorial/wiki: fh:hunting:pelt_skinned/pelt_sold/clue_found/legendary_spawned/chain_complete (payloads in plans/hunting-01-l8.md).

## Open
- In-game journal: ask @ui after wiki settles.
- guide-02 fh_tutorial: write after @quests publishes fh_quests API; lands last.
- (orig) Teach the player. (A) Wiki: docs/wiki/ markdown covering every system, default controls (read from lane configs, not guessed), items, regions, tips; source of truth = lane READMEs/configs; later an in-game journal screen via @ui. (C) Optional intro tutorial (fh_tutorial, built on @quests' engine): over the first 1-2 hours, nudges the player to each system in turn (claim plot, chest, hunting spot, contract board, cargo run, gunsmith, fence...), skippable, never blocking. Wiki can start now; the tutorial script follows the engine API. Spec: docs/FRONTIER_HOMESTEAD_SPEC.md (non-goal 'story missions' amended 2026-11-23 by Aub: optional one-time questlines + tutorial are IN; text dialogue only, no cutscenes/VO). Follow the Overlord integration rules in docs/brainstorm/redfrontier.md Decided. Use only other lanes' exports/events; requests go to their Buddy. No push.

## In flight
- PARKED (forge freeze 2026-11-23): guide-w1 cfcc4e1 (21 pages) + guide-w2 5d80476 (check-wiki.py), both committed, unmerged, review NOT run (Guide3 archived before start; worktrees clean, lead drained). Resume after cutover: run review (10+ facts vs code, leak check, rename-fails demo) -> rebase -> run-specs -> merge w1 then w2 -> log wiki-merged.
