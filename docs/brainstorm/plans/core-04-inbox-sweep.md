# core-04 · Core inbox sweep (buffs caps, offline credit, ui contracts, runner)

Lead: @core lead Cor2. Base: main 9beb4c0 (core-03 done).

## Idea
Clear the remaining @core inbox in four independent blocks. The lead proposed this bundling. Buddy agreed, with one change: block E2 uses a pending-credit queue instead of a direct offline DB write.

## Requests (verbatim, condensed)
- idea-612 @crafting C4: "add caps tonic_vigor=1.15 and tonic_steady=1.10 to fh_buffs/config.lua (config only)".
- idea-613 @survival: "fh_buffs config caps: hydrated = 1.0, clean = 1.0 (config-only)".
- idea-700 @homestead H2: "fh_economy.credit(citizenid, amount, reason, region) that works offline (DB money column), for refunds." Today it logs MONEY LOST.
- B7-nit: fh_economy README Tests list.
- idea-609 @ui: fh:death:bags "needs per-player send with mine=true on receiver's own bags and remaining=expiresAt-os.time() (s), in both event and callback reply".
- idea-610 @ui: fh:buffs:sync "Add remaining=expires_at-now() per entry".
- idea-611: run-specs "a spec load error must count as a failure + nonzero exit".
- idea-699: run-specs "when 'from lupa import lua54' fails, re-exec under ~/.venvs/rf/bin/python if it exists".

## Decided
- **E2 offline credit = pending-credit queue, not a direct write to the money column.** Why: rsg-core keeps a loaded player's money in memory and saves it back on save/logout. A raw `UPDATE players SET money=JSON_SET(...)` that races a login gets overwritten, and that's another MONEY LOST. So `credit(citizenid, amount, reason, region_id) -> ok, reason`:
  - If that citizenid is online, use the pay path (ledger row first, AddMoney, void on failure, like pay at fh_economy/server/main.lua:46).
  - Else insert a row into a new `fh_pending_credit` table (+ ledger row 'credit_pending').
  - On character load (RSGCore:Server:PlayerLoaded or the existing fh_core character hook), claim pending rows atomically (`UPDATE ... SET claimed_by=? WHERE citizenid=? AND claimed_by IS NULL`, then select by claim token), AddMoney, then delete them. A row is never paid twice.
  - Positive integer amounts only; same validation as charge. tierA review.
- Checked existing primitives: fh_economy exports pay/rep/charge/getRep (main.lua:160-163). None takes a citizenid or works offline, so credit is new. fh_buffs config caps table (config.lua:5) is config-only for 612/613. run-specs exit code is already nonzero on load error (`worst`), so 611 only needs TOTAL to count errors (e.g. `TOTAL N specs, T tests, F failures, E load errors`).
- U1 death bags: keep the broadcast semantics, but send per player. Loop over online players with `publicList(forSrc)` adding `mine` (bag owner citizenid == receiver's) and `remaining` (expiresAt - os.time(), seconds, ≥0). Do the same in the callback (fh_death/server/main.lua:54-62, 330). Don't send owner ids to other clients.
- U2 buffs: snapshot entries gain `remaining = max(0, expires_at - now())` (fh_buffs/server/main.lua:7,21,40). expires_at stays for compatibility.
- 699: re-exec only if `~/.venvs/rf/bin/python` exists and we're not already running it (guard against loops). Otherwise keep the current error message, and name the venv in it.

## Plan
| Block | Touches | Clashes with | Kind |
|---|---|---|---|
| B1 buffs caps (612+613) | fh_buffs/config.lua | U2 (fh_buffs, different file) | Root cause |
| E2 offline credit + B7-nit | fh_economy server/main.lua, new SQL migration, README, specs | none | Root cause |
| U1 death bags mine/remaining (609) | fh_death/server/main.lua, specs | none | Root cause |
| U2 buffs remaining (610) | fh_buffs/server/main.lua (+shared logic snapshot), specs | B1 (same resource, trivial) | Root cause |
| T1 runner (611+699) | tools/run-specs.py | everything that runs specs (merge it first or last, not mid-suite) | Root cause |

Workers: B1+U2 one worker (fh_buffs); E2 one worker (tierA); U1 one worker; T1 one worker (mechanical). All in parallel. Gemini review each; tierA for E2.
Done-check: specs green via ~/.venvs/rf/bin/python tools/run-specs.py. E2 specs: online credit, offline → pending, claim-on-load pays once (double-load/concurrent claim), bad amount refused. U1: mine true only for owner, remaining ≥0. T1: a broken spec shows in TOTAL as a load error, exit 1. Plain python3 re-execs into the venv.
After merge: notify @crafting (612), @survival (613), @homestead (700: swap the MONEY LOST path for credit), @ui (609/610: fh_ui already reads mine/remaining). Archive 609/610/611/612/613/699/700.

## Open
- (none)

## Out of scope
B6f pane toggle (owner tests), horse ownership, fh_ui changes.
