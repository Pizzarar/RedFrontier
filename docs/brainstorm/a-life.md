# Brainstorm Summary · A-LIFE (`a-life`)

> Rolling team brief (< ~5k tokens). Updated on every decision.

## Who's here
- Brainstorm: A-Life
- Lead: ★ AL3
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
- @world world-03 block H (Wor1): regions[r].ambush = {id,x,y,z,label,verified=false}, 2-3 per region × 15 regions, on roads, at least 200 m from towns and claims. A-Life keys nodes by id (fallback `<region>:ambush:<i>`) and drops or returns squads whose node is gone. Relayed to Ali1.
- Hub: TOWN LOTS are never raid targets; WILDERNESS CLAIMS are raid-exposed (a v2 A-Life hook).

## Open
- a-life-04 candidates: escort/rescue contracts; owner-coloured blips; 8x3 loot (@world). Inbox: idea-898/899/900, 807.

## In flight
- a-life-01 MERGED + pushed c1eed21 (+ follow-ups idea-803 e7a2783, idea-805 53770c3; 82/1510/0). The owner's in-game check is pending (OWNER-TESTS "A-life: camp ownership").
- a-life-02 (`docs/plans/a-life-02-roads-raids.md`): outlaw squads on road ambush nodes that materialise on foot near players, kills weaken retakes, law reinforce squads as data, `alife_contract` board jobs. Handed to Ali1, now AL2 rn-700965813307 after a lead handoff; 2026-11-24 per Red3 ("use the quota"). W1 dropped by AL2: relies on @world world-03 H for regions[].ambush; with no nodes, ambush is a no-op. B1 MERGED+pushed 4937d4f (99/1833/0). B2 7261650 + B3 5077d49 being joined on a-life-b23 (rn-21134fee7048); squad_wiped payload fixed as {squad_id,node_id,region_id,faction,participants=citizenids} (matches camp_cleared, fh_zones/server/main.lua:154). b23 joined c9aef99 (100/1852/0), Gemini PASS 0/0/1 c9aef99; B4 PASS d5301ac. B2+B3+B4 on a-life-b4 047aed9 (main merged in, 105/1947/0), slot asked of Red4. Inert in-game until @world world-i (regions[].ambush) merges. Follow-ups queued idea-898 (2D vs 3D range), 899 (squad heat, with 807), 900.
- a-life-02 MERGED + pushed (047aed9 on origin). Inert until @world world-i regions[].ambush merges.
- a-life-03 (`docs/plans/a-life-03-claim-raids.md`): online-only raids on wilderness claims (town lots never), warning first, fight at home or lose 2 stacks from chest 1 to the camp stash; C0 = @homestead plotInfo extension. Handed to the lead 2026-11-25.
- a-life-03 progress: C0+C1 merged 6b98510. C2 PASS 0/0/1 e9b16b5 (Gemini). C2b dropped (Buddy: stolen goods go in an fh_alife per-camp ledger, delivered on camp_cleared). C2c ledger + C3 on a-life-c2c, rn-56a8edede5cd (Opus, tierA). Lead AL3 rn-3421c23f06df.
- Decision 2026-11-25: stolen claim goods go into a persisted per-camp loot ledger in fh_alife (cap 20 stacks) and are paid into the camp stash on camp_cleared. C2b (fh_zones stash-wipe change) dropped: a boot wipe would lose goods at every restart window. C2 Gemini PASS 0/0/1 (idea-961 rides along).
- a-life-03 PASS: MERGED ff (C2 + C2c loot ledger + fixes + C3 OWNER-TESTS) on 5fca77a, 132/2428/0. Owner in-game check pending (OWNER-TESTS "A-life: claim raids"). Follow-ups idea-958/959/987/1006.
- a-life-fx1 PASS: MERGED ff (idea-959 serial-safe raid steal picks, idea-1006 L2/L3), Gemini 0/0/0. Open: idea-958 (@homestead), 987 (@core), 1014.
- a-life-fx2 PASS: MERGED (idea-958 claimsReady boot gate, idea-1031 one bag + leftovers, idea-1014 invalid-entry log), Gemini 0/0/2; minors idea-1055.
