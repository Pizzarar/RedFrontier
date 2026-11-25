# Plan roads-02 · M7 roads slice: rep unlocks wagon tiers + T2 freight

Lane: @roads · Lead: Roa3 (`vs who lead`) · Buddy: Roads · 2026-11-24

## Idea
Spec §6 M7: "Regional rep unlocks wagon tier + T2 contracts". fh_progression (on main) already defines
unlock ids `wagon_t2` and `contracts_t2` (fh_progression/config.lua:9-10), but nothing consumes them:
`git grep canUnlock` hits only fh_fence and fh_hands. Roads wires the gates and adds the T2 freight content.

## Owner's words (verbatim)
"build everything autonomously, Aub tests only at the end." Overlord Red3 2026-11-24: "Keep your lane
working its goals: no parking without a real blocker … Buddy picks the next plan."

## Decided
- Gate primitive = `exports.fh_progression:canUnlock(src, unlock_id) -> ok, reason` (README:7). No new rep
  system and no new flag. Checked: fh_progression README, fh_fence/fh_hands usage (same pcall pattern),
  `vs --help` (no relevant primitive).
- Fail closed: if fh_progression is not started or canUnlock errors, T2/T3 wagons and T2 contracts are refused
  (`fh_locked`). T1 wagons and T1 contracts are always available. Soft dep: no `dependencies` entry.
- Needs `wagon_t3 = { region_id = 'heartlands', min_tier = 3 }` in fh_progression config. That's a request to
  @progression, not an edit in their resource. Until it lands, R8 maps t3 to `wagon_t3` and refuses with
  `unknown_unlock`, which is correct fail-closed behaviour (Root cause, no workaround).
- T2 contracts: same fh_quests `freight` job type, with an offer `tier` field. T2 = larger qty (needs a t2+
  wagon's slots), longer route, higher pay; deadline scales with distance. Offers list T2 with `locked = true`
  when gated (board shows them; accept refuses). Pay stays through the fh_quests engine.
- Supplies keep flat prices (roads-01 decision); no shortage feed in this plan.

## Plan
| Block | Touches | Clashes with | Kind |
|---|---|---|---|
| R8 wagon tier gate: `spawnWagon` (and any tier-upgrade path) checks canUnlock(`wagon_t2`/`wagon_t3`) for t2/t3; reason surfaced to player; specs with stubbed fh_progression (allowed / tier_too_low / not started / throws) | `[fh]/fh_cargo` server + shared rules, spec | none (fh_cargo is roads-only) | Root cause |
| R8r request to @progression: add `wagon_t3` unlock (heartlands, tier 3) | fh_progression/config.lua (their lane) | @progression | Root cause |
| R9 T2 freight: offer `tier`, T2 templates in fh_trade freight config, `accept` gates T2 on canUnlock(`contracts_t2`), checks the wagon tier fits qty, `locked` flag on gated offers; specs | `[fh]/fh_trade` shared/server freight, config, spec | supplies branch if still open (same resource: rebase) | Root cause |
| R10 seed `docs/lanes/roads/SPEC.md` + `TASKS.json` (`vs spec write --lane roads`, `vs task set`) from roads-01 + roads-02 | docs only | none | Root cause |
| R11 OWNER-TESTS `## Roads` card: add rep-gate steps (admin set rep → tier 2 → t2 wagon + T2 contract unlock; tier 1 refused) | OWNER-TESTS.md `## Roads` only | other lanes' sections (append-only) | Root cause |

Order: R8r sent first (Buddy sends now) → R8 ∥ R9 ∥ R10 → R11 last. Each: worktree unit, specs green on
`~/.venvs/rf/bin/python tools/run-specs.py`, Gemini review PASS, merge via the Red3 slot.

## Done-check
- Venv specs green incl. new gate specs; `git grep canUnlock` shows fh_cargo + fh_trade consumers.
- OWNER-TESTS `## Roads` has the rep-gate steps.
- `vs log decision "roads-02 playtest-ready <hash>"`.

## Out of scope
Ungated chase/ambush (waits on @spikes S2/S3 RESULT lines), off-road wheel break natives (in-game check),
supplies shortage pricing, new regions, @ui screens.

Credits: original design, no plugin parity.
