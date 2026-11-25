# progression-02 · Ladder: regional tiers, treasure payoff, second hand

## Idea
L9 shipped the mechanisms (tiers, fence, one hand), but three of them stop short:
1. **Tiers exist only for heartlands.** quests-03 (contract tiers) reads `getTier` in 4 regions. Everywhere except heartlands it returns 1 forever, so the ladder can't climb there.
2. **Treasure leads pay nothing.** You buy `fh_treasure_lead` (coords + hint on the item) and there is no dig, no cache and no payout. It's a $250 dead item.
3. **One hand type.** L9 lists ranch hand, stablehand and cook; only `ranch_hand` (feed_topup) exists.

## Words (verbatim)
- Overlord Red3 (2026-11-24): "Buddy: if your lead has no plan, riff the next one from your SPEC Done-when gaps and hand it over this hour."
- Prg Lead: "Candidates I see: the trough task for hands (if a lane owns troughs now), more hand types and tasks, more fence stock and treasure-lead payoffs, tier 3 unlocks. One rule: no edits to fh_fence/server/trade.lua while prog-fw is open."

## Decided (Buddy lean, acted on per R13)
- **Primitives checked:** fh_progression `getTier`/`canUnlock` + config `tiers`/`unlocks` (fh_progression/config.lua:4-14); `FhRegions.isEnabled` (fh_core/shared/regions.lua); fh_core exports `addItem`, `removeItem` (all-or-nothing), `setItemInfo`, `canFit`, `requestSpawn`; fh_economy `pay`/`charge`; fh_hands `registerTask` export (fh_hands/server/main.lua:65,280); fence lead item info (fh_fence/config.lua:27,36-43). No new vs/skill/core primitive needed. No contract change requested from @core.
- **Troughs are still unowned** (only an rsg-core item def). The trough task stays Open, not in this plan.
- **Stablehand/cook are not buildable lane-locally:** no lane owns horse care or cooked-food items (food ids aren't settled in fh_survival/fh_inventory). Second hand = **woodcutter**: tops up `lumber` (registered by fh_homestead, config.lua:85; priced in fh_trade) in the plot chest, which feeds homestead build costs. This is a spec deviation, recorded here. Stablehand/cook stay Open until owners exist.
- **Roads consumes wagon_t2 + contracts_t2** (roads-02, fh_cargo spawnWagon + fh_trade T2 freight; docs/brainstorm/plans/roads-02-rep-unlocks.md). Roads request R8r: `unlocks.wagon_t3 = { region_id = 'heartlands', min_tier = 3 }`; until it lands t3 fails closed with `unknown_unlock`. It's in G1 verbatim. (idea-850 to @roads is superseded.)
- **contracts_t2 consumer = quests-03** (getTier-based). Our job is making tiers real in their regions (G1).
- Treasure payoff lives in a **new file** `fh_fence/server/leads.lua` (+ client). trade.lua is untouched while prog-fw is open.
- Original content: no plugin or parity inspiration, so no Credits line.
- Rules: specs first; specs only via `~/.venvs/rf/bin/python tools/run-specs.py`; review per Overlord (Sonnet if Gemini is down); merge slots via Red3; no push; never write the owner's name.

## Plan
| Block | Touches | Clashes with | Kind |
|---|---|---|---|
| G1 Tiers for every quest-enabled region (heartlands, scarlett_meadows, bayou_nwa, great_plains; thresholds from heartlands as default) + t3 unlock ids (`wagon_t3 = { region_id = 'heartlands', min_tier = 3 }` exactly, per roads R8r; `contracts_t3`; `hire_hand_2`). Spec: every region with `FhRegions.isEnabled` has an ascending tier row; every unlock names a known region | fh_progression/config.lua, spec | quests-03 T1 (getTier) + roads-02 (wagon_t3): land G1 first, then ping the Quests and Roads Buddies | Root cause |
| G2 Treasure lead payoff: lead item info → client hint + area blip; `fh:fence:dig` server checks distance (server-side ped coords, radius in config), `removeItem` the lead first (all-or-nothing = one-shot, no dupes), then a weighted loot roll (money via `pay` + rare parts via `addItem`, `canFit` checked before removal, fail closed). Pure `leads.roll(table, rng)` + spec | new fh_fence/server/leads.lua, client/leads.lua, config.lua (loot table), fxmanifest | prog-fw (trade.lua): **must not touch trade.lua**; config.lua edits are additive | Root cause |
| G3 Woodcutter hand: `registerTask('lumber_topup')` mirroring feed_topup (cap/perTick in config), `hands.woodcutter` entry; second hand gated by `hire_hand_2` (t3). Spec: cap respected, unpaid tick does no work, two hands bill two wages without double-charge | fh_hands/config.lua, server/main.lua (task only) | none | Root cause |
| G4 README updates (fh_progression tiers table, fh_fence leads, fh_hands woodcutter) + OWNER-TESTS progression steps (rep in scarlett → tier 2; buy lead → dig → payout; lead gone after; hire woodcutter → lumber in chest) | READMEs, OWNER-TESTS.md | other lanes' OWNER-TESTS sections: rebase | Root cause |

Order: G1 first (unblocks quests-03) → G2 ∥ G3 → G4.
Done-check per block: venv specs green, review PASS, merged via a Red3 slot, hash logged.
**Done when:** every quest-enabled region climbs t1-t3; a treasure lead digs once at its spot for a real payout and can't be dug twice or away from the spot; a woodcutter keeps the plot chest's lumber topped up on wages; `decision progression ladder-ready <hash>`.

## Out of scope
- Trough task (no owner). Stablehand/cook (no horse-care or food owner). fh_fence trade.lua (prog-fw). Rep balance passes. Any new @ui screen (hints use a notify + blip).

## Lead
Progression lead rn-5dc775ae6f22.

## Update 2026-11-24 (after G1 ae3f6a2)
- quests-03 gates per offer with `getTier(src, offer.region_id)` and reads no unlock ids.
- `contracts_t2` stays: roads-02 R9 gates T2 freight on it (fh_trade accept). Add a config comment naming that consumer.
- `contracts_t3` has no consumer: drop it in G4 (config + README tier table). Re-add when someone gates t3 freight.
