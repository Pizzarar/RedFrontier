# Plan · @ui · fh_ui shared NUI shell (L10)

## Owner's words (verbatim, from brief)
"one shared NUI shell (vanilla JS): buff HUD, heat indicator, insurance dialog, contract board, station menus, fence shop. Lanes ship data/events, UI ships screens. Hypnospace-light surrealism but readability first. ... build everything autonomously, Aub tests only at the end. Use @core §4 APIs only ... contract changes = request to @core. Anything waiting on in-game spike results goes behind one config flag. Pure-Lua specs (tools/run-specs.py) + in-game test card in README. No push."

Overlord integration rules (2026-11-22): work in `vs worktree create` units; merge to local main only after review PASS (rebase on current main, `python tools/run-specs.py` all green, merge, log hash); one lane merges at a time, rebase again if main moves; in-game checks go in a `## UI` section of OWNER-TESTS.md (no separate test doc); no pushes; when playtest-ready log `decision ui playtest-ready <hash>`.

## Decided
- **Inventory is out.** fh_inventory (rsg-inventory fork) keeps its own NUI. fh_ui never renders containers.
- **One resource `fh_ui`**, one `ui_page`, vanilla JS/HTML/CSS, no build step (spec §2).
- **Contract (the only API lanes see):**
  - Client event `fh:ui:open` `{ screen, data }` / `fh:ui:close` `{ screen }` / `fh:ui:update` `{ screen, data }` — server lanes send these with TriggerClientEvent.
  - Player actions come back from NUI callbacks as a server event `fh:ui:action` `{ screen, action, payload }`, re-emitted by fh_ui server as `fh:<owning_lane>:ui_<action>`; fh_ui does no game logic and no authority (spec §2 server-authoritative). Owning lane validates everything.
  - Passive HUD widgets subscribe to existing events directly: `fh:buffs:sync` (buff HUD), `fh:death:bags` (own drop-bag timer), `fh:heat:changed` (when L7 exists).
  - Each screen = `html/screens/<name>.js` + a data schema documented in fh_ui README. Lanes code against the schema; UI owns layout.
- **Screens without a producing lane yet** (heat, insurance, contract board, station menu, fence shop) are built against fixture data and opened via dev command `fh_ui_demo <screen>` (dev-only, ACE-gated like fh_core dev cmds). Real wiring happens when that lane ships; the schema in the README is the request.
- **Spike flag:** reuse `fh_spike_gated` convar if anything needs it (likely nothing: NUI focus/keys are standard Cfx). No new flag.
- **Look:** Hypnospace-light (docs/lanes/art-direction/SPEC.md if present): one surreal accent (e.g. slow-drifting sepia gradient / wobble on headers), body text high-contrast, min 14px, no motion on numbers. Readability gate wins.
- Checked for existing primitives: fh_core events doc, fh_inventory html (separate, not reused), `vs --help` (no UI primitive). No new vs command.

## Blocks
| Block | Touches | Clashes with | Kind |
|---|---|---|---|
| U1 shell: fxmanifest, ui_page, router, open/close/update + focus handling, `fh:ui:action` relay, README schema section, Lua spec for relay validation (screen whitelist, payload size cap) | new `fh_ui/` only; server.cfg ensure line | @core (server.cfg ensure list, one line) | Root cause |
| U2 buff HUD (fh:buffs:sync) + own drop-bag countdown (fh:death:bags filtered to self) | fh_ui only | none | Root cause |
| U3 fixture screens: heat indicator, insurance dialog, jobs board (was contract board; data from @quests: contracts/bounties/hunting requests), station menu, fence shop + `fh_ui_demo` | fh_ui only | none | Workaround → each lane wires its real event when it ships; tracked as Open per screen |
| U4 OWNER-TESTS.md `## UI` card + playtest-ready log | OWNER-TESTS.md (own section) | other lanes' sections (append only) | Root cause |

Order: U1 → U2 ∥ U3 → U4. Done-check per block: review PASS, run-specs green, merged to local main with hash logged.

## Out of scope
Inventory/container UI, quest journal (@quests) and handbook/tutorial prompts (@guide) — later blocks once those lanes publish schemas, any game logic or money/rep math, push/release, new fh_core contracts (if needed → `vs inbox add --lane core`).
