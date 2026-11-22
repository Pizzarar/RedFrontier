# Natives used by fh_core

The shared modules (`config.lua`, `shared/*.lua`) use no natives: they must stay loadable under busted.
Only `server/inventory.lua` calls natives, all server-side.

| Native | Where | Why | Notes |
|---|---|---|---|
| `GetPlayerPed(src)` | `server/inventory.lua` `open` | Player's ped for the reach check | Returns 0 for an unknown/dropped `src`; fh_core treats 0 as `fh_no_player` |
| `GetEntityCoords(ped)` | `server/inventory.lua` `open` | Server-side ped position for `FhContainers.canReach` | Server-side value under OneSync; never trust client-sent coords |

Cfx runtime functions (not game natives) also used: `GetResourceState`, `GetCurrentResourceName`,
`AddEventHandler`, `TriggerEvent`, `exports`.
