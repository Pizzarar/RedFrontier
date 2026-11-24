# Plan · @a-life 02 · roads, raids and contracts (v2 slice 1)

Implemented A-Life — Thanks to S.T.A.L.K.E.R. A-Life by GSC Game World. (This credit line goes in the commits and CREDITS.md; it is already in CREDITS.md, so add one only if a new feature line is needed.)

Lead: Ali1 (rn-bbe4d1ca7960). Buddy: A-Life (rn-2589bd3f3837). Cross-lane: @world Wor1 rn-cb1d438f267f (ambush node data), @quests (job board, via the public `registerJobType` export only).

## Ask (verbatim)
- Red3: "next a-life plan after a-life-01 (e.g. camp raids/patrol movement between camps)". "owner ... wants [quota] USED. Keep your lane working its goals."
- Hub: "A-Life carries most of the 'more' content: camp ownership flips feed fh_trade shortage prices, heat/rep, and generated contracts (camp clear, bounty, escort, rescue)." "no visible cross-map riding."

## Goal (what Aub sees)
Outlaw squads leave the camps they hold and sit on road ambush points. If Aub rides past one, a gang on foot is waiting there. Killing them weakens the outlaws, which delays their retake and makes it more likely to fail. Law patrols reinforce the camps the law holds. Each outlaw-held camp and each live ambush squad posts a job on the region's board. `/alife` lists the squads on the road.

## Decided
- Primitives checked:
  - `fh_alife` rules: squads, `tick`, `resolveSquad`, the retake goal (`fh_alife/shared/alife_rules.lua`).
  - fh_core `requestSpawn`/`despawn` (server-owned spawns, zone budget), with spawn and death watch modelled on `fh_heat/server/roadblocks.lua` and the fh_zones ped health check.
  - fh_quests `registerJobType` (`fh_quests/server/api.lua:240`) and the built-in `camp_clear`/`bounty` types (`fh_quests/shared/jobtypes.lua:12`).
  - FhRegions (`kind`, `factionLabel`).
  - No new vs command and no new core API.
- **Nodes:** ambush points come from `regions[id].ambush` (@world, optional in their block C). Until those land, `FhAlifeConfig.ambush[region]` holds 2 unverified fallback points per region. When both exist, @world's data wins.
- **No riding.** A squad on its way to a node is invisible. It materialises on foot only once it holds an ambush node *and* a player is within `ambushRadius`, using the same "wake when near" idea as fh_zones. It despawns when no player is near, and keeps its surviving strength.
- **Outlaw raids:** every tick, each outlaw-held camp has a configurable chance to send a squad to one of its region's ambush nodes (goal `ambush`). The squad holds the node for N ticks, then returns. One live squad per node and a per-region cap keep the entity budget bounded.
- **Strength links:** each kill takes 1 off the squad's strength, and a wiped squad is removed. Outlaw strength lost on the road is subtracted from that faction's next retake roll in the region (`regionPressure`), so killing raiders makes the camp easier to hold.
- **Law patrols:** law-held camps get `reinforce` squads, data only, that add holder strength against retakes. They never spawn peds in v2.
- **Heat:** no new heat source. Killing a squad that fh_heat already tracks through faction peds adds heat as it does today. If no such path exists, the lead logs a follow-up and does not add a source here.
- **No clash with fh_heat's own ambush:** fh_heat's spike-gated "night ambush" is law hunting a wanted player. A-Life ambushes are faction squads on fixed nodes, with different spawn owner tags. Both share the fh_core zone budget.
- **Contracts:** a new job type, `alife_contract`, registered through `registerJobType`. It offers a "clear <camp>" job only while that camp is outlaw-held, and a "break the ambush at <node>" job while a squad holds a node. A job pays on the existing `fh:zones:camp_cleared` event or on a new `fh:alife:squad_wiped` event. Escort and rescue stay out (see Out of scope).
- Pacing is config, and `/alife tick n` still fast-forwards. `/alife` lists squads by goal, node and strength.

## Plan
| Block | Touches | Clashes with | Kind |
|---|---|---|---|
| B1 rules: ambush nodes in the graph (@world data or config fallback), goals `ambush`/`reinforce`, raid chance and caps, `regionPressure`, wiped and return paths, serialize the new fields (old saves still load) + specs | `fh_alife/shared/alife_rules.lua`, `fh_alife/config.lua`, `spec/alife_rules_spec.lua` | none | Root cause |
| B2 server: materialise and despawn ambush squads near players via requestSpawn (tag `owner={kind='alife_squad'}`), server-side death watch, `fh:alife:squad_wiped` event, `/alife` squad list; docs in `fh_core/docs/events.md` + specs | `fh_alife/server/main.lua`, new `fh_alife/server/squads.lua`, fxmanifest, `spec/alife_server_spec.lua`, events.md | fh_heat roadblocks (shared spawn budget only) | Root cause |
| B3 contracts: `alife_contract` job type via `registerJobType` (camp-clear while outlaw-held, break-ambush while a node is held), pays on existing/new events + specs | new `fh_alife/server/contracts.lua` (+ shared rules for offers/verdict), spec | @quests: export use only, no fh_quests edits. If a needed hook is missing, queue it to @quests rather than editing | Root cause |
| B4 OWNER-TESTS steps (ride to an ambush point, gang there, kill them, `/alife` shows the squad gone, board shows the contracts) | OWNER-TESTS.md | append-only | Root cause |
| W1 fallback ambush coords in fh_alife config | `fh_alife/config.lua` | @world block C | **Workaround**, replaced when @world ships `regions[].ambush` (their world-01 C / Open item); fallback is ignored once data exists |

Order: B1 → (B2 ∥ B3) → B4. W1 ships with B1.
Done-check: `~/.venvs/rf/bin/python tools/run-specs.py` green; Gemini review PASS per block; merge slot from Red3 (or its successor). Never commit to main outside the slot.

## Out of scope
- Visible riding and mounted chases.
- Escort and rescue contracts (a-life-03).
- Wilderness-claim raids (needs the homestead claim-class API; a-life-03 candidate).
- Owner-coloured blips.
- The per-faction loot tables (@world).
