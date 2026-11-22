# Core plan 01: boot → M0 → M1 slice (`@core`)

## Owner's words (hub steer, 2026-11-22, verbatim)
> get Aub in-game ASAP, he's the only tester. Order: 1) local RedM server (FXServer + RSGCore + ox_lib + oxmysql) he can join today, with a short checklist of owner-only steps (Cfx key in an untracked file, never committed); 2) settle rsg-inventory replace-vs-wrap, lock §4 contracts, admin cmds, natives.md, headless boot check + busted; 3) carry straight into the M1 extraction slice inside this lane rather than waiting for L1/L3 lanes. Ship playable increments he can test each step. Spikes lane (rn-5b33cb75dbfb) reuses your server; agree the server path with it.

Spec: docs/FRONTIER_HOMESTEAD_SPEC.md (§4 contracts, §6 M0/M1).

## Decided
- **Server layout (agreed with @spk):** FXServer server-data lives in repo at `server/`. Tracked: `server/server.cfg`, `server/resources/[fh]/fh_*`, `server/resources/[rsg]/` (vendored RSG + ox_lib + oxmysql, pinned versions recorded in `server/VENDORED.md`), `server/resources/[spikes]/spk_*` (Spikes owns it; never ensured in server.cfg; Aub runs `ensure spk_<name>` live), `server/migrations/`.
- **Untracked (gitignored, B1 adds .gitignore before any other file):** `server/secrets.cfg` (sv_licenseKey, mysql_connection_string, rcon), `server/artifacts/` (FXServer Windows build), `server/db/` (portable MariaDB data), `server/cache/`, `txData/`. `server.cfg` does `exec secrets.cfg`. Ship `server/secrets.example.cfg` with placeholders only.
- **DB:** portable MariaDB zip under `server/db/`, started by script; no system service, no system install. `tools/start-server.ps1` starts DB then FXServer; `tools/stop-server.ps1`.
- **No txAdmin.** Plain `FXServer.exe +exec server.cfg`, so the headless boot check can run without a browser.
- **rsg-inventory: conditional wrap-or-fork (Buddy lean, R13).** B3 reads rsg-inventory's server move path. If there's a server-side veto point for every move (UI drag included) → **wrap**: fh_core container API on top, §4.1 extra fields stored as item fields/metadata. If not → **fork-and-patch** into `[fh]/fh_inventory`, route its move handler through `fh_core.canFit`. Replace-from-scratch only if both fail; that's a stop-and-report.
- **Spikes contract:** spk_ resources may use ox_lib only (no RSG item/container calls). Spikes PRs append natives (name + hash + source + go/no-go) to a spikes section; Core lead folds them into `fh_core/docs/natives.md`.
- **Entity spawning on RedM (from @spk, Buddy re-verified 2026-11-22):** server-side CREATE_PED / CREATE_OBJECT_NO_OFFSET are compiled out for RDR3 (citizenfx/fivem `code/components/citizen-server-impl/src/state/ServerSetters.cpp`: `#ifndef STATE_RDR3` at line 4, natives at lines 446 and 477, `#endif` at 517). Spec §7 "server owns spawn" becomes: **the server owns the decision and the state; a chosen client creates the networked entity; the server adopts it by netId.** The server keeps camp state, guards against duplicates, and sets orphan mode. B4 adds this as a §4 contract, `fh_core` spawn-request (request → pick spawner client → client creates → server adopts netId and records it → retry if the client drops or times out). B5 admin spawn commands and B6b camp spawn go through it. Wagons too: CREATE_AUTOMOBILE (L312) and CREATE_VEHICLE_SERVER_SETTER (L343) are in the same guard, so wagons use the same spawn-request contract (S1 adds a pcall CreateVehicle probe). Spikes S1 (branch spikes/probes 8e4a69c) gives the in-game confirmation. Lock B4 only after S1 reports, or lock it as provisional.
- **Git:** remote is `Pizzarar/RedFrontier` (personal, not pre-approved). Work on branches, merge to local `main`. **Do not push** without the owner's OK. B1 makes the first commit.
- Primitives checked: `vs --help` (spawn/task/spec/watch), VS MCP tools. Nothing existing covers a game server, so this is all new code. No parity/plugin-inspired features in this plan. RSGCore, ox_lib, oxmysql and rsg-inventory are vendored deps: credit them in `CREDITS.md` (RSGCore by Rexshack-RedM, ox_lib/oxmysql by Overextended / CommunityOx, whichever fork is pinned).

