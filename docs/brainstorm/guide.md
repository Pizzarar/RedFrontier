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

## Open
- guide-02 design: no intake event yet for chest/board/cargo/gunsmith/fence. Lean: chained short tutorial quests; steps use real events where they exist (homestead:claimed, hunting:pelt_skinned/sold), talk steps elsewhere, swapped as additive whitelist events land. Flag to @quests: README example prereq {'tutorial_intro'} on family_hale_1 conflicts with never-blocking.
- In-game journal: ask @ui after wiki settles.
- guide-02 fh_tutorial: write after @quests publishes fh_quests API; lands last.
- (orig) Teach the player. (A) Wiki: docs/wiki/ markdown covering every system, default controls (read from lane configs, not guessed), items, regions, tips; source of truth = lane READMEs/configs; later an in-game journal screen via @ui. (C) Optional intro tutorial (fh_tutorial, built on @quests' engine): over the first 1-2 hours, nudges the player to each system in turn (claim plot, chest, hunting spot, contract board, cargo run, gunsmith, fence...), skippable, never blocking. Wiki can start now; the tutorial script follows the engine API. Spec: docs/FRONTIER_HOMESTEAD_SPEC.md (non-goal 'story missions' amended 2026-11-23 by Aub: optional one-time questlines + tutorial are IN; text dialogue only, no cutscenes/VO). Follow the Overlord integration rules in docs/brainstorm/redfrontier.md Decided. Use only other lanes' exports/events; requests go to their Buddy. No push.

## In flight
- PASS W3 wiki-refreshed on main 93e9014: survival, progression, crafting, quests, roads, homestead, hunting, ui pages + shared pages (check-wiki 21/0, specs 71/1382/0). Remaining: core page refresh (E2 merged), journal ask to @ui, guide-02 tutorial.
- PASS wiki-merged: W1 18cc57b + W2 3ef1455 on main (21 pages, check-wiki green, specs 36/697/0). R3 = W3 per-lane refresh when a lane logs playtest-ready; journal ask to @ui now unblocked.
- (history) Freeze lifted 15:11Z (C2 cutover). Resume section added to plans/guide-01-wiki.md: R1 review W1 cfcc4e1 + W2 5d80476 -> R2 rebase (clean, main moved docs-only) -> merge W1 then W2, no push, one lane at a time -> R3 = W3 when lanes go playtest-ready. Handed to Overlord to spawn Guide Lead.
- Journal: asking @ui waits until wiki-merged.
