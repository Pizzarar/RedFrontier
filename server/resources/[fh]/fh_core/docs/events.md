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
| `fh:death:dropped` | death lane | `{ src, citizenid, container_id, coords }` |
| `fh:death:recovered` | death lane | `{ src, citizenid, container_id }` |
| `fh:zones:camp_cleared` | zones lane | `{ src, territory_id, tier }` |
| `fh:economy:paid` | fh_economy | `{ src, citizenid, amount, reason, region_id, ledger_id }` |
| `fh:economy:rep_changed` | fh_economy | `{ src, citizenid, region_id, delta, value, reason }` |
| `fh:buffs:applied` | fh_buffs | `{ src, buff_id, magnitude, expires_at, refreshed }` |
| `fh:homestead:claimed` | fh_homestead | `{ src, citizenid, plot_id, region_id }` |
| `fh:homestead:open_chest` | fh_homestead (client -> server request) | `{ plotId }` (string); server revalidates owner + reach, `src` from `source` |
| `fh:homestead:unclaimed` | fh_homestead | `{ src, citizenid, plot_id }` (citizenid = former owner; src 0 = console) |
| `fh:dev:clientError` | fh_core (client -> server, dev only) | `{ resource, msg, traceback }` (strings; server truncates, drops unless convar `fh_dev` is 1, rate-limits 10/min per `source`, logs to `server/logs/client-errors.log`) |

Payloads for events not emitted by B4b are a contract proposal; the emitting lane may extend them additively.
