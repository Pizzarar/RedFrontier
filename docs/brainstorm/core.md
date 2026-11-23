# Brainstorm Summary · CORE (`core`)

> Rolling team brief (< ~5k tokens). Updated on every decision.

## Who's here
- Brainstorm: Core
- Lead: ★ Cor3
- Workers: 1

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
- M1 order: B4c spawn contract → (B6b T1 camp fh_zones ∥ B6c soft death fh_death) → B6d stash home + end-to-end card. Wagons/chases out of scope. M1 small_safe = bulky (saddlebag carry); cargo reserved for M4 wagon loot. B6e: minimal per-character saddlebag, opens only mounted/near a horse; admin test-horse via B4c. Bulky stays out of backpack. Bulky to/from chest: `/saddlebag in|out <slot> [amt]` (workaround; pane stays backpack). Follow-up B6f pane toggle (todo).
- No GitHub push without owner OK (Pizzarar/RedFrontier not pre-approved).

## Open
- Horse ownership/stables: no lane owns it (B6e saddlebag is per-character stopgap).
- Aub: Cfx key + first join (OWNER-STEPS.md), then run OWNER-TESTS.md; flip fh_spike_gated after S1/S2.
- RSG + fh_inventory (fork, unwrapped) client errors still need Aub to send CitizenFX log from Main.
- Second client for camp-ownership spike (default: drop/rejoin).
- Push to GitHub: owner OK needed.

## In flight
- Plan: docs/brainstorm/plans/core-01-boot-to-m1.md (+ amendments: machine split, autonomy). Lead Cor2 rn-428940b6f1c5.
- Main 6307f28 = B1 boot, B2 boot-check+run-specs, B3 inventory fork, B4a container API+fh_inventory, B4b ledger/buffs/regions/events, B5 admin cmds+natives.md, B6a plot+chest, B-dev split+FH.safe. 179 specs green, Gemini PASS each. Nothing runtime-tested (no key yet). Unpushed.
- Lead Cor3 rn-625d84361e38. B4c, B6b (a8356e7), B6c (bb56aa2) merged; 248 specs. B6d 3c0bd99 in review; B6e saddlebag fix 8c5e5c6 (263 specs) in re-review. Then M1 code-complete, waits on Aub key + test session.
- B4c PASS (ca9aaff on core-b4c; Gemini re-review PASS; merged main 3c784d4): fh_core spawn-request contract, fh_spike_gated, spike-gated.md, OWNER-TESTS.md. 210 specs. B6b (rn-6e13b8f89183) + B6c (rn-21efce5bd3da) dispatched in parallel.
- B6b PASS (409d995, Gemini re-review 0/0/0) + B6c PASS (f5de5ae, Gemini re-review 0/0/0) merged main a8356e7/bb56aa2; 248 specs, syntax 48 files clean. B6d stash home + M1 end-to-end card dispatched (rn-7c4617c755e5, core-b6d).
- B6d PASS (3c0bd99, Gemini 0/0/3; nits folded into B6e) merged main 3a6e4d5; 249 specs. B6e saddlebag (9a037bd, 256 specs) nit fixes then Gemini review.
- B6e PASS (124f06c, Gemini tierA re-review 0/0/1) merged main 26eef2a: per-char saddlebag, server horse check, /saddlebag in|out transfer. 263 specs, [fh] syntax 51 clean. M1 CODE COMPLETE; unverified in-game. Follow-ups B6f (pane toggle), B6g (pickSlot info nit).
