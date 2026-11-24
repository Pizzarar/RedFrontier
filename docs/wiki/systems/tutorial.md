# Tutorial

The first time a new character loads, a short guide starts. It walks you through your first day in seven text steps — no voice, no cutscenes. It never blocks anything, and you can skip it any time. Built but **not checked in game yet** (unverified).

## Commands

| Command | What it does |
|---|---|
| `/tutorial` | show the current step and re-set its waypoint |
| `/tutorial skip` | stop the tutorial for this character (survives relog) |
| `/tutorial restart` | start it again from the first step |

## The seven steps

1. Open your inventory with `I`.
2. Ride to the Valentine Trade Post and quote or sell.
3. Find a homestead plot and claim it with `/fh_claim`.
4. Open the jobs board with `/jobs`.
5. Hunt an animal, skin it, and sell the pelt to the trapper.
6. Meet a family quest giver — Ruth Hale.
7. Eat and drink to keep your needs up.

Steps with a destination set a yellow GPS route to it. The tutorial finishes on its own after step 7 and never
re-starts unless you ask it to.

## Good to know

- It is completely optional and never blocks anything — the [family questlines](quests.md) don't wait for it.
- Progress and the "done" mark are kept per character; skipping is too.
- Where a step matches a real game event (claiming a plot, selling a pelt), it advances on that. The rest advance on a
  simple check (opening the inventory, the board, the trade menu, or eating/drinking).

See also: [Getting started](../getting-started.md) · [Quests](quests.md) · [Wiki index](../README.md)

Sources:
- `server/resources/[fh]/fh_tutorial/README.md`
- `server/resources/[fh]/fh_tutorial/shared/tutorial.lua`
- `server/resources/[fh]/fh_tutorial/server/main.lua`
- `server/resources/[fh]/fh_tutorial/client/main.lua`
- `server/resources/[fh]/fh_quests/README.md`
