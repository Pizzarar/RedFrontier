# A-Life: camps change hands

Clear an outlaw camp and the local law takes it over. A little later an outlaw squad marches back and retakes it. That loop changes what a camp drops and how a region's trade shortages move.

## What happens
- **You clear a camp** (see [Zones](fh_zones.md)). The region's law now holds it.
- **Roughly 20-30 minutes later** an outlaw squad retakes it (the wait is rolled each time, one tick per minute). The camp is outlaw-owned again.
- A law-held camp stays quiet: its outlaws do not wake when you walk in.

## Shortages
- Law holding a camp **relieves** the region's shortage; outlaws retaking it **raise** it again.
- The Heartlands tracks **salt** and Scarlett Meadows tracks **whiskey**. Shortages feed the freight jobs on the jobs board (see [Roads](roads.md)).

Timings and positions are unverified in game.

See also: [Zones](fh_zones.md) · [Roads](roads.md) · [Wiki index](../README.md)

Sources:
- `server/resources/[fh]/fh_alife/config.lua`
- `server/resources/[fh]/fh_alife/shared/alife_rules.lua`
- `server/resources/[fh]/fh_alife/server/main.lua`
- `server/resources/[fh]/fh_zones/shared/camp_rules.lua`
- `server/resources/[fh]/fh_core/docs/events.md`
