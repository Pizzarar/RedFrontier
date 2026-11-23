# Survival plan 01: L2 fh_survival needs-as-buffs (`@survival`)

## Owner's words (lane brief, verbatim)
> L2 fh_survival: needs-as-buffs (food, water, rest, temperature, cleanliness), canteen refill, washing, sluggish debuffs, never lethal. Built only on fh_buffs.apply/get; any fh_buffs change goes through @core. Well-Rested-from-comfort deferred to L1. Pure-Lua specs first; in-game card for Aub.

Overlord (2026-11-22): "Aub's target is all lanes playtest-ready on local main, with no clicks from Aub. If you're blocked on a contract, ask the owning lane ... and plan around a stub."

## Overlord integration rules (apply to every block)
1. Work in `vs worktree create` units, never the primary checkout.
2. Merge to local main only after the review PASSes: rebase on current main, `python tools/run-specs.py` all green, merge, log the hash.
3. One lane merges at a time; if main moves, rebase again.
4. fh_homestead belongs to @homestead, fh_buffs/fh_core to @core. Do not edit them; requests go to their Buddies.
5. In-game checks go in a `## Survival` section of `OWNER-TESTS.md`. No separate test doc.
6. No pushes.
7. When playtest-ready: `vs log decision "survival playtest-ready <hash>"`.

## Decided
- **Needs are positive timed buffs only.** Eat → `well_fed`, drink/canteen → `hydrated`, sleep → `rested`, fire/shelter → `warm`, wash → `clean`. Every need goes through `exports.fh_buffs:apply(src, id, mag, duration)`; state is read with `get(src)`. Default durations (config): well_fed 60 min, hydrated 45, rested 120, clean 90, warm 20 (refreshed while near heat).
- **Sluggish is worked out from what's missing, not stored as a debuff.** fh_buffs has no `remove`, and same-id refresh keeps the max magnitude (`fh_buffs/shared/buff_logic.lua:43-46`), so a debuff buff could never be cleared early. fh_survival ticks (config, ~15 s), counts missing core needs and maps the count to sluggish level 0-3. It sends `fh:survival:state` to the client. **Never lethal:** no health drain at any level.
- **Core needs:** food, water, rest and cleanliness always count. `warm` counts only inside config `ColdRegions` (§4.4 region ids). Outside them it is just a bonus.
- **Sluggish effect sits behind one flag:** `Config.SluggishEffect = 'notify'` (default: text plus level in the state event, no natives) | `'native'` (stamina/dead-eye regen reduction and a movement clipset at level 3; natives listed in `fh_core/docs/natives.md` with the hash). `native` is unverified in-game, so the safe default ships first and the OWNER-TESTS card checks both settings.
- **Relog:** the lane owns a `fh_survival_needs` table. On drop it saves the remaining seconds per need; on character load it re-applies them through `fh_buffs.apply`. Characters with no row get a 10-min login grace before sluggish can kick in. Server restarts behave the same way.
- **Well-Rested from comfort is in this lane.** This corrects the brief: homestead-01 says "Homestead does NOT apply buffs; @survival reads comfort and calls fh_buffs". Sleeping at a homestead `bed` station gives `rested` with magnitude `1.0 + comfort × k`, capped by the fh_buffs cap (1.20). A bedroll anywhere gives 1.0.
- **rsg-core hunger/thirst/cleanliness metadata (`rsg-core/server/player.lua:167-174`) is not used.** No vendored resource decays it, so fh_buffs is the single source of truth. fh_survival never reads or writes those keys.
- **Contracts and stubs:**
  - @core fh_buffs: add caps `hydrated = 1.0` and `clean = 1.0` (config-only, no API change). Requested via the @core inbox. Until it lands, the S2 boot check logs `unknown_buff` for those two and still runs the other needs. No stub code is needed: `apply` refuses cleanly.
  - @core `registerItems` (B7, in flight on core-b7, not on main): S3 registers food, canteen and bedroll items through it. Until B7 is on main, the items live in the lane's `shared/items.lua`, with a guarded `pcall(exports.fh_core.registerItems)`. Follow-up: S3b removes the guard once B7 is merged.
  - @homestead `isNearStation(src,'bed')` (H3) and `getComfort(citizenid)` (H4) are not on main yet. S4 calls them through a `pcall` adapter (`server/homestead_adapter.lua`); a missing export means no bed (bedroll only) and comfort 0. Follow-up: S4b drops the fallback path once H3/H4 are on main and the adapter spec runs against the real exports.
  - @ui: the U2 buff HUD already listens to `fh:buffs:sync`, so needs show up there for free. The sluggish level is sent on `fh:survival:state` (documented in the README) for @ui to pick up later. No UI work in this lane.
