# guide-02 · fh_tutorial scope gaps + Field Guide ask

## Idea
fh_tutorial is already on main (f17d3ce, ff783fe): 8 steps (greeting, inventory, eat_drink, claim_plot, trade_post,
hunt, jobs, family). The SPEC list of stops is not fully covered yet. Close the gaps with the same step patterns the
resource already uses, and narrow the old "in-game journal" Open item to what is actually missing.

## Owner's words (verbatim, original lane brief)
"Optional intro tutorial (fh_tutorial, built on @quests' engine): over the first 1-2 hours, nudges the player to each
system in turn (claim plot, chest, hunting spot, contract board, cargo run, gunsmith, fence...), skippable, never
blocking." / "later an in-game journal screen via @ui."

## Scope check (SPEC stop -> main today)
| Stop | On main | Gap |
|---|---|---|
| claim plot | `claim_plot` (fh:homestead:claimed) | — |
| chest | — | **T1 `stash`** |
| hunting spot | `hunt` (fh:hunting:pelt_sold) | — |
| contract board | `jobs` (fh:ui:open screen jobs) | — |
| cargo run | — | **T1 `cargo`** |
| gunsmith | — | **T1 `gunsmith`** |
| fence | — | **T1 `fence`** |
| journal screen | fh_ui `journal` screen exists (owner quests, `/journal`, fh_ui/README.md:103) = quest log | help/wiki content in game still missing -> **T2** |

## Decided
- Same mechanics as the existing steps (fh_tutorial/README.md "How the non-event steps advance"): real intake event
  where one exists; otherwise fh_tutorial's server calls `exports.fh_quests:talk(src, '<synthetic npc>')` on a signal.
  `talk` only advances the step that expects that npc, and the tutorial pays no rewards (shared/tutorial.lua:115),
  so a forged client check can skip at most a tutorial prompt. That's why client checks count as Root cause here, not a workaround.
- Signals (worker verifies each one in code and cites file:line, no guessing):
  - `stash`: homestead stash/chest open (client check, same as `inventory`; find the stash open path in fh_homestead).
  - `cargo`: server event `fh:cargo:wagon_spawned` (fh_cargo); fh_tutorial listens and calls talk. If the payload has
    no src/citizenid, fall back to a client check and queue a request to the @roads Buddy for the field.
  - `gunsmith`: gunsmith menu open (fh_gunsmith; find its open event/screen).
  - `fence`: client `fh:ui:open` with `screen = 'fence'` (fh_fence/client/main.lua:17), same as `jobs`.
- Default order (config edit, `FhTutorialConfig.order`): greeting, inventory, eat_drink, claim_plot, **stash**,
  trade_post, hunt, **gunsmith**, jobs, **cargo**, **fence**, family. Fence goes late because it's the crime loop.
- Waypoints are copied from the owning lane's config with file:line (never invented), like the existing steps.
- Never blocking stays: no quest lists `tutorial_intro` as a prereq; `/tutorial skip` still works mid-run.
- Persistence by step id (ff783fe): adding ids must not reset or skip a player's current step. Spec it.
- T2: the quest journal already exists, so the ask to @ui is a read-only **Field Guide** screen. The content is a
  guide-owned data file, so @ui owns the screen and @guide owns the words.
- Primitives checked: fh_quests `talk` export + intake whitelist (fh_quests/shared/intake.lua), fh_tutorial
  client-check pattern, fh_ui screens list (fh_ui/README.md, `journal` exists), `vs inbox add` for the @ui ask.
  No new command or rule.
- Credits: no plugin/parity inspiration; nothing for CREDITS.md.

## Plan
| Block | Touches | Clashes with | Kind |
|---|---|---|---|
| T1 four new steps | server/resources/[fh]/fh_tutorial/**, spec/tutorial_spec.lua, docs/wiki/systems/tutorial.md | W3 round 2 only on tutorial.md (T1 owns that page) | Root cause |
| T2 Field Guide content | fh_tutorial/shared/field_guide.lua (new), tools/check-wiki.py (entry -> wiki page link check) | @ui's screen work (they read our file only) | Root cause; waits on @ui screen schema |

T1 done-check: specs green via `~/.venvs/rf/bin/python tools/run-specs.py` (new steps build; an old saved step id
still resolves after the reorder; unknown id dropped); check-wiki green; tutorial README + wiki table list all 12
steps with signal file:line; OWNER-TESTS `## Tutorial` gains the 4 in-game checks. Review: 10+ cited signals/waypoints
checked against code. Merge via the Red3 merge slot, no push.

T2 done-check (after @ui accepts the schema): one entry per system page in docs/wiki/systems (title, 3-5 lines,
controls, wiki path); check-wiki fails on a missing/dead entry; specs green.

Order: T1 now. T2 starts when @ui replies with the screen schema (@guide Buddy relays it).

Lead: Guide lead (rn-2ab38ea7f111), after or alongside W3 round 2 (no clash outside tutorial.md).

## Out of scope
The NUI screen itself (@ui), new events in other lanes (requests go to their Buddy), rewards for the tutorial, voice or
cutscenes, pushing.
