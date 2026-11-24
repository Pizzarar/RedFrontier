# fh_tutorial

The intro tutorial (plan guide-02, `@guide`), built on the fh_quests API. One quest, `kind = 'tutorial'`
(`tutorial_intro`), that walks a new character through their first day with short text-only prompts. Skippable and
**never blocking**: it is no one's prereq and nothing depends on it.

- `config.lua`: `FhTutorialConfig.order` — the step order, by stable step id. Reordering the intro is a config edit.
- `shared/tutorial.lua`: pure step bodies + the build/persistence decisions, specced in `spec/tutorial_spec.lua`.
- `server/main.lua`: registers the quest, auto-starts it on a new character's first load, advances the non-event steps
  through `fh_quests.talk`, and backs `/tutorial`, `/tutorial skip`, `/tutorial restart`.
- `client/main.lua`: shows prompts via `ox_lib` notify, draws the step's GPS route, reports the client-check signals,
  and acknowledges the greeting after it has been on screen.

## Flow (steps)

The order comes from `FhTutorialConfig.order` in `config.lua`: greeting, inventory, eat/drink, claim plot, trade post,
hunt, jobs, family giver. Teach needs before they bite, home and stash before shopping, jobs after the first sale
proves the money loop, and the family giver is the graduation. Unknown ids in the list are dropped with a warning;
`greeting` and `inventory` are mandatory (an order missing either falls back to the built-in default order).

Steps advance on the fh_quests intake whitelist plus `fh:quests:talked`. Where a real `fh:*` event exists we use it;
otherwise a talk step (a real giver) or a client check (reported to the server, which calls `talk`). Every step with a
location sets a GPS waypoint (drawn as the yellow multi-route, since RDR3 has no `SET_NEW_WAYPOINT`).

| # | id | Prompt (summary) | Advances on | Waypoint (source) |
|---|---|---|---|---|
| 1 | `greeting` | Welcome; read this, then the inventory prompt follows | client check `fh:tutorial:check greeting` (client ack after 2.5s on screen) | — |
| 2 | `inventory` | Open your inventory (`I`) | client check `rsg-inventory:client:open` | — |
| 3 | `eat_drink` | Eat and drink | server event `fh:buffs:applied` (`well_fed`/`hydrated`) | — |
| 4 | `claim_plot` | Claim a homestead plot (`/fh_claim`) | `fh:homestead:claimed` | homestead = `fh_homestead/config.lua` `heartlands_01.center` |
| 5 | `trade_post` | Go to the Valentine Trade Post, quote/sell | client check `fh:trade:menu` | trader = `fh_trade/config.lua:37` |
| 6 | `hunt` | Hunt, skin, sell a pelt to the trapper | `fh:hunting:pelt_sold` | trapper = `fh_hunting/config.lua:39` |
| 7 | `jobs` | Open the jobs board (`/jobs`) | client check `fh:ui:open` screen `jobs` | — |
| 8 | `family` | Meet a family quest giver (Ruth Hale) | `talk` npc `npc_hale` | giver = `fh_quests/shared/givers.lua:8` |

Waypoint coordinates are copied from the owning lanes' configs (never invented here); re-sync if a lane moves one. All
are approximate / unverified in game, like their sources.

## How the non-event steps advance

`registerQuest` only advances steps on the intake whitelist or `fh:quests:talked`. The steps without a real event
(greeting, inventory, trade, jobs, survival) are `talk` steps with a synthetic npc id, and fh_tutorial's own server
calls `exports.fh_quests:talk(src, npc)` when the matching signal is seen. `talk` is a no-op unless the current step
expects that npc, so a stray or forged report can never skip a step. The greeting has no player action: the prompt
carries `ack = { check = 'greeting', after_ms = 2500 }` and the client reports the check after the text has been on
screen; opening the inventory during that window is simply a no-op until the greeting advances.

## Commands

| Command | What it does |
|---|---|
| `/tutorial` | show the current step's prompt and re-set its waypoint |
| `/tutorial skip` | stop the tutorial: persist `skipped`, abandon an active run |
| `/tutorial restart` | clear `skipped`, abandon an active run, then start again |

## Persistence

