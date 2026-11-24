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
| `fh:economy:rep_changed` | fh_economy | `{ src, citizenid, region_id, delta, value, reason }`: `src` is `nil` when written by `repByCitizenid` for an offline character; key on `citizenid` |
| `fh:economy:charged` | fh_economy | `{ src, citizenid, amount, reason, region_id, ledger_id }`: a `charge` debit (B7); `amount` is the positive sum taken |
| `fh:economy:credited` | fh_economy | `{ src, citizenid, amount, reason, region_id, ledger_id, queued }`: money added by `credit` (core-04 E2). `queued = false`: paid online at once (`ledger_id` = its `credit` row); `queued = true`: a pending credit paid on character load (no `ledger_id`) |
| `fh:buffs:applied` | fh_buffs | `{ src, buff_id, magnitude, expires_at, refreshed }` |
| `fh:homestead:claimed` | fh_homestead | `{ src, citizenid, plot_id, region_id, class }`; `class` = `'claim'` or `'town_lot'` (homestead-02 H8; also fired for a bought lot) |
| `fh:homestead:lot_bought` | fh_homestead | `{ src, citizenid, plot_id, region_id, price }`: a town lot bought with `/fh_buylot` / `buyLot` (after `claimed`); `price` = dollars charged |
| `fh:homestead:open_chest` | fh_homestead (client -> server request) | `{ plot_id }` (string); server revalidates owner + reach, `src` from `source` |
| `fh:homestead:unclaimed` | fh_homestead | `{ src, citizenid, plot_id }` (citizenid = former owner; src 0 = console) |
| `fh:homestead:spilled` | fh_homestead | `{ src, citizenid, plot_id, reason, stashes = { { stash_id, items = { { item, count } } } } }`: plot chest items destroyed on unclaim (H13); `reason` = `force unclaim` (admin) or `ITEM LOST: added during unclaim` (final sweep); only stashes whose clear was read back empty |
| `fh:spawn:create` | fh_core (server -> chosen client) | `{ requestId, kind, model, modelHash, coords = {x,y,z}, heading, token }`; client creates a networked entity |
| `fh:spawn:created` | fh_core (client -> server) | `{ requestId, token, netId }`; netId must be a positive integer; adopted only if `source` is the chosen spawner, `token` is current, the entity exists, is network-owned by `source`, is held by no other request, is not a player ped, model matches, within `AdoptMaxDistance` |
| `fh:spawn:failed` | fh_core (client -> server) | `{ requestId, token, reason }` (reason truncated to 64); counts only from the current spawner + token; retries |
| `fh:spawn:delete` | fh_core (server -> client) | `{ requestId, token, netId? }`; client deletes only the entity it made for that token, and only if it has that netId when one is given (duplicate/stale/rejected/despawned). Never names the adopted netId |
| `fh:spawn:release` | fh_core (server -> client) | `{ requestId, token, netId }`; adopted: the client stops tracking it (server owns its lifetime) |
| `fh:spawn:client_ready` | fh_core (client -> server) | `{}`; this client can take spawn requests (only ready clients are picked) |
| `fh:dev:clientError` | fh_core (client -> server, dev only) | `{ resource, msg, traceback }` (strings; server truncates, drops unless convar `fh_dev` is 1, rate-limits 10/min per `source`, logs to `server/logs/client-errors.log`) |
| `fh:zones:camp_activated` | fh_zones | `{ camp_id, region_id }`; a player came within `activationRadius` of an idle camp, its peds are being requested |
| `fh:zones:camp_cleared` | fh_zones | `{ camp_id, region_id, loot, participants }`; every adopted ped is dead (server-checked); loot = array of `{ name, amount, info? }` placed in the camp stash; participants = array of citizenids of players within `activationRadius` of the camp centre at clear (empty table if none; additive, optional for listeners) |
| `fh:zones:camp_respawned` | fh_zones | `{ camp_id, region_id }`; `respawnMinutes` elapsed, bodies despawned, stash emptied, camp idle again |
| `fh:zones:ped_dead` | fh_zones (client -> server) | `{ tag }`; a hint only: believed from a player within activation radius + 25 m of the camp, then the server re-reads the ped's health itself |
| `fh:zones:open_loot` | fh_zones (client -> server request) | `{ camp_id }`; only honoured once the camp is cleared; `fh_core.open` re-checks reach server-side |
| `fh:spawn:adopted` | fh_core (LOCAL client event, post-adopt hook) | `{ requestId, tag, owner, kind, netId, entity }`; fires on the spawning client when the server released the adopted entity (again after a re-request, on the new spawner). `tag`/`owner` ride on `fh:spawn:create` |
| `fh:saddlebag:open` | fh_core (client -> server request) | `{ netId }`; the horse the player rides or stands next to. The server checks the entity exists, is a horse and is within reach of the server-side ped (`FhSaddlebagRules.canAccess`), then opens the character's saddlebag |
| `fh:saddlebag:transfer` | fh_core (client -> server request) | `{ netId, dir = 'in' or 'out', slot, amount? }`; moves a stack between the container the server says the player has open and their saddlebag. The server re-checks the horse and reach; one `fh_core.move` applies it (events `fh:inventory:moved` / `refused` fire as for any move) |
| `fh:alife:camp_flipped` | fh_alife | `{ camp_id, region_id, from, to }`; a camp changed owner (cleared -> law, or outlaw retake). `from`/`to` are faction ids |

## fh_alife exports
- `exports.fh_alife:getOwner(campId)` -> `string|nil` factionId: the camp's effective owner (an explicit flip, else its territory's default faction).
- `exports.fh_alife:isLawHeld(campId)` -> `boolean`: whether the camp's owner is a law faction.

Payloads for events not emitted by B4b are a contract proposal; the emitting lane may extend them additively.
