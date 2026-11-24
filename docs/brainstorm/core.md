# Brainstorm Summary · CORE (`core`)

> Rolling team brief (< ~5k tokens). Updated on every decision.

## Who's here
- Brainstorm: Core
- Lead: ★ Cor3
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
- Machine split: DevPC hosts server (FXServer, MariaDB, key); Main PC plays via NordVPN Meshnet (host 'Media-Host') 100.102.50.11:30120 (LAN 192.168.1.135). txAdmin optional. B-dev: OWNER-STEPS rewrite + firewall step + FH.safe client-error forwarding to server/logs/client-errors.log.
- 2026-11-22 autonomy (Aub 'go go go' via Overlord): hold lifted; only in-game RESULT steps wait on Aub. S1/S2-dependent behaviour behind convar fh_spike_gated (default true, conservative; listed in fh_core/docs/spike-gated.md). Test cards accumulate in OWNER-TESTS.md for one top-to-bottom session.
- M1 order: B4c spawn contract → (B6b T1 camp fh_zones ∥ B6c soft death fh_death) → B6d stash home + end-to-end card. Wagons/chases out of scope. M1 small_safe = bulky (saddlebag carry); cargo reserved for M4 wagon loot. B6e: minimal per-character saddlebag, opens only mounted/near a horse; admin test-horse via B4c. Bulky stays out of backpack. Bulky to/from chest: `/saddlebag in|out <slot> [amt]` (workaround; pane stays backpack). Follow-up B6f pane toggle (todo).
- Player count: owner + up to 5 friends (sv_maxclients 6, unlisted, allowlist, NordVPN Meshnet; was Tailscale), up from spec §2's 1-4. B-access: first joiner = admin (only while none exists), friends never admin; allowlist via rsg-core ACE whitelist + gitignored allowlist.cfg; fh_allow <license> admin cmd + rejected-connect log line.
- No GitHub push without owner OK (Pizzarar/RedFrontier not pre-approved).
- 2026-11-23 idea-616(2) closed: covered by @roads fh_cargo nearestWagon+getWagon (roads-r1 32817e7); roads briefed hunting.
- 2026-11-23 core-03 carried-inventory API (docs/brainstorm/plans/core-03-carried-api.md): extend addItem/removeItem to carried refs {backpack|equipped,id=src}, new setItemInfo(ref,slot,info,expectName?), requestOfNetId(netId) for existing despawn. Checked fh_core exports + fh_inventory fh_api.lua first. Covers roads gap, idea-615/643/687/689/616(1); 600/692 covered by B7.
- 2026-11-23 core-04 inbox sweep (docs/brainstorm/plans/core-04-inbox-sweep.md): 612/613 caps, 610 buffs remaining, 609 death bags mine/remaining, 611/699 run-specs, 700 offline credit = pending-credit queue claimed on load (raw money UPDATE races rsg save), B7-nit.
- 2026-11-23 core-05 (plans/core-05-gun-parts-loot.md): gun_parts outlaw loot 0.8 x2-3 + unpend crafting sources spec. idea-721 declined: fh_core timeout cannot stop the late write; root fix = fence-side token.
- 2026-11-24 Host network moved Tailscale -> NordVPN Meshnet (Media-Host), idea-744. core-06 infra sweep (743 ace grants, 744 docs, 750 idempotent rocks_zones INSERT) dispatched by lead as I1 rn-c1105e8f1c5c tierA; 762 bounced to @roads.
- 2026-11-24 core-07 (plans/core-07-keyless-hardening.md), quota push: L1 static contract lint (exports/events/items), A1 tierA money audit, S1 fh_core edge specs, B6f pane toggle DARK behind convar fh_saddlebag_pane=false (flip after owner saddlebag RESULT; then remove /saddlebag in|out). Lane SPEC.md written (docs/lanes/core/SPEC.md, uncommitted, lead commits in merge slot).

