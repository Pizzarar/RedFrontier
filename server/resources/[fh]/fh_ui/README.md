# fh_ui (spec L10): shared NUI shell

One `ui_page`, vanilla JS/HTML/CSS, no build step. Lanes ship data, fh_ui ships screens. **fh_ui holds no game
authority**: it renders what a lane sends and relays validated player actions back to the lane that owns the screen.

## Events in (server/lane -> client, net events)
| Event | Payload | Effect |
|---|---|---|
| `fh:ui:open` | `{ screen, data }` | show the screen, call its `open(el, data)`; interactive screens take NUI focus |
| `fh:ui:update` | `{ screen, data }` | call `update(el, data)`; never changes focus |
| `fh:ui:close` | `{ screen }` | call `close(el)`, hide, release focus if no interactive screen remains |

Send with `TriggerClientEvent('fh:ui:open', src, { screen = 'insurance', data = {...} })`.

## Focus rules
- Passive HUD widgets (`FhUiRelay.passive`: `buffs`, `heat`, `bags`) never take focus. Every other screen is interactive and
  takes `SetNuiFocus(true, true)`.
- Esc or the `close` NUI callback closes interactive screens and releases focus. Esc (every interactive screen it
  closes) and a named close both relay action `close` to the owning lane (`fh:<lane>:ui_close`, payload `{}`).
- Focus is released when the last interactive screen closes and on `onResourceStop`.

## Events out (client -> server -> lane)
- NUI callback `action` -> `TriggerServerEvent('fh:ui:action', { screen, action, payload })`.
- Server validates in `shared/relay.lua`, then re-emits the **server** event `fh:<owning_lane>:ui_<action>` with
  ONE table (events.md convention): `{ src, screen, action, payload }` (`src` from `source`, never from the client). The lane revalidates everything: this is a request.
- Failures are dropped and logged (`[fh_ui] dropped action from <src>: <reason>`).

## Whitelist and limits (all in `shared/relay.lua`)
| Screen | Owning lane | Focus |
|---|---|---|
| `placeholder` | `ui` | interactive (U1 smoke) |
| `buffs` | `buffs` | passive |
| `heat` | `heat` | passive |
| `bags` | `death` | passive (U2) |
| `insurance` | `death` | interactive |
| `jobs` | `quests` | interactive |
| `station` | `homestead` | interactive |
| `fence` | `fence` | interactive |

Action must match `^[a-z_]{1,32}$`. Payload must be a table of plain data (strings, finite numbers, booleans, nested
tables with string/number keys), <= 2048 bytes estimated, depth <= 4. Rate limit: token bucket per player, 5/s, burst 10.
A new screen is added in one place (the `screens` table), plus `html/screens/<name>.js` and a `<script>` tag in
`html/index.html`.

## Writing a screen
`html/screens/<name>.js` calls `FH_UI.register('<name>', { open(el, data), update(el, data), close(el) })`.
`FH_UI.action(screen, action, payload)` sends an action; `FH_UI.close(screen)` asks the client to close it.
Style: one surreal accent only (the drifting sepia header), high-contrast body text, min 14px, no motion on numbers.

## In-game checklist (spec 9)
1. `ensure fh_ui` starts clean; no `[fh_ui]` errors in the server console.
2. As a player, `TriggerClientEvent('fh:ui:open', src, { screen = 'placeholder', data = { text = 'hi' } })` shows the panel; the mouse works.
3. Esc closes it and the mouse/camera control returns; a `fh:ui:ui_close` event reaches a test listener.
4. Ping button: a listener on `fh:ui:ui_ping` gets `{ src, screen, action, payload }` with the right `src`.
5. Open an unknown screen name: ignored, one `[fh_ui] open ignored` line, no focus taken.
6. A passive screen (`buffs`) opened alone never grabs the mouse; Esc leaves it up.
7. Spam the Ping button: extra clicks beyond the burst are logged as `rate_limited`, nothing crashes.
8. `restart fh_ui` while the panel is open: focus is released, controls work.

## Screen schemas
Later blocks append one subsection per screen: `data` shape for open/update, actions and payloads it may send.

### placeholder
`open/update` data `{ text? }`. Actions: `ping` `{ t }` -> `fh:ui:ui_ping` `{ src, screen, action, payload }`; `close` `{}`.

### buffs (passive HUD, U2)
Fed by fh_ui's own client listener on `fh:buffs:sync` (no lane code calls `fh:ui:open` for it). `open/update` data
`{ rows = { { id, label, magnitude?, remaining? } } }`, `remaining` = whole seconds at push time (counted down in the
NUI, re-pushed every 5 s and on each sync); empty `rows` hides the widget. No actions. Never takes focus.

