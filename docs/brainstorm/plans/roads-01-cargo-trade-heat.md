# Plan roads-01 · L6 Cargo/Wagons/Trade + L7 Heat/Ambush (@roads)

## Idea
Build spec §5 L6 (`fh_cargo`, `fh_trade`) and L7 (`fh_heat`) so M4 (haul a safe by wagon, fast-travel blocked, wheel break/repair, one freight contract, one shortage route) and M5 (faction heat, roadblock, lay-low decay, bounty payoff; mounted chase gated) are code-complete. Spec: docs/FRONTIER_HOMESTEAD_SPEC.md §3-§7.

## Owner's words (from the lane brief)
"build everything autonomously, Aub tests only at the end." "Use @core §4 APIs only (fh_core containers, fh_buffs, fh_economy, regions, events); contract changes = request to @core. Anything waiting on in-game spike results goes behind one config flag. Pure-Lua specs (tools/run-specs.py) + in-game test card." "No push."

Overlord integration rules (2026-11-22), verbatim summary: work in `vs worktree create` units, never the primary checkout; merge to local main only after review PASS: rebase on current main, `python tools/run-specs.py` all green, merge, log the hash; one lane merges at a time (main moved → rebase again); in-game checks go in this lane's section of OWNER-TESTS.md only; no pushes; when playtest-ready log `decision roads playtest-ready <hash>`.

## Decided
- Checked existing primitives: fh_core container types already include `wagon` (fh_core/shared/containers.lua:6,14; config.lua:25 wagon 60 slots); `fh_spike_gated` convar + fh_core/docs/spike-gated.md (one flag, reused, no new flag); fh_core regions/factions (shared/regions.lua:10-41); fh_economy `pay`/`rep` exports (fh_economy/README.md:6-8); fh_core `requestSpawn` spawn contract; admin `fh_heat` stub (fh_core/server/admin.lua:46-53). No wagon resource in [rsg]; spawn_rules KINDS excludes vehicles (fh_core/shared/spawn_rules.lua:16).
- Spike gating: S2 (spk_chase) and S3 (spk_wheel) RESULT lines are empty, so mounted chase and native wheel break sit behind `fh_spike_gated` (default true = conservative path). New rows appended to spike-gated.md.
- Fast travel: no fast-travel resource exists. fh_cargo exposes the veto (`exports.fh_cargo:canFastTravel(src)` -> ok, reason) + `fh:cargo:fasttravel_blocked`; whoever adds fast travel calls it. Not a workaround: it is the contract.
- Pricing, contracts, heat math are pure shared Lua modules with specs; server files are thin.
- 2026-11-22 hub (RiffBot): freight registers as a job type in @quests' fh_quests; roads builds no board.
- Contract board / heat HUD: lanes ship data, @ui ships screens. Here: data exports + an ox_lib menu/chat fallback only.

## Blocks
| Block | Touches | Clashes with | Kind |
|---|---|---|---|
| R0 @core request: spawn kind `wagon` (client CreateVehicle + adopt netId, same contract as ped/horse) + admin `fh_heat` delegates to `exports.fh_heat` when started | fh_core spawn_rules.lua, spawn.lua, admin.lua | @core (owner of the files) | Root cause (sent to @core inbox; roads does not edit fh_core) |
| R1 fh_cargo: wagon tiers config (T1 cart / T2 wagon / T3 freight: slots, weight, speed cap), per-wagon `wagon` container via fh_core, load/unload cargo items only within reach of own wagon, `canFastTravel` veto, `/fh_wagon <tier>` dev spawn, server export `nearestWagon(src, coords, range) -> container ref|nil` (nearest live wagon within range that src may load; v1 = owner only) for @hunting (idea-617) | new `[fh]/fh_cargo`, server.cfg ensure line | server.cfg (all lanes, one line) | Root cause |
| R2 wheel break + hammer repair: break roll from speed/off-road/load (pure), `hammer` + `wagon_wheel` items, repair progress. Gated path: break = state + speed cap only; ungated: native wheel break per spk_wheel | fh_cargo, item registry entries | fh_core items (request via R0 note if registry is core-owned) | Root cause (gated path replaced by flipping flag after S3 GO) |
| R3 fh_trade prices: regional base × shortage multiplier, drift over time, sell saturation; trade-post sell via fh_economy `pay` | new `[fh]/fh_trade`, migration for price state | fh_economy (read-only use) | Root cause |
| R4 freight contracts: generate from shortages, accept → cargo item into wagon, deliver to target region (reach check) → pay + rep, fail on timeout/loss. NO own board: freight is a job type for @quests' fh_quests (pure job-type def: offers/accept/progress/complete/fail hooks), emits `fh:trade:contract_*` events, registers with fh_quests when that resource is started (soft dependency) | fh_trade, migration | @quests (job-type registration contract), @ui (screen) | Root cause |
| R5 fh_heat: per-faction heat 0-100 persisted, sources (camp clears via fh_zones events, illicit cargo sale), lay-low decay off-territory, bounty payoff via fh_economy, `fh:heat:changed` | new `[fh]/fh_heat`, migration | fh_zones events (consume only) | Root cause |
| R6 roadblocks + chase: heat threshold spawns chokepoint roadblock peds via requestSpawn (always on); night ambush + mounted wagon chase only when `fh_spike_gated=false` | fh_heat, spike-gated.md rows | @core spike-gated.md (append rows only) | Root cause (chase gated until S2 GO) |
| R7 test card + playtest-ready | OWNER-TESTS.md `## Roads` section, READMEs | all lanes (own section only) | — |

Order: R0 sent now. R1 → R2 (needs R0 at runtime; specs can land first) ∥ R3 → R4 (needs R1 wagon container). R5 ∥ R3 after R1. R6 after R5. R7 last. Each block: worktree unit, specs green, Gemini/peer review PASS, rebase, merge, log hash.

## Done-check
- `python tools/run-specs.py` all green including new fh_cargo/fh_trade/fh_heat specs; boot-check clean.
- OWNER-TESTS.md `## Roads` card walks M4 + M5 bullets; gated items say which flag flip enables them.
- `vs log decision "roads playtest-ready <hash>"`.

## Lead
Roads lead (spawned by Buddy; none was running).

## Out of scope
Fast-travel system itself, NUI screens (@ui), horse ownership/stables, hired hands, regional rep unlock UI (M7), any push.

Credits: original design, no plugin parity.
