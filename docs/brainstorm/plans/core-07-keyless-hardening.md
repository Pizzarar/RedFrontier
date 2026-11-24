# core-07 · Keyless hardening + B6f behind a flag

Lead: @core lead Cor2. Base: main 7bb75f6.

## Idea
Owner quota mandate (Red3, 11-24): keep @core working without parking. Everything in the lane that's runtime-tested still waits on the owner's Cfx key. So spend this round on whatever makes that first boot most likely to just work. About 59 distinct `exports.fh_*:fn` call sites cross resource lines, and none has ever run. Cheapest high-value fix: lint them statically now. Plus a money-path audit, edge-case specs, and B6f built dark.

## Owner/lead words
- Red3: "Keep your lane working its goals: no parking without a real blocker … Buddy picks the next plan."
- Cor2: "(1) docs/lanes/core/SPEC.md doesn't exist … (2) Hardening that doesn't need a key … (3) Whether B6f's pane toggle can go ahead now behind a flag (tierA-invariant) rather than waiting."

## Decided
- (1) SPEC.md written by Buddy (docs/lanes/core/SPEC.md, uncommitted). Lead commits it in the next merge slot. Its Done-when adds a static contract check + a money audit.
- (2) Hardening = L1 contract lint + A1 money audit + S1 edge specs.
- (3) **B6f: go now, dark.** New convar `fh_saddlebag_pane` default `false`. With false, behaviour is exactly today's (/saddlebag in|out, player pane = backpack), so the owner's OWNER-TESTS run is unchanged. With true, the player pane toggles backpack⇄saddlebag. Flip it after the owner's saddlebag RESULT. Root cause for the UX; /saddlebag in|out stays as fallback until the flip, then a follow-up removes it (task B6f-cleanup).
- L1 is a Python tool (forge is Linux; boot-check is ps1). It plugs into run-specs or a new `tools/check-contracts.py` that the suite runner calls. No new vs primitive is needed. Checked: tools/ (run-specs.py, check-wiki.py, boot-check.ps1); nothing does cross-resource export checking today.

## Plan
| Block | Touches | Clashes with | Kind |
|---|---|---|---|
| L1 contract lint | new tools/check-contracts.py (+ hook in run-specs or test entry), allowlist file for intended gaps, spec | none (tools only; may surface bugs in sibling lanes → queue to their inbox, don't fix them here) | Root cause |
| A1 money audit (tierA) | fh_economy server/main.lua (fixes only if findings), spec/economy_* | none | Root cause |
| S1 fh_core edge specs | spec/core_inventory_*, spec/core_spawn_* (spec-only; code fixes only for in-unit root causes) | A1 no; B6f if it touches fh_core inventory.lua (S1 is spec-only, so fine) | Root cause |
| B6f pane toggle (dark) | fh_inventory fork (~6 player-pane handlers), fh_core saddlebag glue, convar, README, specs, OWNER-TESTS line (flag off by default) | S1 (fh_core inventory specs: rebase) | Root cause (flag = rollout, not workaround) |

All four run in parallel, one worker each. Reviews: L1/S1 normal Gemini; A1 and B6f tierA.
- **L1 check:** for every `exports.<res>:<fn>` and `exports['<res>']:<fn>` in `server/resources/[fh]`, `<res>` exists, `<fn>` is exported by that resource on the right side (server vs client), and the resource is ensured in server.cfg. Also every `TriggerEvent/TriggerClientEvent/RegisterNetEvent 'fh:*'` has at least one listener or a documented reason. Item names referenced in config loot/recipe/shop tables exist in some registerItems/items def. Output: list + exit 1. Known gaps go into the allowlist with an idea id. Findings in sibling lanes → `vs inbox add --lane <lane>`.
- **A1 check:** an independent audit, done fresh (not anchored on prior reviews), of pay/charge/credit/pending-claim for double-pay, lost money across yields, character switch, negative/float amounts, SQL injection, and ledger/balance divergence. Findings fixed in-unit, with specs for each.
- **S1 check:** specs for carried refs with an offline src, a bulky→backpack veto, setItemInfo expectName races, requestOfNetId after despawn, a re-request loop on a gone entity, and spawn timeout paths.
- **B6f check:** specs for flag-off parity (existing saddlebag specs unchanged) and flag-on toggle (mounted/near-horse gate, bulky only into saddlebag, server veto on every move).

Done-check overall: specs green via ~/.venvs/rf/bin/python tools/run-specs.py, check-contracts exits 0 (with allowlist), syntax clean, each block PASS. Merge via Red3 slots.

## Open
- (none). B1-live still waits on the owner (key).

## Out of scope
Horse ownership/stables, fixing sibling-lane lint findings (queued to them), flipping fh_saddlebag_pane on.