### bags (passive HUD, owning lane `death`, U2)
Fed by `fh:death:bags` plus the `fh:death:bags` callback fetch at start. `open/update` data
`{ rows = { { id, remaining?, dir?, dist? } } }`: own bags only (entries with `mine == true`), `dir` = compass word
(N..NW or `here`), `dist` metres. No actions.

#### Contract requests (U2, routed by the lead; no lane was edited)
- **fh_death**: `fh:death:bags` entries are `{ id, x, y, z }` for every bag to every client. Needs, per player
  (send to each owner, not `-1`, or compute per-src): `mine = true` on the receiver's own bags and
  `remaining = <seconds until despawn>` (`expiresAt - os.time()` on the server, same field in the callback reply).
  Until then the bags widget shows nothing (ownership is never guessed client-side).
- **fh_buffs**: `fh:buffs:sync` entries carry `expires_at` on the server's `GetGameTimer()/1000` clock, which the
  client cannot compare to its own. Add `remaining = expires_at - now()` to each snapshot entry. Until then the
  buffs widget lists active buffs with `--` instead of a time.

### heat (passive)
`open/update` data `{ factions = { { id, label, level (0-100), tier } }, lay_low = { active, seconds_left? } }`. Producer (future
`fh_heat`) re-sends via `fh:ui:update` on `fh:heat:changed`. No actions.

### insurance (dialog, owner `death`)
`open` data `{ title, fee, delay_minutes, target_chest, note? }`. Actions: `confirm` `{}` (button or Enter), `cancel` `{}`; Esc relays `close`.
Lane revalidates fee and chest ownership.

### jobs (owner `quests`)
Jobs board, the real `fh_quests` board (README "Client sync: fh:quests:sync").
`open/update` data `{ region_id, expires_at, expired?, notice?, notice_kind?, offers = { { id, job_type, title, text, rewards = { money?, rep = { region_id, delta }?, items = { { name, amount } }? }, accepted } } }`.
`job_type` is data (freight, hunt_request, bounty ...), never switched on. An `update` without `offers` only changes the inline
`notice` (`notice_kind` `ok|error`); the board stays. `expired` boards show no offers. Accepted offers show "Accepted" and no button.
Actions: `accept` `{ id }` (relays `fh:quests:ui_accept`; the lane answers with a `notice` update), `close` `{}`. No autofocus, Enter does nothing.
The client adapter (`client/adapter.lua` + `shared/quests_view.lua`) turns each `fh:quests:sync` into an `update` while the screen is open.

### journal (owner `quests`)
Quest journal, the `journal[]` of `fh:quests:sync` (fh_quests README "Client sync").
`open/update` data `{ entries = { { quest_id, kind, title, giver?, region_id?, status, step?, steps_total?, step_text?, count?, need?, rewards = { money?, rep?, items? }, cooldown_until?, updated_at? } }, notice?, notice_kind? }`.
`status` is `active|done|failed|abandoned`; entries come active first, then history newest first. An `update` without `entries` only
changes the inline `notice`. Only active rows have an Abandon button (second click: "Confirm abandon?").
Actions: `abandon` `{ id }` (the quest_id; relays `fh:quests:ui_abandon`, the lane answers with a notice update and a fresh sync), `close` `{}`.
Opened by `/journal` -> `fh:quests:ui_journal_open`; the client adapter fills it from the last sync (it caches the latest snapshot). No autofocus, Enter does nothing.

### station (owner `homestead`)
`open/update` data `{ title, options = { { id, label, inputs = { { item, qty } }, outputs = { { item, qty } }, time_seconds, can_craft } } }`.
Actions: `craft` `{ id }` (button disabled when `can_craft` is false; the lane rechecks), `close` `{}`.

### fence (owner `fence`)
`open/update` data `{ title?, stock = { { id, label, price, qty, rare? } }, sell = { { id, label, price, qty } } }`.
Actions: `buy` `{ id, qty }`, `sell` `{ id, qty }` (qty clamped client-side to 1..listed qty; lane revalidates), `close` `{}`.

### Dev demo (fixtures)
`/fh_ui_demo <heat|insurance|jobs|station|fence>` opens that screen with `shared/fixtures.lua` data for the caller;
`/fh_ui_demo close [screen]` closes. Gated by the command ACE `command.fh_ui_demo` (same pattern as fh_homestead). Fixture actions relay to
lanes that do not exist yet and are simply unhandled.
