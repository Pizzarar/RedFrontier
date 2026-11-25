# Public events (developer reference)

`fh:*` events that exist in code on main today. Convention: one table argument, server events carry `src` first, client-to-server events are requests the server revalidates (`server/resources/[fh]/fh_core/docs/events.md`). Payloads below are read from the emitting code. Lane events from the other playtest-ready lanes are in the last section, read from each lane's README (not re-checked line by line).

## Server-local notifications (`TriggerEvent`)

| Event | Emitted at | Payload |
|---|---|---|
| `fh:inventory:moved` | `server/resources/[fh]/fh_core/server/inventory.lua:150` | `{ src, citizenid, from, to, item, count }` |
| `fh:inventory:refused` | `server/resources/[fh]/fh_core/server/inventory.lua:153` | `{ src, citizenid, from, to, item, count, reason }` |
| `fh:inventory:transferred` | `server/resources/[fh]/fh_core/server/inventory.lua:169` | `{ src, citizenid, from, to, moved, leftovers }` |
| `fh:economy:paid` | `server/resources/[fh]/fh_economy/server/main.lua:37` | `{ src, citizenid, amount, reason, region_id, ledger_id }` |
| `fh:economy:rep_changed` | `server/resources/[fh]/fh_economy/server/main.lua:63` | `{ src, citizenid, region_id, delta, value, reason }` |
| `fh:economy:charged` | `server/resources/[fh]/fh_economy/server/main.lua:109` | `{ src, citizenid, amount, reason, region_id, ledger_id }` (a debit) |
| `fh:economy:credited` | `server/resources/[fh]/fh_economy/server/main.lua:340` (online) · `:299` (queued claimPending) | `{ src, citizenid, amount, reason, region_id, queued, ledger_id? }` — `ledger_id` online-only (E2 offline-safe credit) |
| `fh:buffs:applied` | `server/resources/[fh]/fh_buffs/server/main.lua:19` | `{ src, buff_id, magnitude, expires_at, refreshed }` |
| `fh:homestead:claimed` | `server/resources/[fh]/fh_homestead/server/main.lua:84` | `{ src, citizenid, plot_id, region_id }` |
| `fh:homestead:unclaimed` | `server/resources/[fh]/fh_homestead/server/main.lua:107` | `{ src, citizenid, plot_id }` |
| `fh:death:dropped` | `server/resources/[fh]/fh_death/server/main.lua:190` | `{ src, citizenid, container_id, coords, life, expires_at, moved, kept }` |
| `fh:death:recovered` | `server/resources/[fh]/fh_death/server/main.lua:260` | `{ src, citizenid, container_id }` |
| `fh:death:expired` | `server/resources/[fh]/fh_death/server/main.lua:252` | `{ src, citizenid, container_id, coords, lost }` |
| `fh:zones:camp_activated` | `server/resources/[fh]/fh_zones/server/main.lua:115` | `{ camp_id, region_id }` |
| `fh:zones:camp_cleared` | `server/resources/[fh]/fh_zones/server/main.lua:137` | `{ camp_id, region_id, loot }` |
| `fh:zones:camp_respawned` | `server/resources/[fh]/fh_zones/server/main.lua:148` | `{ camp_id, region_id }` |
| `fh:alife:camp_flipped` | `server/resources/[fh]/fh_alife/server/main.lua:60` | `{ camp_id, region_id, from, to }` |
| `fh:hands:hired` | `server/resources/[fh]/fh_hands/server/main.lua:248` | `{ src, citizenid, hand_kind }` |
| `fh:hands:fired` | `server/resources/[fh]/fh_hands/server/main.lua:262` | `{ src, citizenid, hand_kind }` |
| `fh:hands:unpaid` / `quit` / `task_failed` | `server/resources/[fh]/fh_hands/shared/hands_logic.lua` (via `server/main.lua` emit) | `{ src, citizenid, hand_kind, ... }` |
| `fh:ui:ui_<action>` (see below) | `server/resources/[fh]/fh_ui/server/main.lua:17` | `{ src, screen, action, payload }` |

`fh:ui:ui_<action>` is the relay: fh_ui re-emits a validated NUI action as `fh:<owning_lane>:ui_<action>` (for example `fh:ui:ui_ping`, `fh:<lane>:ui_close`). The whitelist of screens and owners is in `server/resources/[fh]/fh_ui/shared/relay.lua`.

## Client to server requests (`RegisterNetEvent`)