## Open
- Horse ownership/stables: no lane owns it (B6e saddlebag is per-character stopgap).
- Aub: Cfx key + first join (OWNER-STEPS.md), then run OWNER-TESTS.md; flip fh_spike_gated after S1/S2.
- RSG + fh_inventory (fork, unwrapped) client errors still need Aub to send CitizenFX log from Main.
- Second client for camp-ownership spike (default: drop/rejoin).
- Push to GitHub: owner OK needed.

## In flight
- 11-23 post-thaw PASS+merged local main (unpushed): B-access 495621d, B7 334642c (Gemini tierA PASS 0/0/1; fix brief plans/core-02-b7-fix.md), idea-614 b63a340 (Sonnet PASS 0/0/0). 23 specs/431 tests green. Siblings notified. Nit B7-nit (README Tests list) queued.
- B7 contracts batch (plan core-02): charge/getRep/removeItem/wagon spawn kind/heat delegate/registerItems for @progression/@homestead/@roads (idea-600/602/603 merged).
- Plan: docs/brainstorm/plans/core-01-boot-to-m1.md (+ amendments: machine split, autonomy). Lead Cor2 rn-428940b6f1c5.
- Main 6307f28 = B1 boot, B2 boot-check+run-specs, B3 inventory fork, B4a container API+fh_inventory, B4b ledger/buffs/regions/events, B5 admin cmds+natives.md, B6a plot+chest, B-dev split+FH.safe. 179 specs green, Gemini PASS each. Nothing runtime-tested (no key yet). Unpushed.
- Lead Cor3 rn-625d84361e38, IDLE. Main de086db (M1 + B6g + B-run one-click first-run.cmd), 267 specs, unverified in-game, unpushed. B6f held for test RESULTs. Waiting on Aub: key+firewall → OWNER-STEPS → OWNER-TESTS → push OK.
- B4c PASS (ca9aaff on core-b4c; Gemini re-review PASS; merged main 3c784d4): fh_core spawn-request contract, fh_spike_gated, spike-gated.md, OWNER-TESTS.md. 210 specs. B6b (rn-6e13b8f89183) + B6c (rn-21efce5bd3da) dispatched in parallel.
- B6b PASS (409d995, Gemini re-review 0/0/0) + B6c PASS (f5de5ae, Gemini re-review 0/0/0) merged main a8356e7/bb56aa2; 248 specs, syntax 48 files clean. B6d stash home + M1 end-to-end card dispatched (rn-7c4617c755e5, core-b6d).
- B6d PASS (3c0bd99, Gemini 0/0/3; nits folded into B6e) merged main 3a6e4d5; 249 specs. B6e saddlebag (9a037bd, 256 specs) nit fixes then Gemini review.
- B6e PASS (124f06c, Gemini tierA re-review 0/0/1) merged main 26eef2a: per-char saddlebag, server horse check, /saddlebag in|out transfer. 263 specs, [fh] syntax 51 clean. M1 CODE COMPLETE; unverified in-game. Follow-ups B6f (pane toggle), B6g (pickSlot info nit).
- B6g PASS (842050a, Gemini 0/0/1 comment nit) merged main 06f2d3b; 267 specs. Lane idle pending owner in-game test; B6f (pane toggle) held for test RESULTs.
- B-run PASS (c8f1b22 Gemini 0/0/2, lows fixed db83664) merged main de086db: tools/first-run.cmd/.ps1 (UAC firewall, hidden key prompt, start + connect line), OWNER-STEPS 4 steps. test-firstrun ALL PASS, 267 specs. Owner: install RDR2+RedM, key, double-click first-run.cmd.
- 11-23 merged to local main (unpushed): B-access 495621d, B7 334642c, idea-614 b63a340; 23 spec files / 431 green. Siblings notified.
- core-03 handed to lead rn-f602a24ed9c2 (C3a+b one worker, C3c parallel).
- 11-23 core-03 COMPLETE: C3c 07449f7 + C3a 2b7587d / C3b 1baff20 merged main (Gemini tierA PASS 0/0/0 57161cd, range-diff '='; venv 51/1057/0). Siblings to swap adapters for fh_core addItem/removeItem carried refs + setItemInfo.
- core-03 COMPLETE main 9beb4c0 (614/615/616/643/687/689 archived). core-04 handed to Cor2 rn-d9e827279687.
- 11-23 core-04: B1+U2 (fh_buffs caps + remaining) and T1 (run-specs load errors, venv re-exec) merged main e991426 stack (Gemini PASS; venv 65/1292/0). U1 low fix + E2 FAIL fix (float compare) in flight.
- 11-23 core-04 U1 (fh:death:bags per player, mine/remaining, idea-609) merged main (c3b0fa3 + b5c7e70; Gemini PASS, venv 70/1358/0). E2 tierA re-review of fix 74cbbc1 pending.
- 11-23 core-04 COMPLETE: E2 offline-safe fh_economy.credit (fh_pending_credit, mig 0015, claim on load) + B7-nit merged main (1713bde, b3e4acf fix, 313ec96 renumber; Gemini tierA PASS after 1 fix; venv 71/1382/0). Core playtest-ready.
- core-04 COMPLETE main 018df02 (playtest-ready). core-05 handed to Cor2.
- 11-23 core-05 COMPLETE: K1 gun_parts outlaw loot (0.8, 2-3) + rollLoot ranges + crafting_sources_spec unpend merged main (ae7a8ff, a488aba; Gemini PASS 0/0/2 folded; venv 71/1385/0). idea-721 declined (fix is fence-side). Core merges on hold until playtest gate docs land.
- 11-24 core-06 COMPLETE: I1 (743 ACE grants before ensures, 744 Meshnet Media-Host IP/docs) merged main 47b4fd5 by Red3; 750 already on main 90a8278 (hub rf-inboxfix). I1-nit Get-MeshnetIp null guard 0b72271. tools/test-firstrun.ps1 needs a Windows run (no pwsh on forge). Core inbox empty.
- 11-24 R1 COMPLETE: idea-804 fh_economy.repByCitizenid (offline rep for homestead H8 abandon; shared applyRep, src re-resolve after awaits) 59c688b+f9a7316, Gemini PASS 0/0/2 folded; venv 87/1595/0.
- 11-24 R1 idea-804 merged 7bb75f6; core-06 I1 (743/744/750) by lead. core-07 handed to Cor2 rn-d9e827279687 (4 parallel blocks). Remaining owner-gated: B1-live, B6f flip.
- 11-24 core-07 S1 PASS: fh_core edge specs (49 tests: carried refs offline src, bulky veto, setItemInfo races, netId after despawn, spawn timeouts, snap) d29dc30+4393738, Gemini PASS 0/0/3 folded; venv 93/1699/0.
- 11-24 core-07 A1 PASS: fh_economy money audit, 3 fixes (logout-window guard, checked add/remove in integer cents, whole-cent amounts) + unload tracker cleanup; 2d43a30+3da975a, Gemini tierA FAIL 0/1/1 then PASS 0/0/0; venv 96/1732/0. Follow-ups M2/M3 queued, siblings idea-862..867.
- 11-24 core-07 L1 PASS: tools/check-contracts.py (exports/events/items lint, allowlist, run-specs --contracts) 645cc93+fix; Gemini FAIL 0/2/3 then PASS 0/0/0; 0 findings, 5 allowlisted.
- 11-24 X1 (live) PASS: fh_core access claim moved to resource-local access.txt (Save/LoadResourceFile), re-applied at boot; io errors logged; server.cfg add_ace resource.fh_core command.add_principal. Gemini tierA-security PASS 0/0/2; X1-nit queued.
- 11-24 core-07 B6f PASS: saddlebag player pane toggle DARK behind fh_saddlebag_pane=false (c895347+e2474f7+c7d4c9c), Gemini tierA PASS 0/0/4 then delta PASS 0/0/2 e4e00ab; venv 98/1808/0. Lows + /saddlebag in|out removal -> B6f-cleanup (after owner RESULT + flip).
