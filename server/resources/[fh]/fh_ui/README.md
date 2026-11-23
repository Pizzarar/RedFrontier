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
- Passive HUD widgets (`FhUiRelay.passive`: `buffs`, `heat`) never take focus. Every other screen is interactive and
  takes `SetNuiFocus(true, true)`.
- Esc or the `close` NUI callback closes interactive screens and releases focus. A named close also relays action
  `close` to the owning lane (`fh:<lane>:ui_close`).
- Focus is released when the last interactive screen closes and on `onResourceStop`.

## Events out (client -> server -> lane)
- NUI callback `action` -> `TriggerServerEvent('fh:ui:action', { screen, action, payload })`.
- Server validates in `shared/relay.lua`, then re-emits the **server** event `fh:<owning_lane>:ui_<action>` with
  `(src, payload)` (`src` from `source`, never from the client). The lane revalidates everything: this is a request.
- Failures are dropped and logged (`[fh_ui] dropped action from <src>: <reason>`).

## Whitelist and limits (all in `shared/relay.lua`)
| Screen | Owning lane | Focus |
|---|---|---|
| `placeholder` | `ui` | interactive (U1 smoke) |
| `buffs` | `buffs` | passive |
| `heat` | `heat` | passive |
| `insurance` | `death` | interactive |
| `contracts` | `trade` | interactive |
| `station` | `homestead` | interactive |
| `fence` | `economy` | interactive |

Action must match `^[a-z_]{1,32}$`. Payload must be a table of plain data (strings, finite numbers, booleans, nested
tables with string/number keys), <= 2048 bytes estimated, depth <= 4. Rate limit: token bucket per player, 5/s, burst 10.
A new screen is added in one place (the `screens` table), plus `html/screens/<name>.js` and a `<script>` tag in
`html/index.html`.

## Writing a screen
`html/screens/<name>.js` calls `FH_UI.register('<name>', { open(el, data), update(el, data), close(el) })`.
`FH_UI.action(screen, action, payload)` sends an action; `FH_UI.close(screen)` asks the client to close it.
Style: one surreal accent only (the drifting sepia header), high-contrast body text, min 14px, no motion on numbers.

## Screen schemas
Later blocks append one subsection per screen: `data` shape for open/update, actions and payloads it may send.

### placeholder
`open/update` data `{ text? }`. Actions: `ping` `{ t }` -> `fh:ui:ui_ping`; `close` `{}`.
