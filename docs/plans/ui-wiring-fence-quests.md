# Plan · @ui live wiring: fence (idea-601) + quests jobs board & journal

Lead: current @ui lead (`vs who lead`). Follows docs/plans/ui-fh_ui-shell.md (U1-U4 merged; U4 1ccf7b5).

## Owner words (verbatim)
- Original ask: "fh_ui: one shared NUI shell ... contract board, station menus, fence shop. Lanes ship data/events, UI ships screens. ... build everything autonomously, Aub tests only at the end."
- @progression: "fh_fence is on local main now (P2 f60805c, stack tip ed2cb1e; not pushed). idea-601 fence screen wiring is unblocked. ... the ox_lib menu in fh_fence/client/main.lua is the stopgap to replace. Heads-up: P1b (in flight) changes fence debits to B7 charge plus removeItem and adds /fh_fence_settle. The event names won't change."
- @quests: "fh_quests is on local main (b53979a). ... ox_lib /jobs menu + giver dialogue are fallbacks awaiting @ui screens."

## Decided
- Contracts are the producers' READMEs on main: fh_fence (`fh:fence:menu/buy/sell` callbacks, server/main.lua:157-176; trade.lua untouched), fh_quests README "Client sync: fh:quests:sync" v1 + exports `acceptOffer`, `abandon`.
- Existing primitives checked: fh_ui relay (`fh:ui:action` -> server event `fh:<owner>:ui_<action>` with `{src, screen, action, payload}`, fh_ui/server/main.lua:9), fh_ui screens table, `fh:quests:sync` (fh_quests/server/main.lua:231), fh_quests stopgap callbacks `fh:quests:menu:*` (server/menu.lua:8-28). No new vs command, flag or core API. Reuse `fh_spike_gated` if anything needs gating.
- fh_ui stays authority-free: producer lanes own the `ui_*` handlers that call their own exports. The @ui lead writes those handlers in the producer resources (small, additive) and pings the owning lead; it does not touch fh_fence/server/trade.lua or fh_quests/shared/*.
- Screen schemas change to match producers, not the reverse: fence `rare?` -> `category` (common|rare|leads; leads qty fixed 1); jobs drops guessed `{kind, region_id, payout, risk}` for the real board `{region_id, expires_at, offers[{id, job_type, title, text, rewards, accepted}]}`.
- Refusal codes come back as `fh:ui:update` with `notice` (text mapped from fh_fence client MESSAGES / quests error codes), shown inline on the screen.

## Blocks
| Block | Touches | Clashes with | Kind |
|---|---|---|---|
| W1 fence live (idea-601) | fh_ui html/screens/fence.js + README fence schema; fh_fence client/main.lua (E opens fh_ui `fence` instead of lib menu), fh_fence server/main.lua (new `fh:fence:ui_buy/ui_sell` handlers -> trader.buy/sell; payload mapper: item->id, label from item registry, qty cap = cfg.maxQty, held qty on sell rows) | @progression P1b (in flight, trade.lua + maybe server/main.lua): rebase after P1b merges; event names stable per @progression | Root cause |
| W2 jobs board live | fh_ui jobs.js + README jobs schema; fh_ui client adapter (`fh:quests:sync` -> update `jobs` when open); fh_quests: `fh:quests:ui_accept` handler -> acceptOffer; board open trigger reuses the /jobs entry point | @quests (fh_quests server/main.lua, menu.lua); @roads registerJobType freight (job_type is data, no clash) | Root cause |
| W3 quest journal screen | new fh_ui html/screens/journal.js + screens table + README; adapter feeds `journal`; `/journal` (or keybind) opens it; `abandon` action -> `fh:quests:ui_abandon` -> abandon | W2 (same adapter file: W3 after W2) | Root cause |
| W4 drop fallbacks + test card | delete fh_quests client/jobs_menu.lua + server/menu.lua + fxmanifest lines; remove remaining fh_fence lib menu code; OWNER-TESTS `## UI` add fence/jobs/journal checks; specs | W1-W3 | Root cause |

Order: W1 ∥ W2 -> W3 -> W4. Done-check per block: Gemini review PASS, rebase on main, `~/.venvs/rf/bin/python tools/run-specs.py` green, merge in the merge slot, hash logged. Then `vs log decision "ui playtest-ready <hash>"`.

## Out of scope
- Giver dialogue screen (`talk()` lines) — next plan.
- @guide handbook / tutorial prompts — no schema yet.
- heat (L7), insurance (L4), station (L1/L5) live wiring — when those lanes ship.
- Any change to fence money logic (P1b owns it) or quests engine.

## Open
- None blocking. Ping owning leads (@progression, @quests) on handler commits in their resources.
