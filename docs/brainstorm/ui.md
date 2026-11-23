# Brainstorm Summary · UI (`ui`)

> Rolling team brief (< ~5k tokens). Updated on every decision.

## Who's here
- Brainstorm: UI
- Lead: ★ UI2
- Workers: 0

## Done when
- fh_ui on local main with U1-U4 PASS, specs green, `## UI` card in OWNER-TESTS.md, `decision ui playtest-ready <hash>` logged.

## Decided
- Plan: docs/plans/ui-fh_ui-shell.md (U1 shell → U2 buff HUD + bag timer ∥ U3 fixture screens → U4 test card).
- Inventory stays in fh_inventory's own NUI; fh_ui never renders containers.
- Contract: `fh:ui:open/close/update {screen,data}` in; `fh:ui:action` out, relayed as `fh:<lane>:ui_<action>`; no authority in fh_ui.
- Screens with no producing lane yet use fixtures + `fh_ui_demo`; reuse `fh_spike_gated`, no new flag.
- @quests contract = fh_quests README @ quests-q1 d277f55 (on local main b53979a since Q1-Q5 merge): `fh:quests:sync` v1 snapshot {journal[], board{region_id,epoch,expires_at,offers[{id,job_type,title,text,rewards,accepted}]}} + emitted events. Server actions: acceptOffer(src,offer_id), abandon(src,quest_id). ox_lib menus in Q3/Q4 are fallback until @ui wires jobs board + journal.
- Overlord rules: vs worktree units, merge after PASS + rebase + run-specs green, one lane at a time, OWNER-TESTS `## UI` only, no push, log playtest-ready.

## Open
- U3 jobs rename must use the real board schema (above), not the brief's guessed rows (kind/region_id/payout/risk tier: no risk tier exists; payout = rewards{money,rep,items}).
- fh_quests has no fh:quests:ui_* handlers; its ox_lib fallback uses lib callbacks fh:quests:menu:board/active/accept/abandon (server/menu.lua:8-28). U5 handlers can wrap the same exports.
- Proposed U5 quest journal + jobs board live wiring: fh_ui client adapter on fh:quests:sync -> journal/jobs screens; actions ui_accept/ui_abandon need @quests net handlers calling acceptOffer/abandon (request to @quests). Dialogue screen (talk() lines) = later.
- @guide handbook + tutorial prompts: wait for schema.
- idea-601 (accepted): fh_fence (@progression P2) ships data + temporary ox_lib menu; @ui then wires the `fence` screen to it (schema in fh_ui README, actions fh:fence:ui_buy/ui_sell) and fh_fence drops its menu. Blocked on: forge freeze, U3 merge, fh_fence on main.
- idea-601 pre-read (fh_fence @ prog-p2 99bb8bf, review PASS, not on main): `fh:fence:menu` returns {label, stock[{item,price,category=common|rare|leads,lead}], sells[{item,price}]}; buy/sell = lib callbacks via trade.lua, return ok+code. fh_ui fence schema (U3) wants {title, stock[{id,label,price,qty,rare?}], sell[{id,label,price,qty}]}. Lean: U3 fix swaps `rare?` for `category` (3 tiers); fh_fence's 601 side maps item->id, adds labels, stock qty cap, and held qty for sell rows; ui_buy/ui_sell handlers call trader.buy/sell and push refused codes back via fh:ui:update.
- Real wiring per fixture screen as lanes ship: heat (L7), insurance (L4), jobs board (@quests: contracts/bounties/hunting requests; replaces contract board), station menus (L1/L5), fence (L9).
- (orig ask) L10 fh_ui: one shared NUI shell (vanilla JS): buff HUD, heat indicator, insurance dialog, contract board, station menus, fence shop. Lanes ship data/events, UI ships screens. Hypnospace-light surrealism but readability first. Spec: docs/FRONTIER_HOMESTEAD_SPEC.md. Owner: build everything autonomously, Aub tests only at the end. Use @core §4 APIs only (fh_core containers, fh_buffs, fh_economy, regions, events); contract changes = request to @core. Anything waiting on in-game spike results goes behind one config flag. Pure-Lua specs (tools/run-specs.py) + in-game test card in README. No push.

## In flight
- Shell plan + plan 2 (ui-wiring-fence-quests) complete; idea-715 merged 60ec4aa.
- Plan 3: docs/plans/ui-giver-dialogue.md (idea-722: fh_ui `dialogue` screen replaces fh_quests ox_lib giver dialogue; D1 ∥ D2 -> D3). Handed to UI2 rn-8c7a9bce2671 2026-11-23; D2 coordinates with Que2.
- idea-722 D1 PASS (0/0/1) + D2 PASS (delta 0/0/0) + D3 PASS (0/0/0), merged main 53bf1c7 (3ec82df, e26f028, 83e2903, 53bf1c7). PLAN ui-giver-dialogue COMPLETE.
