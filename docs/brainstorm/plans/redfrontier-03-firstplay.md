# redfrontier-03 · first-play (Red3, 2026-11-24)
Owner (first in-game session): "go ham, take all your leans, get all systems built for me to start playing; I want the intro tutorial."
Owner state: loads in on Media-Host, wagon spawns, inventory opens. Naked spawn, hunting native error, no tutorial, couldn't find a homestead plot.

## Blocks
| block | worker | touches | clashes with |
|---|---|---|---|
| A first-play fixes | rn-cfe17392a584 (wt rf-firstplay) | fh_hunting client, fh_* client natives, rsg-character | E (natives sweep may touch fh_trade/fh_cargo client) - small |
| B fh_tutorial intro | wt rf-tutorial | new fh_tutorial, server.cfg ensure, docs/wiki | D (server.cfg, 1 line) |
| C map blips + /where | wt rf-mapblips | fh_ui client blips, reads lane configs | none |
| D inbox quick fixes idea-743/744/750 | wt rf-inboxfix | server.cfg aces, docs/first-run, 0001 migration | B (server.cfg) |
| E second region + freight | wt rf-region2 | fh_zones/fh_trade/fh_cargo/fh_heat configs | A (minor) |
All run in parallel; clashes are one-line rebases.

## Decided
- fh_tutorial built now by hub (guide-02 lane is idle). Built on the fh_quests API, kind='tutorial', skippable, never blocking (guide.md:19-24).
- Checked existing primitives: fh_quests registerQuest (tutorial kind), fh_ui NUI. No blips existed in fh_* (grep AddBlip/BlipAddForCoords = 0).
- Merge order: A > D > C > E > B (B last, it points at things the others add).