- The quest's done/step state lives in `fh_quest_state` (owned by fh_quests). The quest is repeatable with
  `cooldown_min = 0` so `/tutorial restart` can replay a completed tutorial through the public `start`/`abandon`
  exports (a one-time quest cannot be restarted once done).
- Progress is stored by **step id**, not just the step index: each step has a stable `id`, and fh_quests persists
  `progress.step_id` and resolves the current step by it (`fh_quests/shared/engine.lua` `stepIndexOf`). Reordering
  `FhTutorialConfig.order` therefore keeps an in-flight character on the same logical step.
  `server/migrations/0017_fh_tutorial_step_ids.sql` is the one-time migration for rows written before step ids
  existed (old index -> new index + id); run `tools/setup-server.ps1` to apply it.
- The skip/auto-start flag lives in `fh_tutorial_state` (`server/migrations/0016_fh_tutorial.sql`). A row means the
  character has been auto-started at least once; no row = a brand-new character (auto-starts on load). `skipped` is
  whether they opted out.

## Events

- Consumes (server): `fh:quests:started`, `fh:quests:step`, `fh:quests:completed` (prompt routing),
  `fh:buffs:applied` (survival step), `RSGCore:Server:PlayerLoaded` / `RSGCore:Server:OnPlayerUnload` /
  `playerDropped` (lifecycle; on load it re-shows an in-flight run's current prompt), `onResourceStart`
  (register/re-register).
- Consumes (client, net): `fh:tutorial:prompt` (prompt + waypoint), `rsg-inventory:client:open`,
  `fh:trade:menu`, `fh:ui:open` (client-check signals).
- Emits (client -> server, net): `fh:tutorial:check` `check = 'greeting'|'inventory'|'trade'|'jobs'`.
- Emits (server -> client, net): `fh:tutorial:prompt` `{ text, waypoint = { x, y, z, label } | nil,
  ack = { check, after_ms } | nil }`.

## Dependencies and start order

Hard dependency on `fh_core`, `fh_quests`, `oxmysql`, `ox_lib`, `rsg-core`. `ensure fh_tutorial` goes in
`server/server.cfg` after `ensure fh_quests`. The client-check signals are soft: they only matter once the owning lane
(fh_inventory, fh_trade, fh_ui) is running, and are detected at runtime regardless of start order.

## Natives (client, all unverified in game)

GPS route, via `Citizen.InvokeNative` with hashes verified against `alloc8or/rdr3-nativedb-data/natives.json` (MAP
namespace): `CLEAR_GPS_MULTI_ROUTE` `0x9E0AB9AAEE87CE28`, `START_GPS_MULTI_ROUTE` `0x3D3D15AF7BCAAF83`
(`colorNameHash` = `joaat('COLOR_YELLOW')`, a guess), `ADD_POINT_TO_GPS_MULTI_ROUTE` `0x64C59DD6834FA942`,
`SET_GPS_MULTI_ROUTE_RENDER` `0x4426D65E029A4DC0`. RDR3 has no `SET_NEW_WAYPOINT`; this is the equivalent.

## Tests

`~/.venvs/rf/bin/python tools/run-specs.py spec/tutorial_spec.lua` — validates the def, checks the config order and
unknown/mandatory-id handling, walks the step machine to done, and covers skip/restart/persistence plus progress
surviving a reorder. Syntax: `~/.venvs/rf/bin/python tools/run-specs.py --syntax
"server/resources/[fh]/fh_tutorial"`.

## In-game checklist (unverified)

1. New character first load: the greeting shows, then the inventory prompt after ~2.5s; pressing `I` advances to the
   eat/drink step.
2. `/tutorial` re-shows the current step and route; `/tutorial skip` stops it and survives a relog; `/tutorial restart`
   brings it back from step 1 (also after completing it).
3. Eating/drinking, claiming a plot, opening the trade menu, selling a pelt, opening the jobs board, and talking to
   Ruth Hale each advance the matching step.
4. A finished tutorial never re-starts on its own (fh_tutorial_state row), and never blocks the family quests.
5. Reordering `FhTutorialConfig.order` and relogging does not move an in-flight character to a different step.
