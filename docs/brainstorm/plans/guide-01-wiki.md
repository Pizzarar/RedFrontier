# guide-01 · Player wiki (docs/wiki)

Lane: @guide · Lead: Guide Lead (spawned 2026-11-23) · Status: handed off

## Idea
A player-facing wiki in `docs/wiki/` that teaches every system, built only from what is merged on local main. Later an in-game journal (@ui) and an optional tutorial (fh_tutorial) reuse it.

## Owner's words (verbatim, via Overlord 2026-11-23)
"wiki + quests (repeatable jobs board + one-time family questlines) + optional intro tutorial."
Overlord: "Guide: the wiki can start now from what's already on main. The tutorial lands LAST, after every other lane is playtest-ready, and it uses the fh_quests contract from @quests."

## Decided
- Source of truth = lane READMEs (`server/resources/[fh]/*/README.md`), configs and shared rule files on main. Never invent a number, key or price; if the code doesn't say it, the page doesn't either.
- Controls: there is no central keymap. Keys live per resource (e.g. `fh_death/client/main.lua:5` and `fh_homestead/client/main.lua:5` `INPUT_CONTEXT = 0xCEFD9220 -- E (unverified)`, `fh_inventory` `Config.Keys.Open`). The controls page lists each key with its source path and carries the code's "(unverified)" tag until a spike verdict clears it.
- Every page ends with a `Sources:` list of repo paths. That is what keeps it honest across 11 lanes.
- Plain markdown, player voice, short pages. No dev internals (event names, DB tables) on player pages; a separate `docs/wiki/dev/events.md` may list public events (e.g. @hunting's fh:hunting:* list from plans/hunting-01-l8.md) for @quests/tutorial use.
- Checked for existing primitives: `vs --help` (no docs/wiki tooling), `tools/` (only run-specs.py and server tools), skills (none for wiki). The checker in W2 is new, small, and lives in tools/.
- Overlord rules apply: vs worktree units only, rebase + `python tools/run-specs.py` green before merging to local main, one lane at a time, log the hash, no push. In-game checks (none expected for docs) go in a `## Guide` section of OWNER-TESTS.md.

## Plan
| Block | Touches | Clashes with | Kind |
|---|---|---|---|
| W1 wiki pages | docs/wiki/** (new) | nothing (new dir) | Root cause |
| W2 wiki checker | tools/check-wiki.py (new) | nothing; does NOT edit run-specs.py | Root cause |
| W3 refresh pass | docs/wiki/** | lanes merging to main (read-only on their files) | Root cause |

W1 — `docs/wiki/README.md` (index), `getting-started.md`, `controls.md`, `systems/<resource>.md` for each fh_* resource on main (core, inventory, buffs, economy, zones, death, homestead, hunting, ui), `items.md`, `regions.md`, `tips.md`, `dev/events.md`. Pages for lanes not yet merged (survival, crafting, roads, progression, quests) are stubs: one line "Coming with @<lane>" and no invented content.
Done-check: every fh_* resource on main has a page; every page has Sources; reviewer spot-checks 10 facts against code.

W2 — `python tools/check-wiki.py`: every `Sources:` path exists, every page is linked from the index, no dead relative links, exit 0 = green. Run it in the W1/W3 review.
Done-check: green on W1 output; fails when a Sources path is renamed (show the failing run).

W3 — when a lane logs `decision <lane> playtest-ready <hash>`, fill its stub page from that hash. Repeat per lane. Log `decision guide wiki-refreshed <lane> <hash>`.
Done-check: no stubs left once all feature lanes are playtest-ready; checker green.

Order: W1 → W2 → merge → W3 rolling.

## Resume after forge freeze (2026-11-23)
State: W1 origin/guide-w1 cfcc4e1 (21 pages), W2 origin/guide-w2 5d80476 (check-wiki.py). Both 1 ahead / 9 behind main fa94127; the 9 main commits touch no docs/wiki or tools paths, so the rebase should be clean. Review never ran.
R1 Review W1+W2 (one reviewer): 10+ wiki facts checked against code on main (file:line), leak check (no owner name, no emails), check-wiki green on W1 tree, rename-fails demo (rename one Sources path -> red, restore -> green). FAIL -> fix worker on the same branch, re-review.
R2 Rebase both on main, run specs, merge W1 then W2 (one lane merges at a time: take the merge slot, no push). Log `decision guide wiki-merged <hash>`.
R3 = W3 as above; no lane is playtest-ready yet (0 in log), so the lead idles after R2 until one is.

## Open
- In-game journal screen: ask @ui once the wiki settles (their NUI, our content).
- guide-02 fh_tutorial: written after @quests publishes the fh_quests API; lands last.

## Out of scope
fh_tutorial code, NUI work, editing any other lane's files or READMEs (requests go to that lane's Buddy), pushing.

Credits: no plugin/parity inspiration; nothing to add to CREDITS.md.
