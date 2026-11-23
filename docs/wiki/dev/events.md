# Public events (developer reference)

`fh:*` events that exist in code on main today. Convention: one table argument, server events carry `src` first, client-to-server events are requests the server revalidates (`server/resources/[fh]/fh_core/docs/events.md`). Payloads below are read from the emitting code. Planned events (for example `fh:hunting:*`) are not listed: fh_hunting emits none yet.

## Server-local notifications (`TriggerEvent`)

| Event | Emitted at | Payload |
|---|---|---|
| `fh:inventory:moved` | `server/resources/[fh]/fh_core/server/inventory.lua:150` | `{ src, citizenid, from, to, item, count }` |
| `fh:inventory:refused` | `server/resources/[fh]/fh_core/server/inventory.lua:153` | `{ src, citizenid, from, to, item, count, reason }` |
| `fh:inventory:transferred` | `server/resources/[fh]/fh_core/server/inventory.lua:169` | `{ src, citizenid, from, to, moved, leftovers }` |
| `fh:economy:paid` | `server/resources/[fh]/fh_economy/server/main.lua:37` | `{ src, citizenid, amount, reason, region_id, ledger_id }` |
| `fh:economy:rep_changed` | `server/resources/[fh]/fh_economy/server/main.lua:63` | `{ src, citizenid, region_id, delta, value, reason }` |
| `fh:buffs:applied` | `server/resources/[fh]/fh_buffs/server/main.lua:19` | `{ src, buff_id, magnitude, expires_at, refreshed }` |
| `fh:homestead:claimed` | `server/resources/[fh]/fh_homestead/server/main.lua:84` | `{ src, citizenid, plot_id, region_id }` |
| `fh:homestead:unclaimed` | `server/resources/[fh]/fh_homestead/server/main.lua:107` | `{ src, citizenid, plot_id }` |
| `fh:death:dropped` | `server/resources/[fh]/fh_death/server/main.lua:190` | `{ src, citizenid, container_id, coords, life, expires_at, moved, kept }` |
| `fh:death:recovered` | `server/resources/[fh]/fh_death/server/main.lua:260` | `{ src, citizenid, container_id }` |
| `fh:death:expired` | `server/resources/[fh]/fh_death/server/main.lua:252` | `{ src, citizenid, container_id, coords, lost }` |
| `fh:zones:camp_activated` | `server/resources/[fh]/fh_zones/server/main.lua:115` | `{ camp_id, region_id }` |
| `fh:zones:camp_cleared` | `server/resources/[fh]/fh_zones/server/main.lua:137` | `{ camp_id, region_id, loot }` |
| `fh:zones:camp_respawned` | `server/resources/[fh]/fh_zones/server/main.lua:148` | `{ camp_id, region_id }` |
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
- `server/resources/[fh]/fh_ui/server/main.lua`
- `server/resources/[fh]/fh_ui/client/main.lua`
- `server/resources/[fh]/fh_ui/shared/relay.lua`
