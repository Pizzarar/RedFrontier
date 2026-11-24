# Brainstorm Summary · A-LIFE (`a-life`)

> Rolling team brief (< ~5k tokens). Updated on every decision.

## Who's here
- Brainstorm: A-Life
- Lead: Ali1 Lead · a-life camp sim
- Workers: 0

## Done when
- v1 camp-ownership sim merged: clearing a camp flips it to law, outlaws retake it over time, flips move fh_trade shortages and fh_heat. Verified by the owner in-game (OWNER-TESTS).
- v2 items in Open are either planned or parked.

## Decided
- 2026-11-24, owner away ("push whatever you need", via Red3), so per R13 I acted on my leans. Assumptions are in plan `docs/plans/a-life-01-camp-sim.md`.
- Credit: "Implemented A-Life — Thanks to S.T.A.L.K.E.R. A-Life by GSC Game World" (plan, commits, CREDITS.md, release notes).
- Data split: @world/@core own faction and node data (hub: 8 factions: Lawmen per-state, rail+mining co, settlers' league, traders' guild, bounty hunters, swamp/mountain/desert gangs). A-Life owns the tick, flips and effects. v1 runs on today's 4 factions and 2 camps, data-driven.
- v1 guardrails (hub): squads are data on a node graph; peds spawn only via the fh_zones activationRadius wake and fh_core requestSpawn (server-owned, zone budget); no visible cross-map riding.
- New resource `fh_alife`. Persistence via KVP (no migration). A law-held camp does not activate. The player's `camp_cleared` flips the camp to law and adds `camp_clear` heat against the old owner. Flips call `setShortage`. Loot is picked by owner faction (`lootByFaction` hook).
- Primitives checked: the fh_zones events and state machine, fh_heat `addSource`/`camp_clear`, fh_trade `setShortage`, FhRegions, fh_core requestSpawn. No new vs command.
- @world confirmed (world-01, Wor1 rn-cb1d438f267f): faction ids stay stable (raiders = swamp gang, outlaws = mountain gang, rhodes_law = alias of lawmen); `kind` law/outlaw/neutral is being added; region/territory/camp shapes are unchanged; ambush nodes are optional in their block C; lootByFaction 8x3 is a @world Open item; camps sit at least 200 m from claims and towns. Relayed to Ali1.
- world-01 A2: lawmen will be listed in every region's factions, and gangs only in their own areas. Flip target = the first `kind == 'law'` faction in regions[r].factions; if there is none, log and skip. Relayed to Ali1.
- Hub: TOWN LOTS are never raid targets; WILDERNESS CLAIMS are raid-exposed (a v2 A-Life hook).

## Open
- v2: road ambush nodes; wilderness-claim raids (needs a homestead claim-class API); generated contracts (camp clear, bounty, escort, rescue) via fh_quests; owner-coloured blips (fh_ui places.lua is static); the 8x3 per-faction loot tables (@world data).

## In flight
- a-life-01 MERGED + pushed c1eed21. Follow-ups on main and pushed: idea-803 e7a2783 (no law heat inside your own town lot, via homestead lawSafeAt) and idea-805 53770c3 (review minors, factionLabel broadcasts); 82/1510/0. Lane idle. Waiting on the owner's in-game check, then the owner picks a v2 item from Open.
- a-life-02 B1 rules on a-life-b1 (61de786), W1 dropped: @world H ships regions[].ambush.
