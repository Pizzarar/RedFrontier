# Tutorial

The first time a new character loads, a short guide starts. It walks you through your first day in twelve text steps — no voice, no cutscenes. It never blocks anything, and you can skip it any time. Built but **not checked in game yet** (unverified).

## Commands

| Command | What it does |
|---|---|
| `/tutorial` | show the current step and re-set its waypoint |
| `/tutorial skip` | stop the tutorial for this character (survives relog) |
| `/tutorial restart` | start it again from the first step |
| `/guide [id]` | open the read-only in-game Field Guide (optionally jumping to a topic id, e.g. `/guide hunting`) |

## The twelve steps

1. **Greeting** — a short welcome; the inventory prompt follows.
2. Open your inventory with `I`.
3. Eat and drink to keep your needs up.
4. Find a homestead plot and claim it with `/fh_claim`.
5. Open your homestead chest to stash your gear.
6. Ride to the Valentine Trade Post and quote or sell.
7. Hunt an animal, skin it, and sell the pelt to the trapper.
8. Restore a worn gun at your workbench with `/fh_restore`.
9. Open the jobs board with `/jobs`.
10. Haul a cargo run: get a wagon and move a crate into it.
11. Find the fence and sell your illicit goods.
12. Meet a family quest giver — Ruth Hale.

The order is deliberate: needs first, then a home and stash, then shopping, then jobs once the first sale has proved
the money loop, the fence eleventh because it is the crime loop, and the family giver last as the graduation. It lives in
`FhTutorialConfig.order` (`fh_tutorial/config.lua`), not in code, so reordering it is a config edit; unknown step ids
are dropped with a warning.

Steps with a destination set a yellow GPS route to it. The tutorial finishes on its own after the last step and never
re-starts unless you ask it to.

### How each step advances

| id | Advances on | Source |
|---|---|---|
| `greeting` | client check `fh:tutorial:check greeting` (ack after 2.5 s) | `fh_tutorial/client/main.lua:42` |
| `inventory` | client check `rsg-inventory:client:open` | `fh_inventory/server/main.lua:1169`,`:1171` |
| `eat_drink` | server event `fh:buffs:applied` (`well_fed`/`hydrated`) | `fh_buffs/server/main.lua:19` |
| `claim_plot` | `fh:homestead:claimed` | `fh_homestead/server/main.lua:219` |
| `stash` | client check `rsg-inventory:client:open` where `other.id` = `fh:chest:<plot>:<n>` | `fh_inventory/server/main.lua:1169`,`:1171` · `fh_homestead/shared/plot_rules.lua:107` |
| `trade_post` | client check `fh:trade:menu` | `fh_trade/server/main.lua:276` |
| `hunt` | `fh:hunting:pelt_sold` | `fh_hunting/shared/sell.lua:157` |
| `gunsmith` | client check `fh_gunsmith:conditionChanged` (after `/fh_restore`) | `fh_gunsmith/server/main.lua:94` |
| `jobs` | client check `fh:ui:open` screen `jobs` | `fh_quests/server/ui.lua:11` |
| `cargo` | server event `fh:cargo:wagon_spawned` | `fh_cargo/server/main.lua:83` |
| `fence` | client check `fh:ui:open` screen `fence` | `fh_fence/client/main.lua:17` |
| `family` | `talk` npc `npc_hale` | `fh_quests/shared/givers.lua:5` |

## Field Guide

Type `/guide` any time to open the read-only in-game Field Guide (through [UI](fh_ui.md)). It has one short page for
every system in this wiki, with key controls and the matching wiki path. Switching pages happens client-side with no
server round trip, and `/guide <id>` jumps straight to that topic.

## Good to know

- It is completely optional and never blocks anything — the [family questlines](quests.md) don't wait for it.
- Progress and the "done" mark are kept per character; skipping is too. Progress is stored by step id, so a future
  reorder keeps an in-flight character on the same logical step.
- Where a step matches a real game event (claiming a plot, selling a pelt, spawning a wagon), it advances on that.
  The rest advance on a simple check (opening the inventory, the chest, the board, the trade menu, the fence, or
  restoring a gun at a workbench); the greeting acknowledges itself after a couple of seconds on screen.

See also: [Getting started](../getting-started.md) · [Quests](quests.md) · [Wiki index](../README.md)

Sources:
- `server/resources/[fh]/fh_tutorial/config.lua`
- `server/resources/[fh]/fh_tutorial/README.md`
- `server/resources/[fh]/fh_tutorial/shared/tutorial.lua`
- `server/resources/[fh]/fh_tutorial/shared/field_guide.lua`
- `server/resources/[fh]/fh_tutorial/server/main.lua`
- `server/resources/[fh]/fh_tutorial/client/main.lua`
- `server/resources/[fh]/fh_quests/README.md`
- `server/resources/[fh]/fh_homestead/config.lua`
- `server/resources/[fh]/fh_cargo/server/main.lua`
- `server/resources/[fh]/fh_gunsmith/server/main.lua`
- `server/resources/[fh]/fh_fence/client/main.lua`
- `server/resources/[fh]/fh_inventory/server/main.lua`
- `server/resources/[fh]/fh_trade/server/main.lua`
- `server/resources/[fh]/fh_hunting/shared/sell.lua`
- `server/resources/[fh]/fh_buffs/server/main.lua`
- `server/resources/[fh]/fh_quests/shared/givers.lua`
