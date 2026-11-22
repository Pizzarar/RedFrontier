# Brainstorm Summary · CORE (`core`)

> Rolling team brief (< ~5k tokens). Updated on every decision.

## Who's here
- Brainstorm: Core
- Lead: Core Lead · boot to M1
- Workers: 0

## Done when
- §6 M1 extraction loop playable end-to-end by Aub, boot-check + busted green.

## Decided
- 2026-11-22 Owner steer: boot first (join today), then M0, then M1 slice inside @core. Playable increment + owner test card per block.
- Server-data in repo at `server/`; secrets.cfg/artifacts/db/cache gitignored; portable MariaDB; no txAdmin.
- @spk path agreed: `server/resources/[spikes]/spk_*`, never ensured by default, ox_lib only.
- rsg-inventory: wrap if a server-side move veto exists, else fork-and-patch (B3 decides with file:line evidence).
- Spawn contract: RedM compiles out server CreatePed/CreateObject (ServerSetters.cpp:4-517 #ifndef STATE_RDR3). Server decides + owns state, client creates, server adopts netId. B4 adds fh_core spawn-request contract; S1 confirms.
- B3 (f9a6e63): rsg-inventory has no server veto (move main.lua:880 commits at 968) → FORK-AND-PATCH into [fh]/fh_inventory; size_class/value_base/illicit on shared items, condition/quality in info; world stashes must set coords.
- B2 test runner: tools/run-specs.py on preinstalled Python lupa 2.8 (Lua 5.4), plain-assert runner; nothing installed. busted optional later (specs runner-agnostic).
- No GitHub push without owner OK (Pizzarar/RedFrontier not pre-approved).

## Open
- Second client for camp-ownership spike (default: drop/rejoin).
- Push to GitHub: owner OK needed.

## In flight
- Plan docs/brainstorm/plans/core-01-boot-to-m1.md (B1 boot → B2 boot-check+busted → B3 inventory → B4 §4 → B5 admin+natives → B6+ M1). Lead rn-0e1a7e68e8de. B1 built on core/b1-boot (..ee8eef5), unmerged pending Aub's key + first join. B3 done (fork). B4b PASS c427eee; B4a1 fh_core dfd93ac (77 specs green); B4a2 fork in progress (Core11), then Gemini review of B4a. Blocker: owner Cfx key.
- B3 PASS (f9a6e63 on core-b3; Gemini review PASS): fork-and-patch rsg-inventory into [fh]/fh_inventory.
- B4b PASS (c427eee on core-b4b; Gemini re-review PASS): fh_economy ledger, fh_buffs, regions, events.md. Specs unexecuted (no Lua runner yet).
