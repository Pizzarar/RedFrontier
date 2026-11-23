# Hunting plan 01: L8 fh_hunting (`@hunting`)

## Owner's words (lane brief, verbatim)
> L8 fh_hunting: pelt quality (shot placement, gated on S-pelt verdict; fallback = server-rolled quality), pelts as bulky/cargo items, one Legendary hunt chain, trophies feed Homestead comfort. Spec: docs/FRONTIER_HOMESTEAD_SPEC.md. Owner: build everything autonomously, Aub tests only at the end. Use @core §4 APIs only (fh_core containers, fh_buffs, fh_economy, regions, events); contract changes = request to @core. Anything waiting on in-game spike results goes behind one config flag. Pure-Lua specs (tools/run-specs.py) + in-game test card in README. No push.

## Overlord integration rules (2026-11-22, apply to every block)
1. Work in `vs worktree create` units, never the primary checkout.
2. Merge to local main only after the review PASSes: rebase on current main, `python tools/run-specs.py` all green, merge, log the hash.
3. One lane merges at a time; if main moves, rebase again.
4. fh_homestead belongs to @homestead (core B6b-g on main, 06f2d3b). Do not edit it; requests go to the @homestead Buddy.
5. In-game checks go in a `## Hunting` section of `OWNER-TESTS.md`. No separate test doc.
6. No pushes.
7. When playtest-ready: `vs log decision "hunting playtest-ready <hash>"`. The Overlord gates the combined playtest.

