# Brainstorm Summary · CORE (`core`)

> Rolling team brief (< ~5k tokens). Updated on every decision.

## Who's here
- Brainstorm: Core
- Lead: ★ Cor2
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
- Machine split: DevPC hosts server (FXServer, MariaDB, key); Main PC plays via Tailscale 100.83.196.251:30120. txAdmin optional. B-dev: OWNER-STEPS rewrite + firewall step + FH.safe client-error forwarding to server/logs/client-errors.log.
- No GitHub push without owner OK (Pizzarar/RedFrontier not pre-approved).

## Open
- RSG (non-fh) client errors still need Aub to send CitizenFX log from Main.
- Second client for camp-ownership spike (default: drop/rejoin).
- Push to GitHub: owner OK needed.

## In flight
- Plan docs/brainstorm/plans/core-01-boot-to-m1.md (B1 boot → B2 boot-check+busted → B3 inventory → B4 §4 → B5 admin+natives → B6+ M1). Lead Cor2 rn-428940b6f1c5. Main 65f750f (B1-B6a), 171 specs, unpushed. HELD: no dispatch until Aub's live boot passes (key). Then B6a in-game test, B4c (after S1), B6b-d. Live boot + B4c wait on Aub key / S1.
- B3 PASS (f9a6e63 on core-b3; Gemini review PASS): fork-and-patch rsg-inventory into [fh]/fh_inventory.
- B4b PASS (c427eee on core-b4b; Gemini re-review PASS): fh_economy ledger, fh_buffs, regions, events.md. Specs unexecuted (no Lua runner yet).
- B4a PASS (7d32208 on core-b4a2; Gemini re-review PASS): fh_core container API + fh_inventory fork. Lead Cor2 rn-428940b6f1c5. Main 65f750f (B1-B6a), 171 specs, unpushed. HELD: no dispatch until Aub's live boot passes (key). Then B6a in-game test, B4c (after S1), B6b-d. Live boot + B4c wait on Aub key / S1.
- Spec runner fix PASS (18cd2be, merged to main cdbd1a9): all 8 specs on fh_prelude runner, 157 tests green. Next: keyed boot (Cfx key), then B4c after S1, B5.
- B5 PASS (ef41125 on core-b5; Gemini re-review PASS; merged to main b0eacf6): admin cmds fh_give/fh_heat(stub)/fh_tp/fh_dump, natives.md (spike natives candidate, unproven), rep() pcall. 163 specs green. Spawn cmds moved to B4c.
- B6a PASS-WITH-NITS (bff072e on core-b6a; Gemini re-review; merged main 65f750f): fh_homestead plot claim + owner chest, migration 0003. 171 specs green. Not runtime-tested. HOLD further core dispatch until Aub's live boot.
- B-dev PASS (ab96962 on core-bdev; Gemini re-review PASS; merged main 6307f28): OWNER-STEPS DevPC/Main PC split (one start path, firewall 30120, Tailscale connect), FH.safe client-error return to server/logs/client-errors.log gated by fh_dev; fh_inventory exception documented. 179 specs. Core HELD until live boot.
