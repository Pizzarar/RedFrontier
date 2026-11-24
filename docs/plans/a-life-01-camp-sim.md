# Plan · @a-life 01 · server camp-ownership sim (v1)

Implemented A-Life — Thanks to S.T.A.L.K.E.R. A-Life by GSC Game World. (This credit line goes in the commits, CREDITS.md and release notes.)

Lead: (spawned by the A-Life Buddy at handoff, see the brief). Buddy: A-Life (rn-2589bd3f3837). Cross-lane: @world Buddy rn-14920746d476 (faction + node data).

## Ask (verbatim)
- Lane seed: "STALKER-style server sim (credit GSC Game World): faction squads with goals on a node graph, spawn only near players, camp ownership flips that feed fh_trade prices and heat."
- Owner via Red3: "push whatever you need, get as much done for me to try when home".
- Hub (RiffBot): "v1 guardrails: squads are data on a node graph (camps, towns, road ambush points); peds spawn only near players (reuse the fh_zones activationRadius wake); no visible cross-map riding ... Entity budget per zone, server-owned spawns (spec §7)." "Loot tables are per faction (8 x 3 tiers), so who holds a camp changes what drops."

## Goal for tonight's playtest
Aub clears the Heartlands camp, and the server announces that Valentine Law has taken it. The camp stops spawning bandits, the Valentine trade price moves, and outlaw heat goes up. About 20-30 min later (or after `/alife tick`), an outlaw squad retakes the camp: another announcement, and bandits spawn there again. `/alife` shows the live state.

## Decided
- Primitives checked (none are rebuilt):
  - `fh_zones` camp state machine and its activationRadius wake (`fh_zones/server/main.lua`), plus the `fh:zones:camp_activated` (:115) and `fh:zones:camp_cleared` (:159, includes `participants`) events.
  - `fh_heat` `addSource(src, faction, 'camp_clear')`. The source already exists in `fh_heat/config.lua:6`.
  - `fh_trade` `setShortage(region, item, level)` (`fh_trade/server/main.lua:237`).
  - Factions and territories: `fh_core/shared/regions.lua`, read through `FhRegions`.
  - Peds go only through the existing fh_core `requestSpawn` contract, which is server-owned and respects the zone budget.
  - No new vs command or core API. Admin commands use the existing fh_core admin_args pattern.
- New resource `fh_alife`. The sim is server-only, keeps squads as data, and spawns no peds itself. Peds appear only when fh_zones wakes a camp.
- **Data ownership.** @world/@core own faction and node data. A-Life owns only the tick, the flips and the effects. v1 runs on the 4 factions and 2 camps that exist now, and reads factions and nodes as data, so it works unchanged when @world's 8 factions and new camps land.
- **Node graph v1:** each region has a camp node (from `fh_zones` camps) and a town node (law home, from the region). Road ambush nodes come in v2 (see Open).
- **Squads:** `{id, faction, strength, from, to, etaTick, goal = raid|reinforce|retake}`. A squad never renders while it travels; when it arrives it resolves by weighted dice (attacker strength vs holder strength).
- **Ownership:** each camp has an `owner` faction. The default is the territory's `faction`. A camp held by a law faction is not hostile: fh_zones skips activation, so no bandits spawn. An outlaw-held camp behaves exactly as it does today.
- **The player feeds the sim.** When `fh:zones:camp_cleared` fires, the camp flips to that region's law faction, and each participant gets `addSource(src, oldOwner, 'camp_clear')`.
- **Flips feed trade.** A flip to outlaws raises the region's configured good via `setShortage` (bandits on the road); a flip to law relieves it. Item and level are config, defaulting to the region's existing initialShortages goods.
- **Per-faction loot:** fh_zones picks the loot table by the current owner faction (`lootByFaction[faction]`), falling back to the camp's own table. v1 ships the hook and the 2 current tables. The full 8x3 tables are @world data.
- **Persistence:** resource KVP (`SetResourceKvp` with JSON). No DB migration, so no migration slot.
- **Announcements:** a server chat broadcast on every flip, e.g. "Valentine Law has taken the Heartlands Outlaw Camp".
- Pacing is config: tick 60s, retake raid roughly 20-30 min after a law flip, scaled up so it can be tested tonight. `/alife tick [n]` fast-forwards (admin only).

## Plan
| Block | Touches | Clashes with | Kind |
|---|---|---|---|
| A1 pure rules `fh_alife/shared/alife_rules.lua` (graph from config, squad spawn/move, resolve, flip, effects list) + `spec/alife_rules_spec.lua` | new files only | none | Root cause |
| A2 server `fh_alife/server/main.lua` + config + fxmanifest: tick, KVP persist, consumes `camp_cleared`, applies effects (heat, shortage, broadcast), exports `getOwner(campId)`/`getState()`, emits `fh:alife:camp_flipped`; admin `/alife` (status) and `/alife tick [n]`; `spec/alife_server_spec.lua` | new resource; server.cfg ensure line | server.cfg also edited by other lanes (one line) | Root cause |
| A3 fh_zones reads owner: skip activation when the owner is law; loot by owner faction (`lootByFaction`, falling back to the camp table). Guard: if fh_alife isn't started, behave exactly as today | `fh_zones/server/main.lua`, `fh_zones/config.lua`, `spec/camp_rules_spec.lua` (or a new zones server spec) | @world (camp data in fh_zones/config.lua): coordinate, don't reshape the camp table | Root cause |
| A4 CREDITS.md line + OWNER-TESTS.md steps (clear camp, see broadcast, `/alife`, `/alife tick 30`, camp hostile again, trade price moved, heat up) | CREDITS.md, OWNER-TESTS.md | other lanes append to OWNER-TESTS (append only) | Root cause |

Order: A1 → A2 → A3 → A4. A1 and A3 can run in parallel once the A1 API is fixed (A3 only needs `getOwner`).
Done-check: `~/.venvs/rf/bin/python tools/run-specs.py` green with the new specs, and the syntax check green. Then a Gemini review PASS on the branch, then ask Red3 (or its successor) for the merge slot. Never commit to main outside the slot.

## Out of scope (v1)
- Visible riding squads and mounted chase AI.
- Road ambush nodes and wilderness-claim raids (town lots are never targets).
- Generated contracts (camp clear, bounty, escort, rescue).
- Dynamic blip recolour by owner.
- The full 8x3 loot tables and new camps (@world data).