## Decided
- **Quality source has one flag:** `Config.PeltQualitySource = 'roll'` (default) | `'native'`. S4 `spk_pelt` (spikes/probes) is built but untested, so `roll` ships first. `roll`: the client reports the carcass netId plus the last damage bone (GET_PED_LAST_DAMAGE_BONE, tracked while the animal is alive because death may clear it). The server maps bone → zone (head/vital = 3★, body = 2★, limb/gut/explosive/multi-hit = 1★), checks plausibility (carcass is dead, within 5 m of the skinner, not already claimed) and rolls within the band. `native`: _GET_PED_QUALITY / _GET_PED_DAMAGE_CLEANLINESS are read instead. Both feed the same `quality.resolve()` pure function, so there's no rework.
- **Size class by animal:** small and medium game (rabbit, fox, coyote, deer, boar, wolf) give `bulky` pelts (saddlebag OK). Big game (bear, bison, elk, moose, alligator) and every legendary give `cargo` pelts (wagon or chest only, which blocks fast travel). Big-game pelts go straight into a wagon owned or used by the player within ~8 m. With no wagon in range, the skin is refused with a message and the carcass stays claimable.
- **Items:** one item id per animal pelt (`pelt_deer`, …). Stars go in the §4.1 `quality` field, not in separate ids. Items are registered through `fh_core` `registerItems`. Use the existing rsg-inventory pelt images where they match.
- **Economy:** a trapper sell point in the M1 region pays through `fh_economy.pay(src, base × qualityMult, 'hunting:pelt', region)`. Default multipliers are 1★ 0.4, 2★ 1.0, 3★ 1.8 and legendary ×4 (config).
- **Legendary (Buddy lean, R13; owner didn't pick):** one animal, the Legendary Bear, with a 3-clue tracking chain inside one region (clue 1: buy a rumour from the trapper; clues 2–3: inspect tracks/carcass markers, each revealing the next area). The final area spawns the bear through `fh_core` `requestSpawn` (client creates, server adopts). Killing and skinning it gives `pelt_legendary_bear` (cargo, always 3★) and a `trophy_legendary_bear` (bulky). Chain state is saved per character.
- **Trophies → comfort:** fh_hunting does NOT edit fh_homestead. It ships trophy items with a `comfort` value in shared data, plus the export `exports.fh_hunting:getTrophyComfort(itemId) -> number|nil` (nil for non-trophies, server-side, pure). **Amended 2026-11-22 with @homestead:** Homestead owns placement (trophy_wall slot, removes the item from the plot chest) and reads the export. Hunting fires NO trophy events, to avoid double-counting.
- **Events for @quests/@guide (hub steer, 2026-11-22):** server-only `TriggerEvent`, payloads always include `citizenid`. H2 `fh:hunting:pelt_skinned` {citizenid, item_id, animal, quality, size_class}. H3 `fh:hunting:pelt_sold` {citizenid, item_id, animal, size_class, quality, price, region_id} (animal + size_class added for @quests Q0b). H4 `fh:hunting:clue_found` {citizenid, chain_id='legendary_bear', step=1..3}, `fh:hunting:legendary_spawned` {citizenid, chain_id}, `fh:hunting:chain_complete` {citizenid, chain_id}. All are listed in the README's Emitted section. @quests builds 'deliver an N-star pelt' jobs on pelt_sold; Hunting adds no job logic.
- **Vanilla skinning:** H2 finds out whether the native skin/loot flow can be intercepted (loot event + suppressing the vanilla pelt) or whether we need our own rsg-target "Skin" prompt on the carcass. Lean: own prompt (deterministic and server-authoritative). Record the choice with file:line/native evidence in the README.
- **Primitives checked:** `vs --help` (worktree/task/spec/watch/verdict), the VS MCP tool list, and the §4 exports on main (`fh_core` move/canFit/addItem/registerItems/requestSpawn, `fh_buffs` apply/get, `fh_economy` pay/rep, `fh_zones` getPlot/isInSafeZone). No existing hunting resource is vendored (only rsg-inventory pelt images). This is all new code, with no parity/plugin-inspired features. Pelt images come from rsg-inventory (RSGCore by Rexshack-RedM), already credited.

## Plan (order + done-check)
| Block | Goal | Done-check | RC / WA |
|---|---|---|---|
| H1 Data + rules | `[fh]/fh_hunting` skeleton, animal table (model → pelt id, size_class, base value), item registration, `quality.resolve()` (both sources), price calc, README with emitted/consumed events | `run-specs.py` green with new `spec/hunting_*_spec.lua` (bone→stars bands, plausibility rejects, size_class per animal, price mult); boot-check green | Root cause |
| H2 Skin flow | Client tracks last bone and offers a Skin prompt; server validates, resolves quality and `addItem`s to backpack/saddlebag (bulky) or a nearby wagon (cargo), claims the carcass once | Specs for claim/dup/range/cargo-no-wagon refusal; OWNER-TESTS card: head-shot deer = 3★, gut-shot = 1★, bear refused without wagon | Root cause |
| H3 Trapper | Sell point (M1 region), sell UI via ox_lib context, `fh_economy.pay` with quality mult, ledger reason `hunting:pelt` | Spec on payout math; card: sell 1★ vs 3★ and check the ledger | Root cause |
| H4 Legendary Bear | 3-clue chain (persisted), bear spawn via `requestSpawn`, legendary pelt (cargo) + trophy | Specs for the chain state machine (order, no skip, relog resume, one bear per chain); card walks the chain end to end | Root cause |
| H5 Trophy → comfort contract | Trophy items + `comfort` data, `getTrophyComfort` export (number or nil). No events (contract agreed with @homestead) | Spec on the comfort lookup (trophy → number, pelt/unknown → nil); @homestead H4 consumes it. Hunting is playtest-ready without @homestead consuming it | Root cause (consumer side = @homestead task) |

| Block | Touches | Clashes with |
|---|---|---|
| H1 | new `server/resources/[fh]/fh_hunting/**`, new `spec/hunting_*`, `server.cfg` ensure line | server.cfg (every lane adds ensure lines: rebase) |
| H2 | fh_hunting client/server, `fh_core/docs/natives.md` (append) | natives.md (@core, other lanes append) |
| H3 | fh_hunting server + config | none |
| H4 | fh_hunting, uses fh_core requestSpawn (read-only) | none; contract change = request to @core |
| H5 | fh_hunting shared data; `OWNER-TESTS.md` `## Hunting` section | OWNER-TESTS.md (all lanes append: rebase) |

Order: H1 → H2 → H3, then H4 and H5 can run in parallel. Merge per block. After H5: `vs log decision "hunting playtest-ready <hash>"`.

## Lead
Lane @hunting has no lead, so the Buddy spawns `Lead - Claude`.

## Out of scope
- Editing fh_homestead (it belongs to @homestead), fh_core contracts (requests go to @core), NUI screens (@ui), and wagon mechanics (@roads).
- Butchering and meat for food/Survival, more than one legendary, hunting licences, and animal spawn ecology.
- Push, release.