| Event | Handler | Payload |
|---|---|---|
| `fh:death:open` | `server/resources/[fh]/fh_death/server/main.lua:313` | `{ id }` |
| `fh:homestead:open_chest` | `server/resources/[fh]/fh_homestead/server/main.lua:122` | `{ plot_id }` |
| `fh:zones:open_loot` | `server/resources/[fh]/fh_zones/server/main.lua:216` | `{ camp_id }` |
| `fh:zones:ped_dead` | `server/resources/[fh]/fh_zones/server/main.lua:203` | `{ tag }` (a hint; the server re-reads health) |
| `fh:saddlebag:open` | `server/resources/[fh]/fh_core/server/saddlebag.lua:82` | `{ netId }` |
| `fh:saddlebag:transfer` | `server/resources/[fh]/fh_core/server/saddlebag.lua:102` | `{ netId, dir, slot, amount? }` |
| `fh:spawn:client_ready` | `server/resources/[fh]/fh_core/server/spawn.lua:145` | `{}` |
| `fh:spawn:created` | `server/resources/[fh]/fh_core/server/spawn.lua:149` | `{ requestId, token, netId }` |
| `fh:spawn:failed` | `server/resources/[fh]/fh_core/server/spawn.lua:172` | `{ requestId, token, reason }` |
| `fh:ui:action` | `server/resources/[fh]/fh_ui/server/main.lua:9` | `{ screen, action, payload }` |
| `fh:dev:clientError` | `server/resources/[fh]/fh_core/server/dev_errors.lua:25` | `{ resource, msg, traceback }` (dev only) |

## Server to client (`TriggerClientEvent`)

| Event | Sent at | Payload |
|---|---|---|
| `fh:buffs:sync` | `server/resources/[fh]/fh_buffs/server/main.lua:21` | snapshot table of active buffs |
| `fh:death:bags` | `server/resources/[fh]/fh_death/server/main.lua:62` | `{ { id, x, y, z }, ... }` |
| `fh:spawn:create` | `server/resources/[fh]/fh_core/server/spawn.lua:94` | `{ requestId, kind, model, modelHash, coords, heading, token }` |
| `fh:spawn:delete` | `server/resources/[fh]/fh_core/server/spawn.lua:45` | `{ requestId, token, netId? }` |
| `fh:spawn:release` | `server/resources/[fh]/fh_core/server/spawn.lua:136` | `{ requestId, token, netId }` |
| `fh:dev:throw` | `server/resources/[fh]/fh_core/server/dev_errors.lua:45` | none (dev only) |

The client listens to `fh:ui:open`, `fh:ui:update` and `fh:ui:close` (`server/resources/[fh]/fh_ui/client/main.lua:44`); a lane sends them with `TriggerClientEvent`.

## Local client event

| Event | Fired at | Payload |
|---|---|---|
| `fh:spawn:adopted` | `server/resources/[fh]/fh_core/client/spawn.lua:101` | `{ requestId, tag, owner, kind, netId, entity }` |

## Lane events from READMEs (server, `TriggerEvent`)

Payloads are as each README states them. One table unless noted "positional".

