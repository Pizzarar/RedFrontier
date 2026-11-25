# Plan animations-01 · core action animations (`@animations`)

## Idea
Almost nothing in the game animates. Today only `fh_inventory/client/main.lua:177` plays a clip (generic `use_quick`).
Skinning and herb picking are frozen progress bars. Eating, crafting, cooking, chests, trough and garden have no
animation at all. Add one small client resource (`fh_anim`) that plays a named animation for an action key. Wire
it into each action with a one-line call. Everything is behind a config flag and gated on an in-game probe card
that confirms which base-game anims actually play in RedM.

## Ask (verbatim)
- Owner 2026-11-25: "almost no animations in game; add them in parallel with other lanes" / "just run the animations in parallel".
- Red4: "P0 in-game probe card (S7 pattern, with @spikes) listing base-game anim dicts/scenarios to confirm in RedM;
  then client-only, config-flagged anim helper + per-resource blocks (fh_hunting skin, fh_crafting gather, eat/drink,
  cooking, chests, bench, trough, garden) using lib.progressBar anim/scenario fields. Parallel table + stakes."

## Decided
- **Cosmetic, not blocking (Buddy lean, OK'd by Red4).** For instant actions the server result stays the same and is
  not delayed. The animation plays alongside it. No new wait states go into other lanes' flows.
- **Do not use ox_lib `anim.scenario`.** `ox_lib/resource/interface/client/progress.lua:92` passes the scenario name
  as a string to `TaskStartScenarioInPlace`. rsg-core hashes it first
  (`rsg-core/client/progress.lua:45` `TaskStartScenarioInPlaceHash(ped, joaat(...))`), so the string form is
  suspected not to play in RedM. P0 tests both forms. `fh_anim` starts scenarios itself via the hash and clears
  them when done. Dict/clip entries *may* go through progressBar's `anim` field (`TaskPlayAnim`, line 88).
- **Most actions are server-side.** Eat/drink is a rsg-core usable (`fh_survival/server/actions.lua:45` onUse).
  Bench/cook is the `fh_craft` command (`fh_crafting/server/craft.lua:72`). Chest, trough and garden are server
  handlers. So "client-only" means the *anim code* is client-only. Server sites add one fire-and-forget line,
  `TriggerClientEvent('fh:anim:play', src, '<key>')`, on the success path only. If `fh_anim` is not running, no
  handler exists and it is a no-op.
- **New resource `[fh]/fh_anim`, not inside fh_core.** fh_core is touched by many lanes; a new resource clashes with
  nothing but one `ensure` line in `server/server.cfg`.
- **Safety rules inside the helper:**
  - Skip if the ped is mounted, in a vehicle, swimming, dead, ragdolling or already in a scenario.
  - Instant actions use upper-body dict clips only (flag 31/49), so the player can still move.
  - Scenarios are used only at progress-bar sites, which already set `disable.move`.
  - `stop()` = `ClearPedTasks` only if *our* anim is still the active one.
- **Flag:** `Config.Enabled = false` until the P0 RESULT. Table entries ship as **candidate, unproven** and are
  replaced by P0-confirmed names in A7, which also flips the default to true.
- **Primitives checked:**
  - ox_lib `lib.progressBar` anim field (above).
  - `lib.requestAnimDict` / `lib.playAnim` imports (`ox_lib/imports/playAnim/client.lua`): the helper uses these.
  - rsg-core `client/progress.lua` (hash scenarios).
  - The existing `rsg-inventory:client:giveAnim` (`fh_inventory/client/main.lua:177`): stays as is, but its clip is
    a P0 baseline row.
  - `vs --help`: no command needed.
  - No new convar, migration or vs rule. Not plugin-inspired, so no attribution line.

## API (A1)
- `exports.fh_anim:play(key)`: instant cosmetic clip, auto-ends (duration from table).
- `exports.fh_anim:start(key)` / `exports.fh_anim:stop(key)`: for progress-bar sites. Wrap the existing
  `pcall(lib.progressBar, …)`: `start` before it, `stop` after it, whether it completes, cancels or throws.
- `RegisterNetEvent('fh:anim:play', key)` → `play(key)`.
- `shared/anims.lua` table: `key → { dict, clip, flag, ms }` or `{ scenario, ms }`. Keys: skin, gather, eat, drink,
  craft, cook, chest_open, trough, plant, harvest, refill, wash.
- Pure lookup and guard logic go in a shared module with a spec (`tools/run-specs.py`, venv). Unknown key or flag off
  → returns false, no error.

## Plan
| Block | Touches | Clashes with | Kind | Stakes |
|---|---|---|---|---|
| A0 probe `spk_anim` (S8) + card | new `server/resources/[spikes]/spk_anim/*`, append card to `[spikes]/TEST-CARDS.md` | Spikes lead's other cards in TEST-CARDS.md (append only) | Root cause | low |
| A1 `fh_anim` resource + spec | new `server/resources/[fh]/fh_anim/*`, `server/server.cfg` (+1 ensure line), new spec | server.cfg (any lane adding an ensure) | Root cause | normal |
| A2 skin | `fh_hunting/client/main.lua` ~L114 (start/stop around progressBar) | @hunting: queue empty (brief 2026-11-25) | Root cause | low |
| A3 gather + bench/cook | `fh_crafting/client/gather.lua:22`, `fh_crafting/server/craft.lua` (success path of `fh_craft`, key by station type) | @spikes S6 spk_herb: crafting wires the herb cue into gather.lua after GO; check the branch first | Root cause | low |
| A4 eat/drink/refill/wash | `fh_survival/server/actions.lua` (onUse success after consume; refill L134; wash L148) | @survival: queue empty (brief) | Root cause | low |
| A5 chest/trough/garden | `fh_homestead/server/main.lua:717`, `server/trough.lua:293`, `server/garden.lua` fh_plant/fh_harvest success paths | @homestead: no unit running (brief) | Root cause | low |
| A6 review (other provider) per block | read-only | — | — | — |
| A7 fill table from P0 RESULT + flip `Enabled=true` + owner test steps | `fh_anim/shared/anims.lua`, `fh_anim/config.lua`, owner test doc | none | Root cause | low |

**Order:**
- A0 ∥ A1 in parallel. A0 goes to the Spikes lead `rn-3095b3717f66` (spikes pattern); A1 goes to the animations lead.
- After A1 merges: A2 ∥ A3 ∥ A4 ∥ A5, one worker each, each its own worktree and branch.
- After Aub returns the A0 RESULT: A7.
- Merges go through the merge slot as usual.

**A0 card spec (`/spk_anim <n>`, ≤5 min):**
- Each row plays on Aub's ped for 3s and Aub marks Y/N per row.
- Every scenario row is tried both ways: `TaskStartScenarioInPlaceHash(joaat(name))` and ox_lib string
  `lib.progressBar{anim={scenario=name}}`.
- Candidate rows. Worker confirms the names from rsg resources or known RDR3 lists and marks each one
  **candidate, unproven**:
  - skin: `WORLD_HUMAN_CROUCH_INSPECT`
  - gather: `WORLD_HUMAN_CROUCH_INSPECT` (alt: a pick-plant dict)
  - eat: `mech_inventory@eating@...` (bite clip)
  - drink: `mech_inventory@drinking@...`
  - craft/bench: `WORLD_HUMAN_HAMMER_TABLE` / a hammer dict
  - cook: `WORLD_HUMAN_STIR_POT` / crouch at fire
  - chest_open: crouch / reach-and-search dict
  - trough: pour/bucket
  - plant / harvest: `WORLD_HUMAN_FARMER_WEEDING` / crouch dig
  - refill/wash: crouch at water
  - baseline: `mech_inventory@item@fallbacks@tonic_potent@offhand` `use_quick` (known working)
- Template RESULT line per row:
  - `row | name | hash form Y/N | string form Y/N | looks right Y/N | note`.
  - RESULT goes to the animations lead and Buddy.

**Done-check per block:**
- Every block: venv specs green (`~/.venvs/rf/bin/python tools/run-specs.py`), load-manifests 0 unknown, contracts 0
  findings, review PASS by the other provider.
- A2–A5:
  - Diff is only the start/stop/TriggerClientEvent lines, plus nothing else. Lesson: compare line counts vs the base.
  - With `fh_anim` stopped, the action still works (owner-test step).
- A7: owner test steps for each key.

## Builders
- No DeepSeek. Normal blocks get plain Implement (Sonnet/Gemini A/B, unpinned). Review goes to the other provider.
- Lesson for workers: after `vs worktree create`, run `git merge --ff-only origin/main` before step 0. No git writes
  in the main checkout.

## Lead
Red4 spawns the @animations lane lead. A0 is delegated to the Spikes lead `rn-3095b3717f66`.

## Out of scope
- Props in hand (bowls, knives): later plan, after P0.
- Animations for wagons, fence, tailor, death, emotes / `/e` menu.
- Changing any action's timing or outcome.
- Editing ox_lib's scenario bug upstream (we work around it in `fh_anim`). A follow-up is only worth it if P0 shows
  the string form works; if it does, simplify the helper to use progressBar fields directly.
