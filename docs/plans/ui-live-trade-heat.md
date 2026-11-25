# Plan · @ui live screens: trade post, trapper, heat HUD

Lead: UI2 (rn-8c7a9bce2671). Follows docs/plans/ui-giver-dialogue.md (complete, main 53bf1c7).

## Ask (verbatim)
- Original owner ask: "fh_ui: one shared NUI shell ... buff HUD, heat indicator, insurance dialog, contract board, station menus, fence shop. Lanes ship data/events, UI ships screens. ... build everything autonomously, Aub tests only at the end."
- Red3 (Overlord), 2026-11-24: "Keep your lane working its goals: no parking without a real blocker ... Buddy picks the next plan."
- UI2: "Candidates I'd consider: remaining ox_lib menus in other lanes' resources that fh_ui should own, idea-690 follow-ups (buff HUD polish), and the spec-listed screens not built yet (insurance dialog, station menus)."

## Decided
- Survey of `server/resources/[fh]` on main (2026-11-24): ox_lib menus left only in fh_trade/client/main.lua:16-35 (trade post: registerContext + 2 inputDialog) and fh_hunting/client/main.lua:213-227 (trapper sell context). fh_hunting:114 `lib.progressBar` is a skinning action, not a menu: stays.
- Heat is unwired but its producer is ready: fh_heat `getAll(src)` "for the HUD (@ui)" + `fh:heat:changed` (fh_heat/README.md:23,41); fh_ui `heat` schema already says the producer re-sends on `fh:heat:changed` (fh_ui/README.md:87-89).
- Not in this plan (real blockers): insurance dialog (fh_death has no insurance block yet, server/main.lua:335 "the insurance block (L4)"); station menus (fh_crafting has no client; crafting surface undecided); idea-690 was "fh_buffs has no client HUD", already satisfied by U2 (fh_ui client/hud.lua), archived by UI2.
- Primitives checked: fh_ui screens table (shared/relay.lua:7), relay -> server-local `fh:<owner>:ui_<action>`, `notice`/`notice_kind` convention, dom.js list helpers, `fh_ui_demo` fixtures, existing producer handlers (fh_trade `menuData`/`doSell`/`doBuy` server/main.lua:265-290; fh_hunting `trapper.list`/`trapper.sell` server/main.lua:220-236). No new vs command, flag, core API or export.
- Same rules as before: no authority in fh_ui; producer handlers re-validate; no autofocus, Enter does nothing on mutating screens; lists normalized for empty `{}`.

## Screen contracts
**tradepost** (owner `trade`, interactive). `open/update` `{ label, region, goods = { { item, label, price, shortage, saturation } }, supplies = { { item, label, price } }, max_sell, max_buy, notice?, notice_kind? }`. Goods show "In demand here" when `shortage >= 0.15`, "Market is flooded" when `saturation > 0.3` (same text as the ox_lib menu). Actions: `sell` `{ item, amount }`, `buy` `{ item, amount }` (amount clamped 1..max client-side; lane revalidates), `close`.
**trapper** (owner `hunting`, interactive). `open/update` `{ title, rows = { { container, slot, item, label, stars, legendary, price } }, notice?, notice_kind? }`. Empty rows -> "You have no pelts to sell here." Actions: `sell` `{ container, slot, item }`, `close`.
**heat** (passive, existing schema). Widget hides when every faction is 0.

## Blocks
| Block | Touches | Clashes with | Kind |
|---|---|---|---|
| T1 trade post screen | fh_ui: html/screens/tradepost.js, index.html, shared/relay.lua (`tradepost = 'trade'`), fixtures + `fh_ui_demo tradepost`, README. fh_trade: server `fh:trade:ui_sell`/`ui_buy` (AddEventHandler -> doSell/doBuy, then re-send `menuData` with notice), `/tradepost` opens fh_ui; delete the ox_lib menu in client/main.lua (keep chat fallbacks). Specs. | T2 (relay.lua/index.html/fixtures: one-line adds, rebase); fh_trade owner lane (@roads, idea-725 2182e31): ping before dispatch | Root cause |
| T2 trapper screen | fh_ui: html/screens/trapper.js, index.html, relay.lua (`trapper = 'hunting'`), fixtures, README. fh_hunting: server `fh:hunting:ui_sell` (-> trapper.sell, then re-list rows + notice), `sell_open` opens fh_ui; delete client/main.lua:213-227 ox_lib menu. Specs. | T1 (same one-line adds); @hunting lane: ping before dispatch | Root cause |
| T3 heat HUD live | fh_heat server: on `fh:heat:changed` and player load, build heat data from `getAll` (faction labels/tiers from config) -> `fh:ui:update heat`; fh_ui heat.js hides when all zero. Pure-Lua spec for the data builder. | fh_heat owner lane: ping before dispatch | Root cause |
| T4 test card | OWNER-TESTS.md `## UI` (append trade post, trapper, heat steps), fh_trade/fh_hunting/fh_heat READMEs (point at fh_ui screens) | other lanes' sections (append only) | Root cause |

Order: T1 ∥ T2 ∥ T3 -> T4. Done-check per block: Gemini review PASS, rebase on main, `~/.venvs/rf/bin/python tools/run-specs.py` green, merge via Red3 merge slot, hash logged. Then `vs log decision "ui live trade/trapper/heat merged <hash>"`.

## OWNER-TESTS steps (T4)
1. `/fh_ui_demo tradepost`, `trapper`: screens render fixtures; Enter does nothing; Esc closes.
2. At a trade post `/tradepost`: fh_ui screen (no ox_lib menu); sell 1 good -> "Sold for $N" notice, list refreshes; buy 1 supply -> notice; over-max amounts clamp.
3. At the trapper with a pelt: rows with stars/legendary; Sell -> notice, row gone. No pelts -> empty-state text.
4. `fh_heat` admin set to raise heat: heat widget appears with the faction level, no mouse grab; back to 0 -> widget hides.
5. grep: no `lib.registerContext`/`lib.showContext`/`lib.inputDialog` left in fh_trade or fh_hunting.

## Out of scope
- Insurance dialog, station menus (blocked, see Decided); skinning progressBar.
