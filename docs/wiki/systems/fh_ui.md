# UI

fh_ui is the shared screen layer other systems use to show panels. It has no game logic of its own: it shows what a system sends and passes your clicks back.

## Screens you can see
- **Jobs board** (`/jobs`): the offers on the board, with an Accept button. Accepted offers say "Accepted". See [Quests](quests.md).
- **Journal** (`/journal`): your quests. Active ones have an Abandon button, and a second click confirms.
- **Buffs:** a HUD list of your active buffs with their time left. See [Buffs](fh_buffs.md).
- **Bags:** a HUD list of your own dropped bags, with direction, distance and time left. See [Death](fh_death.md).
- **Insurance:** a confirm dialog.

Other screens are made but their systems aren't wired in yet (unverified): heat, workbench (station) and fence.

## Mouse and keys
- HUD widgets (buffs, heat, bags) never take your mouse.
- Every other screen takes the mouse. **Esc** closes it and gives control back.
- On the jobs board and journal, Enter does nothing, so you can't accept something by accident.
- Clicking too fast gets ignored (5 actions a second).

## Map blips and `/where`

fh_ui puts a **map blip** on every findable place so you can see where things are from the map or minimap: each
homestead plot, the Valentine Trade Post, the trapper, the family quest givers, the jobs board, the outlaw camp,
the crafting stations and the fence stops. Each blip is named ("Homestead plot", "Trade Post", …). Blips are
unverified in game, and the sprite names are guesses that still need a real in-game check.

**`/where`** lists those places and marks one as your destination:

- `/where` lists every place with its distance, nearest first.
- `/where tradepost` (or `trade`), `/where plot` (nearest **unclaimed** homestead plot), `/where trapper`,
  `/where camp`, `/where board`, `/where giver`, `/where station`, `/where fence` mark the nearest of that kind and
  print its name and distance.

RedM has no "set GPS waypoint" native, so `/where` marks your destination with a named blip instead of the pause-map
red X. See [Controls](../controls.md).

## Test panel
A `placeholder` panel exists for testing, and admins have `/fh_ui_demo`.

See also: [Wiki index](../README.md)

Sources:
- `server/resources/[fh]/fh_ui/README.md`
- `server/resources/[fh]/fh_ui/shared/relay.lua`
- `server/resources/[fh]/fh_quests/README.md`