- **Primitives checked:** `vs --help` (worktree/task/spec/watch/verdict/spawn), the VS MCP tool list, and the §4 exports on main: `fh_buffs` apply/get (README), `fh_core` containers/addItem/requestSpawn and `docs/natives.md`, `fh_homestead` claim/unclaim/getPlot/isInSafeZone (`server/main.lua:154-157`; no station/comfort exports yet). No vendored survival or needs resource (no rsg-hud/rsg-needs in `[rsg]`). This is all new code, with no parity/plugin-inspired features, so nothing to credit.

## Plan (order + done-check)
| Block | Goal | Done-check | RC / WA |
|---|---|---|---|
| S1 Pure logic | `shared/needs.lua`: missing-needs → sluggish level (cold-region rule), login grace, durations, rested magnitude from comfort, canteen charges, save/restore remaining-seconds math | `spec/survival_*_spec.lua` green in `run-specs.py` (levels 0-3, warm only in cold regions, grace window, cap clamp, relog restore never extends past saved remaining) | Root cause |
| S2 Server core | `[fh]/fh_survival` skeleton, tick, `fh:survival:state`, `fh_survival_needs` migration plus save on drop and restore on load, README (events/exports/config/tables), `server.cfg` ensure after fh_buffs | specs + boot check green; README lists emitted/consumed events | Root cause |
| S3 Food, water, wash, warmth | Usable food and canteen items (charges in metadata), canteen refill and washing when standing in water (water-check native behind the same flag family; default is a config list of water-zone coords), campfire proximity → `warm` | specs for item → buff mapping, charge use/refill, wash cooldown; natives listed in natives.md | Root cause (registerItems guard = WA → S3b) |
| S3b | Remove the registerItems guard once @core B7 is on main | spec covers real registration | Root cause |
| S4 Rest + comfort | Bedroll item (rested 1.0) and homestead bed via adapter (`1.0 + comfort×k`) | adapter spec: export missing → bedroll-only, comfort 0; present → magnitude from comfort, capped | Root cause (adapter fallback = WA → S4b) |
| S4b | Drop the adapter fallback once @homestead H3/H4 are on main | spec passes against the real exports | Root cause |
| S5 Sluggish effect + card | Client effect with `SluggishEffect` flag (`notify` default, `native` opt-in); `## Survival` in OWNER-TESTS.md (eat/drink/wash/sleep/refill, wait out a need → sluggish, relog keeps needs, never dies, flag = native) | card written; specs green; then `vs log decision "survival playtest-ready <hash>"` | Root cause |

| Block | Touches | Clashes with |
|---|---|---|
| S1 | new `fh_survival/shared/needs.lua`, new `spec/survival_*` | none |
| S2 | new `fh_survival/server/main.lua`, `config.lua`, `fxmanifest.lua`, `README.md`, migration sql, `server.cfg` ensure | server.cfg (every lane adds ensure lines: rebase) |
| S3 | `fh_survival/server/actions.lua`, `client/actions.lua`, `shared/items.lua`, config.lua (append), `fh_core/docs/natives.md` (append) | config.lua with S4/S5 (append-only: rebase); natives.md (other lanes append) |
| S3b | `shared/items.lua`, `server/actions.lua` | none |
| S4 | `fh_survival/server/rest.lua`, `server/homestead_adapter.lua`, config.lua (append) | config.lua (rebase) |
| S4b | `server/homestead_adapter.lua` | none |
| S5 | `fh_survival/client/effects.lua`, config.lua (append), `OWNER-TESTS.md` `## Survival` | OWNER-TESTS.md (all lanes append: rebase) |

Order: S1 → S2, then S3, S4 and S5 in parallel (separate files, config.lua is append-only). Merge per block, one at a time. S3b and S4b run once their dependency is on main. They don't block playtest-ready, because the guards keep things working.

## Lead
Lane @survival has no lead, so the Buddy spawns `Lead - Claude`.

## Out of scope
- Editing fh_buffs/fh_core (@core), fh_homestead (@homestead), NUI screens (@ui).
- Cooking/recipes (@crafting), meat from hunting, lethal meters, disease, weather simulation beyond cold regions.
- Push, release.