| Lane | Event | Payload | Source |
|---|---|---|---|
| hunting | `fh:hunting:pelt_skinned` | `{ src, citizenid, item_id, animal, quality, size_class }` (`animal` = plain key or legendary id) | `server/resources/[fh]/fh_hunting/README.md` |
| hunting | `fh:hunting:pelt_sold` | `{ citizenid, item_id, animal, size_class, quality, price, region_id }` (`animal` = plain key or legendary id) | same |
| hunting | `fh:hunting:clue_found` | `{ citizenid, chain_id, region_id, legendary, step }` (step 1-3; `chain_id` = `legendary` = legendary id) | same |
| hunting | `fh:hunting:legendary_spawned` | `{ citizenid, chain_id, region_id, legendary }` | same |
| hunting | `fh:hunting:chain_complete` | `{ citizenid, chain_id, region_id, legendary }` | same |
| quests | `fh:quests:started`, `step`, `completed`, `failed`, `abandoned` | `{ citizenid, quest_id, kind, step }` | `server/resources/[fh]/fh_quests/README.md` |
| quests | `fh:quests:board_changed` | `{ region_id }` | same |
| quests | `fh:quests:talked` | `{ src, citizenid, npc_id }` (emit only, never advances a quest) | same |
| economy | `fh:economy:charged` | see `fh_core/docs/events.md` | `server/resources/[fh]/fh_economy/README.md` |
| progression | `fh:progression:tier_changed` | `{ src, citizenid, region_id, old, new }` | `server/resources/[fh]/fh_progression/README.md` |
| homestead | `fh:homestead:slot_changed` | positional: `plot_id, slot_id, tier` | `server/resources/[fh]/fh_homestead/README.md` |
| homestead | `fh:homestead:station_built` | positional: `citizenid, plot_id, slot_id, station_type` | same |
| homestead | `fh:homestead:comfort_changed` | positional: `citizenid, newComfort, oldComfort` | same |
| homestead | `fh:homestead:trophy_placed` / `trophy_removed` | `{ citizenid, trophy_id, comfort }` | same |
| cargo | `fh:cargo:loaded` / `unloaded` | `{ src, citizenid, wagon, item, count, container }` | `server/resources/[fh]/fh_cargo/README.md` |
| cargo | `fh:cargo:wagon_spawned` | `{ src, citizenid, wagon, tier, netId }` | same |
| cargo | `fh:cargo:fasttravel_blocked` | `{ src, citizenid, reason, wagon }` | same |
| cargo | `fh:cargo:wheel_broken` | `{ src, citizenid, wagon, tier, native }` | same |
| cargo | `fh:cargo:wheel_repaired` | `{ src, citizenid, wagon, tier }` | same |
| trade | `fh:trade:sold` | `{ src, region, post, item, amount, total }` | `server/resources/[fh]/fh_trade/README.md` |
| trade | `fh:trade:contract_delivered` / `contract_failed` | `{ src?, citizenid, key, quest_id, from_region, to_region, item, qty, reward, reason? }` | same |
| heat | `fh:heat:changed` | `{ src, citizenid, faction, old, value, delta, level, reason }` | `server/resources/[fh]/fh_heat/README.md` |
| heat | `fh:heat:threshold` | `{ src, citizenid, faction, old_level, level, value }` | same |
| heat | `fh:heat:roadblock_spawned` / `roadblock_cleared`, `ambush_spawned`, `ambush_cleared`, `chase_started`, `chase_cleared` | see the README | same |
| survival | `fh:survival:state` (to client) | `{ level = 0..3, missing = { ... } }` | `server/resources/[fh]/fh_survival/README.md` |

Client to server: `fh:survival:refill`, `fh:survival:wash` (one boolean), `fh:survival:restBed` (no payload), `fh:hunting:skin`, `fh:hunting:sell_open`, `fh:hunting:sell`, `fh:hunting:chain_status`, `fh:hunting:chain_rumour`, `fh:hunting:chain_inspect`, `fh:trade:menu`, `fh:trade:sell`, `fh:homestead:open_chest` (now also `chest`). The server revalidates every one of them.

Quest step intake (what a quest step can listen to): `fh:zones:camp_cleared` (with `participants`), `fh:hunting:pelt_skinned`, `fh:hunting:pelt_sold`, `fh:hunting:chain_complete`, `fh:homestead:claimed`, `fh:economy:paid`, `fh:economy:rep_changed`, `fh:death:dropped`, `fh:death:recovered`, `fh:death:expired`. Events with a client source are dropped. See `server/resources/[fh]/fh_quests/README.md`.

See also: [Wiki index](../README.md)

Sources:
- `server/resources/[fh]/fh_core/docs/events.md`
- `server/resources/[fh]/fh_core/server/inventory.lua`
- `server/resources/[fh]/fh_core/server/saddlebag.lua`
- `server/resources/[fh]/fh_core/server/spawn.lua`
- `server/resources/[fh]/fh_core/server/dev_errors.lua`
- `server/resources/[fh]/fh_core/client/spawn.lua`
- `server/resources/[fh]/fh_economy/server/main.lua`
- `server/resources/[fh]/fh_buffs/server/main.lua`
- `server/resources/[fh]/fh_homestead/server/main.lua`
- `server/resources/[fh]/fh_death/server/main.lua`
- `server/resources/[fh]/fh_zones/server/main.lua`
- `server/resources/[fh]/fh_alife/server/main.lua`
- `server/resources/[fh]/fh_hands/server/main.lua`
- `server/resources/[fh]/fh_hands/shared/hands_logic.lua`
- `server/resources/[fh]/fh_ui/server/main.lua`
- `server/resources/[fh]/fh_ui/client/main.lua`
- `server/resources/[fh]/fh_ui/shared/relay.lua`
- `server/resources/[fh]/fh_hunting/README.md`
- `server/resources/[fh]/fh_quests/README.md`
- `server/resources/[fh]/fh_progression/README.md`
- `server/resources/[fh]/fh_economy/README.md`
- `server/resources/[fh]/fh_homestead/README.md`
- `server/resources/[fh]/fh_cargo/README.md`
- `server/resources/[fh]/fh_trade/README.md`
- `server/resources/[fh]/fh_heat/README.md`
- `server/resources/[fh]/fh_survival/README.md`
