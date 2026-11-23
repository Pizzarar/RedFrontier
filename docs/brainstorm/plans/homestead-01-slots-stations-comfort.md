# Plan homestead-01 · build slots, stations, comfort (`fh_homestead`, lane @homestead)

## Idea
Grow the B6a seed (`fh_homestead`: 1 fixed plot, 1 chest, claim/unclaim) into lane L1: fixed plots with predefined
build slots, paid upgrades that spawn props at config coords, a station-slot API for @crafting, and a comfort score
that @survival reads and @hunting feeds.

## Owner words (verbatim)
- "L1 fh_homestead (ownership moves from @core after its B6a/B6d chest work): cabin/fence/prop placement on fixed plots,
  persistent storage, station-slot API (Crafting consumes it), comfort score (Survival + Hunting feed/read it). No
  world-object clearing: pick clear plots or fake with props. Spec: docs/FRONTIER_HOMESTEAD_SPEC.md. Owner: build
  everything autonomously, Aub tests only at the end. Use @core §4 APIs only (fh_core containers, fh_buffs, fh_economy,
  regions, events); contract changes = request to @core. Anything waiting on in-game spike results goes behind one
  config flag. Pure-Lua specs (tools/run-specs.py) + in-game test card in README. No push."
- Overlord integration rules: worktrees via `vs worktree create`; merge to local main only after review PASS, rebased on
  current main, `python tools/run-specs.py` all green, log the hash; one lane merges at a time (rebase again if main
  moves); fh_homestead now belongs to @homestead; in-game checks go in this lane's section of OWNER-TESTS.md (no
  separate test doc); no pushes; when playtest-ready log `decision homestead playtest-ready <hash>`.

## Decided
- Fixed plots only (spec §8). Default (owner didn't object): 4 plots, one per character (`fh_plots.citizenid UNIQUE` stays).
- Each plot config lists build slots: `cabin` (tiers 0-2), `fence` (0-1), `station_1..3`, `trophy_wall`, `chest_2..3`.
  Every slot unlocks something (pillar 3): cabin tier → extra chest slots + comfort; fence → larger safe radius + comfort;
  station → a typed station Crafting can bind; trophy wall → comfort from trophies.
- Build cost = money + materials, both server-side. Props = client-local, non-networked models drawn from server state
  (same as B6a chest); static props need no `requestSpawn`. Model names/coords unverified → behind ONE flag
  `FhHomesteadConfig.verifiedProps` (false = fallback models/positions known from B6a).
- Comfort = pure sum of per-slot points + trophy points (capped), cached server-side, export `getComfort(citizenid)`,
  event `fh:homestead:comfort_changed`. Homestead does NOT apply buffs; @survival reads comfort and calls fh_buffs.
- Primitives checked: fh_core exports (move/canFit/getWeight/snapshot/view/transferAll/registerContainer/open/addItem/
  clearContainer/deleteContainer/registerItems/requestSpawn), fh_economy `pay`/`rep`, fh_buffs `apply`/`get`, `vs --help`.
  Gaps: **no charge (debit) in fh_economy** (`pay` = AddMoney only) and **no remove-item** in the fh_core container API.

## Blocks
| Block | Touches | Clashes with | Kind |
|---|---|---|---|
| H0 contract request to @core: `fh_economy.charge(src, amount, reason, region_id)` (RemoveMoney + ledger `kind='charge'`) and `fh_core.removeItem(ref, item, amount)` | fh_economy, fh_core (by @core) | @core, @progression | Root cause (request, not built here) |
| H1 slot model + pure rules: config slots for 4 plots, `shared/build_rules.lua` (canBuild, cost, tier order, owner-only), migration `00xx_homestead_slots.sql` (`fh_plot_slots(plot_id, slot_id, tier)`), specs | fh_homestead/config.lua, shared/, server/migrations, spec/ | migration numbering (other lanes) | Root cause |
| H2 build flow + props: `/fh_build <slot>` (server checks via H1, charges via H0), persistence load, client draws props for all built slots on join/claim/build; extra chests registered as fh_core `chest` containers | fh_homestead server/client | H0 must be on main | Root cause |
| H3 station-slot API: exports `getStations(citizenid)`, `stationAt(coords)` → {plot_id, slot_id, station_type}, `isNearStation(src, type)`; event `fh:homestead:station_built` | fh_homestead server | @crafting consumes | Root cause |
| H4 comfort: `shared/comfort.lua` pure calc, exports `getComfort`, `addTrophy(citizenid, trophy_id, points)` (Hunting calls), event `fh:homestead:comfort_changed` | fh_homestead | @survival reads, @hunting feeds | Root cause |
| H5 README (events/exports/config/tables) + homestead section in OWNER-TESTS.md; spill-on-unclaim gap stays listed in README Open | README, OWNER-TESTS.md | other lanes' OWNER-TESTS sections | Root cause |

Workaround allowed only if H0 is slow: H1/H3/H4 do not need it. H2 waits for H0; do not debit money or items any other way.

## Order + done-check
H0 sent at handoff → H1 → (H3 ∥ H4) → H2 once H0 on main → H5. Each block: review PASS, rebased on main, `python tools/run-specs.py` all green, merge, log hash.
Lane done when all blocks are merged and `vs log decision "homestead playtest-ready <hash>"` is posted.

## Lead
Spawned fresh Homestead lead (Lead - Claude profile); lane had none.

## Out of scope
Free placement, world-object clearing, AI raids (safe zone), applying buffs (Survival), crafting recipes (Crafting),
hired hands (L9), networked props, spill-to-drop-bag on unclaim (Open), pushing.
