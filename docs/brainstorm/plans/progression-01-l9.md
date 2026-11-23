# Plan progression-01 · L9 rep tiers + fence + hired hands

## Owner's words (verbatim, from brief)
> L9 fh_fence + fh_hands + rep-tier unlocks on top of @core's fh_economy ledger: regional rep tiers, roving fence on a schedule (stops, not real driving), rare parts/treasure leads, hired hands as timers automating upkeep. Insurance stays with @core fh_death. Spec: docs/FRONTIER_HOMESTEAD_SPEC.md. Owner: build everything autonomously, Aub tests only at the end. Use @core §4 APIs only (fh_core containers, fh_buffs, fh_economy, regions, events); contract changes = request to @core. Anything waiting on in-game spike results goes behind one config flag. Pure-Lua specs (tools/run-specs.py) + in-game test card in README. No push.

Overlord integration rules (2026-11-22) apply: vs worktree units only; merge to local main only after review PASS + rebase on current main + `python tools/run-specs.py` all green; one lane merges at a time (re-rebase if main moved); in-game checks go in the **progression section of OWNER-TESTS.md** (overrides "test card in README"); no push; when playtest-ready log `decision progression playtest-ready <hash>`.

## Done when
Spec M7 slice: regional rep unlocks a tier gate (T2 contracts / wagon tier exposed as `canUnlock` checks other lanes call); roving fence visits scheduled stops and sells rare parts + treasure leads; one hired hand automates one upkeep task on a timer. Specs green, Gemini PASS, merged to local main, OWNER-TESTS section written, playtest-ready logged.

## Grounding (read 2026-11-22)
- fh_economy exports only `pay` and `rep` (`server/resources/[fh]/fh_economy/server/main.lua:68-69`). Rep emits `fh:economy:rep_changed` with `value` (main.lua:62-63, value may be nil).
- Missing for L9: **no `getRep` read**, **no `charge`/debit** (fence purchases, hand wages). Both = @core contract change.
- Regions: only `heartlands` + one T1 territory (`fh_core/shared/regions.lua:15-36`). Fence stops are config inside fh_fence, keyed to region ids.
- No lane owns troughs/upkeep yet (grep: only spec mentions).

## Decided
- New resources `fh_progression` (tier table + unlock checks), `fh_fence`, `fh_hands` under `server/resources/[fh]/`. fh_economy stays @core's.
- Checked existing primitives: fh_economy exports (pay, rep, rep_changed event), fh_core container API (addItem, registerContainer, `fence_stash` container type in spec §4), spawn contract (requestSpawn for the fence NPC/wagon). Nothing existing covers tiers, schedule, or timers. No VS command added.
- Fence moves stop-to-stop by schedule (teleport-spawn at stop, despawn on leave); no driving AI.
- Spawned fence NPC/wagon behind `fh_spike_gated` (reuse @core's convar, not a new flag).
- Hands = server timers on persisted state (offline-safe catch-up capped), wages via `charge`.
- Insurance out (@core fh_death).

## Blocks
| Block | Touches | Clashes with | Kind |
|---|---|---|---|
| P0 @core request: `getRep(src, region_id)` + `charge(src, amount, reason, region_id)` exports on fh_economy | fh_economy (core's) | @core | Root cause (sent to @core inbox; progression lead does not edit fh_economy) |
| P1 fh_progression: tier table (config thresholds per region), `getTier`, `canUnlock(src, unlock_id)`, cache refreshed from rep_changed + getRep | new resource, specs | none | Root cause; until P0 lands use a `compat` shim reading fh_rep via oxmysql read-only → **Workaround, replaced when P0 merges (P1b swap shim to export)** |
| P2 fh_fence: schedule config (stops, dwell, rotation), stock tables gated by tier, rare parts + treasure-lead items (lead = item w/ coords info), buy via charge, sell via pay, `fence_stash` container; NPC spawn via requestSpawn behind fh_spike_gated | new resource, items registry via `registerItems` | @core items (register only), @ui later for shop screen (ship data + simple ox_lib menu now) | Root cause; ox_lib menu = Workaround → follow-up @ui fence screen (inbox item) |
| P3 fh_hands: hire/fire, wage ticks via charge, task registry `registerTask(kind, fn)`; first task: hand tops up a homestead chest "feed" item (owned by us) until @homestead ships troughs | new resource | @homestead (chest read via container API only) | Workaround for trough → follow-up: trough task once @homestead/@survival own troughs (Open) |
| P4 OWNER-TESTS progression section + admin cmds (`/fh_rep`, `/fh_fence_next`, `/fh_hand_tick`) for fast testing | OWNER-TESTS.md, resources | other lanes' sections (edit own section only) | Root cause |

Order: P0 sent now → P1 → (P2 ∥ P3) → P4 → Gemini review → merge per Overlord rules → log playtest-ready.

## Out of scope
Insurance, contracts board, wagon tiers themselves (we expose the gate only), NUI screens (@ui), troughs, real driving AI, push.

## Credits
No plugin parity; nothing to credit.
