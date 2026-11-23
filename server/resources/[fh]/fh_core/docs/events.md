# Event bus conventions (spec 4.3)

## Naming
`fh:<domain>:<verb>`: lowercase, snake_case verb, domain = owning lane
(`inventory`, `death`, `zones`, `economy`, `buffs`, `heat`, `cargo`, ...).
Verbs are past tense for notifications (`dropped`, `paid`) or imperative for requests.
The emitting lane owns the name and documents it in its README.

## Payload
- **One table argument**, never positional extras: `TriggerEvent('fh:economy:paid', { ... })`.
- **Server events put `src` first** (first key of the table). For net events the server sets `src`
  from the `source` global; never trust a `src` sent by a client.
- Include `citizenid` when the event concerns a character that may be offline.
- Add fields, never rename or remove them. Consumers must ignore unknown keys.
- Client -> server net events are requests, not facts: the server revalidates everything.

## Known M1 events

| Event | Emitter | Payload |
|---|---|---|
| `fh:inventory:moved` | fh_core | `{ src, citizenid, from, to, item, count }` |
| `fh:inventory:refused` | fh_core | `{ src, citizenid, from, to, item, count, reason }` |
| `fh:death:dropped` | fh_death | `{ src, citizenid, container_id, coords, life, expires_at, moved, kept }`: one per life; `container_id` = drop_bag stash id; `moved` = stacks moved; `kept` = `{ from, name?, amount?, reason }[]` left in their source; `expires_at` = unix seconds |
| `fh:death:recovered` | fh_death | `{ src, citizenid, container_id }`: the owner emptied the bag, which is deleted (`src` 0: found by the sweep; `citizenid` = owner) |
| `fh:death:expired` | fh_death | `{ src, citizenid, container_id, coords, lost }`: despawn timer ran out, bag deleted; `lost` = `{ [slot] = item }` it still held (also logged); `src` 0 |
| `fh:death:open` | fh_death (client -> server request) | `{ id }` (bag id string); server checks owner (citizenid) + reach from the server ped, rate-limited 500 ms, then fh_core.open re-checks reach |
| `fh:death:bags` | fh_death (server -> all clients) | `{ { id, x, y, z }, ... }`: live bags for the open prompt; no owner in it |
| `fh:zones:camp_cleared` | zones lane | `{ src, territory_id, tier }` |
| `fh:economy:paid` | fh_economy | `{ src, citizenid, amount, reason, region_id, ledger_id }` |
| `fh:economy:rep_changed` | fh_economy | `{ src, citizenid, region_id, delta, value, reason }` |
| `fh:buffs:applied` | fh_buffs | `{ src, buff_id, magnitude, expires_at, refreshed }` |
| `fh:homestead:claimed` | fh_homestead | `{ src, citizenid, plot_id, region_id }` |
| `fh:homestead:open_chest` | fh_homestead (client -> server request) | `{ plot_id }` (string); server revalidates owner + reach, `src` from `source` |
| `fh:homestead:unclaimed` | fh_homestead | `{ src, citizenid, plot_id }` (citizenid = former owner; src 0 = console) |
| `fh:spawn:create` | fh_core (server -> chosen client) | `{ requestId, kind, model, modelHash, coords = {x,y,z}, heading, token }`; client creates a networked entity |
| `fh:spawn:created` | fh_core (client -> server) | `{ requestId, token, netId }`; netId must be a positive integer; adopted only if `source` is the chosen spawner, `token` is current, the entity exists, is network-owned by `source`, is held by no other request, is not a player ped, model matches, within `AdoptMaxDistance` |
| `fh:spawn:failed` | fh_core (client -> server) | `{ requestId, token, reason }` (reason truncated to 64); counts only from the current spawner + token; retries |
| `fh:spawn:delete` | fh_core (server -> client) | `{ requestId, token, netId? }`; client deletes only the entity it made for that token, and only if it has that netId when one is given (duplicate/stale/rejected/despawned). Never names the adopted netId |
| `fh:spawn:release` | fh_core (server -> client) | `{ requestId, token, netId }`; adopted: the client stops tracking it (server owns its lifetime) |
| `fh:spawn:client_ready` | fh_core (client -> server) | `{}`; this client can take spawn requests (only ready clients are picked) |
| `fh:dev:clientError` | fh_core (client -> server, dev only) | `{ resource, msg, traceback }` (strings; server truncates, drops unless convar `fh_dev` is 1, rate-limits 10/min per `source`, logs to `server/logs/client-errors.log`) |

Payloads for events not emitted by B4b are a contract proposal; the emitting lane may extend them additively.