## Plan (order + done-check). Each block ends with an owner test card: 3-6 lines Aub can run in-game.
| Block | Goal | Done-check | Root cause / Workaround |
|---|---|---|---|
| B1 Boot | .gitignore, server/ skeleton, FXServer artifact + portable MariaDB fetched by `tools/setup-server.ps1`, vendored RSGCore + ox_lib + oxmysql + rsg-inventory + minimum RSG deps for character create/spawn, `start-server.ps1` | With a placeholder key, the only boot error is the licence check (all resources start clean); DB reachable + migrations ran; `git check-ignore server/secrets.cfg` passes. Then **OWNER-STEPS.md** handed to Aub | Root cause |
| B2 Headless boot check + busted | `tools/boot-check.ps1`: start, grep log for resource-start errors, stop, exit code. busted runner + one sample spec for pure-Lua fh_core modules | `boot-check.ps1` exit 0; `busted` green | Root cause |
| B3 Inventory decision | Read rsg-inventory move path; write `docs/decisions/inventory.md` (veto point file:line or its absence) → wrap or fork | Decision doc with file:line evidence; reported to Buddy before B4 | Root cause |
| B4 §4 contracts | fh_core: item registry (§4.1), container API (§4.2: move/canFit/getWeight/snapshot/transferAll over 7 container types), event naming doc (§4.3), region/faction registry config (§4.4, one region for M1), fh_buffs.apply stub (§4.5), fh_economy.pay/rep + ledger table (§4.6) | busted specs for canFit/size_class matrix + ledger; boot-check green. **Owner test:** move a pocket/bulky/cargo item across containers, cargo refused from backpack | Root cause |
| B5 Admin cmds + natives.md | ox_lib commands: give item, set heat (stub), tp, spawn wagon/horse, dump container. `fh_core/docs/natives.md` seeded with every native used so far (name + hash + source) | Owner test card works; natives.md lists every native grep finds in `[fh]` | Root cause |
| B6+ M1 slice | Per §6 M1, inside this lane, one playable increment per block: (a) fixed plot claim + 1 chest; (b) one T1 outlaw camp spawn + loot (worn rifle, small safe cargo); (c) soft death: keep equipped, drop bag entity, recover; (d) ride home, stash. Uses Spikes go/no-go on camp ownership | Each: boot-check green + owner test card | Root cause. Minimal fh_homestead/fh_zones/fh_death built here are the seeds of L1/L3/L4, not throwaway |

| Block | Touches | Clashes with |
|---|---|---|
| B1 | .gitignore, server/, tools/, CREDITS.md | @spk (server/resources/[spikes]): agreed path, no overlap |
| B2 | tools/boot-check.ps1, spec/ , .busted | none |
| B3 | docs/decisions/ | none |
| B4 | [fh]/fh_core, fh_buffs, fh_economy, server/migrations | future L2/L9 lanes (they inherit these) |
| B5 | [fh]/fh_core (commands, docs/natives.md) | @spk natives section (fold-in only) |
| B6+ | [fh]/fh_homestead, fh_zones, fh_death | future L1/L3/L4 lanes |

## Owner-only steps (lead writes `OWNER-STEPS.md` at B1, ≤10 lines)
1. Generate a RedM server key at keymaster.fivem.net for localhost and paste it into `server/secrets.cfg` (copy from secrets.example.cfg). Never commit.
2. RDR2 (legit copy) + RedM client installed.
3. Run `tools/start-server.ps1`, open RedM, F8 → `connect localhost:30120`.
4. Report anything weird to Core.

## Open
- Second client for Spikes camp-ownership test: Aub's call; default = drop/rejoin migration test.
- Push to GitHub: needs owner OK.

## Out of scope
- L2, L5–L10 systems; NUI beyond what rsg-inventory already ships; balance; spike resources themselves (@spk).

Lead: Core lead (Lead - Claude), spawned by Buddy.

## Amendment 2026-11-22: machine split (hub)
- **DevPC (this box):** repo, FXServer, MariaDB, server.cfg, Cfx key (untracked). Agents start/stop/ensure and read the console directly. txAdmin is **optional** for Aub's web UI. Default stays plain FXServer so the headless boot-check still works.
- **Main PC:** RDR2 + RedM client only. F8 `connect 100.83.196.251:30120` (DevPC Tailscale) or DevPC LAN IP. server.cfg already binds 0.0.0.0:30120 tcp+udp (server.cfg:4-5).
- **Block B-dev (allowed during the live-boot hold, infra only, no new natives):**
  1. OWNER-STEPS.md rewrite for the split. Owner runs once, elevated on DevPC: `New-NetFirewallRule -DisplayName "RedM 30120" -Direction Inbound -Protocol TCP -LocalPort 30120 -Action Allow` + the same for UDP. Add 40120 only if Aub opts into txAdmin. Owner-only because it changes system settings.
  2. Client error return: `fh_core` client helper `FH.safe(fn)` / wrapped thread+event helpers pcall our client code. On error it sends `fh:dev:clientError` (resource, msg, traceback) to the server, which appends it to `server/logs/client-errors.log` (gitignored) and prints to console. Gated by convar `fh_dev 1`, rate-limited. All `[fh]` client handlers use it. Root cause for our code. Workaround for non-fh resources (RSG): Aub sends the tail of `%LOCALAPPDATA%\RedM\RedM.app\logs\CitizenFX_log_*.log` (path to be confirmed on Main). Follow-up: Open item "RSG client errors".
  - Done-check: a spec for the server log handler; a deliberate client error via an admin cmd lands in client-errors.log at the live boot.
| Block | Touches | Clashes with |
|---|---|---|
| B-dev | OWNER-STEPS.md, fh_core client/server dev helpers, .gitignore, [fh] client handlers | B6a client code (wraps it) |
