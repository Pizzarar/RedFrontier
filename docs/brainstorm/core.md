# Brainstorm Summary · CORE (`core`)

> Rolling team brief (< ~5k tokens). Updated on every decision.

## Who's here
- Brainstorm: Core
- Lead: ★ Cor2
- Workers: 2

## Done when
- §6 M1 extraction loop playable end-to-end by Aub, boot-check + busted green.

## Decided
- 2026-11-22 Owner steer: boot first (join today), then M0, then M1 slice inside @core. Playable increment + owner test card per block.
- Server-data in repo at `server/`; secrets.cfg/artifacts/db/cache gitignored; portable MariaDB; plain FXServer default (txAdmin optional).
- @spk path agreed: `server/resources/[spikes]/spk_*`, never ensured by default, ox_lib only.
- Spawn contract: RedM compiles out server CreatePed/CreateObject (ServerSetters.cpp:4-517 #ifndef STATE_RDR3). Server decides + owns state, client creates, server adopts netId. B4 adds fh_core spawn-request contract; S1 confirms.
- B3 (f9a6e63): rsg-inventory has no server veto (move main.lua:880 commits at 968) → FORK-AND-PATCH into [fh]/fh_inventory; size_class/value_base/illicit on shared items, condition/quality in info; world stashes must set coords.
- B2 test runner: tools/run-specs.py on preinstalled Python lupa 2.8 (Lua 5.4), plain-assert runner; nothing installed. busted optional later (specs runner-agnostic).
- Machine split: DevPC hosts server (FXServer, MariaDB, key); Main PC plays via Tailscale 100.83.196.251:30120. txAdmin optional. B-dev: OWNER-STEPS rewrite + firewall step + FH.safe client-error forwarding to server/logs/client-errors.log.
- 2026-11-22 autonomy (Aub 'go go go' via Overlord): hold lifted; only in-game RESULT steps wait on Aub. S1/S2-dependent behaviour behind convar fh_spike_gated (default true, conservative; listed in fh_core/docs/spike-gated.md). Test cards accumulate in OWNER-TESTS.md for one top-to-bottom session.
- M1 order: B4c spawn contract → (B6b T1 camp fh_zones ∥ B6c soft death fh_death) → B6d stash home + end-to-end card. Wagons/chases out of scope.
- No GitHub push without owner OK (Pizzarar/RedFrontier not pre-approved).

## Open
- Aub: Cfx key + first join (OWNER-STEPS.md), then run OWNER-TESTS.md; flip fh_spike_gated after S1/S2.
- RSG + fh_inventory (fork, unwrapped) client errors still need Aub to send CitizenFX log from Main.
- Second client for camp-ownership spike (default: drop/rejoin).
- Push to GitHub: owner OK needed.

## In flight
- Plan: docs/brainstorm/plans/core-01-boot-to-m1.md (+ amendments: machine split, autonomy). Lead Cor2 rn-428940b6f1c5.
- Main 6307f28 = B1 boot, B2 boot-check+run-specs, B3 inventory fork, B4a container API+fh_inventory, B4b ledger/buffs/regions/events, B5 admin cmds+natives.md, B6a plot+chest, B-dev split+FH.safe. 179 specs green, Gemini PASS each. Nothing runtime-tested (no key yet). Unpushed.
- Now: B4c spawn contract → B6b ∥ B6c → B6d.
- B4c PASS (ca9aaff on core-b4c; Gemini re-review PASS; merged main 3c784d4): fh_core spawn-request contract, fh_spike_gated, spike-gated.md, OWNER-TESTS.md. 210 specs. B6b (rn-6e13b8f89183) + B6c (rn-21efce5bd3da) dispatched in parallel.
