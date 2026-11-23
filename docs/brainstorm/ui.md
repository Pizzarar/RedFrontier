# Brainstorm Summary · UI (`ui`)

> Rolling team brief (< ~5k tokens). Updated on every decision.

## Who's here
- Brainstorm: UI
- Lead: UI Lead · fh_ui shell
- Workers: 0

## Done when
- fh_ui on local main with U1-U4 PASS, specs green, `## UI` card in OWNER-TESTS.md, `decision ui playtest-ready <hash>` logged.

## Decided
- Plan: docs/plans/ui-fh_ui-shell.md (U1 shell → U2 buff HUD + bag timer ∥ U3 fixture screens → U4 test card).
- Inventory stays in fh_inventory's own NUI; fh_ui never renders containers.
- Contract: `fh:ui:open/close/update {screen,data}` in; `fh:ui:action` out, relayed as `fh:<lane>:ui_<action>`; no authority in fh_ui.
- Screens with no producing lane yet use fixtures + `fh_ui_demo`; reuse `fh_spike_gated`, no new flag.
- Overlord rules: vs worktree units, merge after PASS + rebase + run-specs green, one lane at a time, OWNER-TESTS `## UI` only, no push, log playtest-ready.

## Open
- Future screens, not in current plan: @quests quest journal, @guide handbook + tutorial prompts. Wait for their schemas.
- Real wiring per fixture screen as lanes ship: heat (L7), insurance (L4), jobs board (@quests: contracts/bounties/hunting requests; replaces contract board), station menus (L1/L5), fence (L9).
- (orig ask) L10 fh_ui: one shared NUI shell (vanilla JS): buff HUD, heat indicator, insurance dialog, contract board, station menus, fence shop. Lanes ship data/events, UI ships screens. Hypnospace-light surrealism but readability first. Spec: docs/FRONTIER_HOMESTEAD_SPEC.md. Owner: build everything autonomously, Aub tests only at the end. Use @core §4 APIs only (fh_core containers, fh_buffs, fh_economy, regions, events); contract changes = request to @core. Anything waiting on in-game spike results goes behind one config flag. Pure-Lua specs (tools/run-specs.py) + in-game test card in README. No push.

## In flight
- FORGE FREEZE (2026-11-23): all work parked. Lead told to park U1 as WIP on its branch, no new spawns/reviews/merges. Resume U1 → U4 after cutover. Note: plan + this brief are uncommitted in the primary checkout.
- Lead rn-b1919ab14b48 (UI Lead · fh_ui shell) running the plan, starting at U1.
- U1 shell PASS, merged main b0ac78a.
- FORGE FREEZE 2026-11-22: all ui work parked, all branches committed, no WIP:
  - ui-u1 58ca760: U1 merged to main b0ac78a (done).
  - ui-u2 b956563: U2 buff HUD + own drop-bag timer, specs green, NOT reviewed/merged. Degrades until core idea-609 (bags mine/remaining) + idea-610 (buffs remaining).
  - ui-u3 24e884e: U3 fixture screens + fh_ui_demo, specs green, NOT reviewed/merged. Pending: rename contracts -> jobs (owner quests, rows kind/title/region_id/payout/risk tier) + review fixes.
  - U2 review (Ui5, Gemini) landed after drain: FAIL 1 major/2 minor/1 nit on b956563. Major: client/hud.lua pushBags recomputes deadline every 5s tick, so the countdown never runs down (compute deadline only on fh:death:bags/callback; tick refreshes dir/dist only). Minors: hud.js use Math.ceil (jitter skips seconds); @ox_lib/init.lua -> shared_scripts like siblings. Fix via Ui3 on resume, re-review.
  - U3 review (Ui6, Gemini) FAIL 0/3/3 on 24e884e. Majors: (1) fh_ui_demo checks IsPlayerAceAllowed(src,'group.admin'), which isn't granted, so admins get locked out -> check 'command.fh_ui_demo' like fh_homestead; (2) empty Lua {} serializes as JSON {}, so `(rows||[]).forEach` crashes heat/contracts/station/fence -> normalize lists with Array.isArray (dom.js helper); (3) Enter auto-focus fires accept/craft/buy on list screens, and insurance.update adds the global Enter listener while hidden -> no autofocus on list screens; update only when open. Minor: .panel needs max-height + overflow-y auto. Apply with the jobs rename via Ui4, re-review.
  - Also check U2 widgets for the same {}-vs-[] crash when fixing U2.
  - Resume order: fix U2 (Ui3) || fix U3+jobs rename (Ui4) -> re-reviews -> merge U2 -> rebase+merge U3 -> U4., merge U2, rebase+merge U3, then U4. core idea-611: run-specs TOTAL hides spec load errors.
