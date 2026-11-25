# ui-tailor-catalog · fh_tailor catalog + wardrobe screens (idea-1003, progression-03 T4)

Source: docs/brainstorm/plans/progression-03-tailor.md (T4). Lead: UI3 rn-6551e91acd85. Progression lead: Pro2 rn-4460126058da.

Implemented catalog-style tailor/general-store clothing progression — Thanks to Red Dead Redemption 2 (single-player
tailors and catalogs) by Rockstar Games (design idea only; no assets or text copied).

## Decided
- **Primitives checked:** fh_ui shell contract (`fh:ui:open/close/update`, relay `fh:<lane>:ui_<action>`, per-screen
  `M.actions` allowlist from idea-849), fh_tailor T1 exports on main 95177a0 (`getStock`, `getWardrobe`, `buy`, `equip`,
  `saveOutfit`, `wearSaved`, `message`), core B6f done (c2d652b, pane toggle dark). No new vs/skill primitive.
- **Split:** T4a now (screens on the T1 server contract). T4b (mirror preview + saddlebag outfit pane hook) waits on
  progression-03 T2 client apply: preview needs a client apply function that does not exist yet.
- **Server authority:** fh_ui stays dumb. fh_tailor owns `fh:tailor:ui_<action>` handlers and calls its own exports with
  the relay's net `src`; never trusts client price/tier/owned. Every refusal returns `message(code)` as the screen notice.
- **Opening:** fh_tailor server exports `openShop(src, shopId)` / `openWardrobe(src)` send `fh:ui:open` with
  getStock/getWardrobe data. T2's stops (and later the homestead wardrobe) call these instead of their ox_lib menus.
- **Guarded exports only (Pro2 objection, accepted):** raw T1 exports have no range guard. ui.lua calls only T2b's
  guarded+debounced `actBuy/actStock/actWardrobe/actEquip/actSave/actWear` (codes `not_at_wardrobe`, `too_fast`).
  T4a merges after prog-t2 + prog-t2b. T4b targets T2b client exports `previewLook(look)` / `revertLook()`.
- New code sits in new files (`fh_tailor/server/ui.lua`, fh_ui screen files) so T4a does not clash with Pro2's T2.

## Plan

| Block | Touches | Clashes with |
|---|---|---|
| T4a `tailor` screen (catalog: rows label/kind/price/min_tier/owned, locked rows greyed with tier text, buy) + `wardrobe` screen (owned list, worn, saved slots: equip, save to slot, wear saved). fh_ui relay entries + `M.actions` allowlists, fixtures + schemas + specs, demo string, README. fh_tailor `server/ui.lua`: ui_buy/ui_equip/ui_save/ui_wear handlers + openShop/openWardrobe exports, re-send fresh data via `fh:ui:update` after each action | fh_ui (shared/relay.lua, fixtures.lua, html/screens/tailor.js + wardrobe.js, index.html, server/main.lua, README), fh_tailor (server/ui.lua new, fxmanifest one line, README section), spec/ | progression-03 T2 only on fh_tailor fxmanifest/README (one-line adds) |
| T4b mirror preview (client-local `previewLook`/`revertLook`, always revert on close) + switch T2's tailor stops / wardrobe from ox_lib menus to `openShop`/`openWardrobe` + saddlebag outfit pane hook | fh_ui tailor.js + wardrobe.js, fh_tailor client + README client section, OWNER-TESTS tailor steps | Pro2 OK'd (T4b owns the swap). Conditions: base on main after T2b; remove the ox_lib shop/wardrobe menus in the same commit, keep [G] prompts + stop/plot-chest detection (they call openShop/openWardrobe); revertLook on every close path (Esc, crash, resource stop); update fh_tailor README client section + OWNER-TESTS tailor steps. Pro2 T3 (config.lua) no clash |
| T4c OWNER-TESTS `## UI` steps for tailor/wardrobe | OWNER-TESTS.md | after T4a (+T4b) |

Order (Pro2-agreed merge order): T2b → T4a → T4b → T4c.

## In flight
- T4a MERGED f16213f (20de27d+f16213f; review PASS 0/0/1 rn-2131f8ce03a2). Gates: 137/2546/0, G5 0 unknown, contracts 0, syntax 268/0. Next: T4b on main.
