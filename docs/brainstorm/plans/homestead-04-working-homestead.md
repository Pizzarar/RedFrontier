# Plan homestead-04 · working homestead: garden slot, then trough slot (`fh_homestead`, lane @homestead)

## Idea
Two new build slots that turn the plot into something that produces. A garden grows vegetables for @crafting's stews (idea-916). A trough refills your horse at home and becomes the hired hands' real job, replacing the chest-feed workaround in fh_hands.
Owner words (via Overlord Red3, 2026-11-24): "owner has ~75% Claude quota for the next 1-2 days and wants it USED. Keep your lane working its goals: no parking without a real blocker."
Spec: docs/FRONTIER_HOMESTEAD_SPEC.md pillar 3 "every homestead upgrade unlocks a mechanic"; M7 "one hired hand automating troughs".
Crafting (idea-916): "farming would be a new homestead system (plots, grow timers, persistence)... Crafting just consumes carrot/potato/corn (cook_stew recipes)... No dependency or rush from us."

## Done-when
- H18-H21 merged to main (review PASS, `~/.venvs/rf/bin/python tools/run-specs.py` green, contracts + syntax gates clean, range-diff '=' pasted in slot ask).
- `vs log decision "homestead homestead-04 playtest-ready <hash>"`; OWNER-TESTS homestead card per block.

## Decided (Buddy lean, owner may redirect: plan proposed to owner 2026-11-25, no answer yet; quota push = act on lean)
- **Garden slot `garden` (claim plots only, tiers 0-1):** tier 1 = 3 beds; tier 2 is out of scope.
  - Plant with `/fh_plant <seed>` (or prompt) near the garden. It takes 1 seed from the backpack, using fh_core removeItem with the backpack ref (core-03 C3a).
  - Seeds: seedcarrot, seedpotato and seedcorn only (rsg-core items.lua:185-191 exist). The crop table lives in config, so more seeds are a config change.
  - Growth is server time stamped in DB (`planted_at`), so it grows while the owner is offline and survives restarts. Default 2 real hours per crop (config).
  - Harvest gives N veg (config, default 3) into the backpack, falling back to plot chest 1, using the H14b safe-refund rules. The bed is empty again afterwards.
  - Unclaim: planted beds block abandon like chests do (H13 rule: `fh_garden_not_empty`). Admin force clears and logs.
  - Comfort: the garden slot gives points like other slots (config).
- **Trough slot `trough` (claim plots, tier 0-1):**
  - The trough owns a small fh_core container `fh:trough:<plot>` that accepts `feedbag` only.
  - Mechanic: when the owner mounts their horse inside the plot radius and the trough holds a feedbag, the horse's health and stamina cores are refilled client-side and 1 feedbag is consumed server-side (cooldown, config default 30 min). The model and native calls go behind `verifiedProps` / a `troughRefill` flag.
  - Exports `getTrough(citizenid) -> ref|nil` so @progression's fh_hands can top up the trough instead of chest 1. That replaces the workaround at fh_hands/server/main.lua:81. We do not edit fh_hands: the change is a request to @progression.
- **No buffs applied by us** (Survival owns buffs). The horse refill is a direct core refill, not an fh_buffs buff.
- **Primitives checked:**
  - fh_core removeItem/addItem/registerContainer (README:158-183, backpack ref C3a);
  - fh_homestead slot model (config slotTemplate, build_rules.lua) and the H13/H14b refund rules;
  - fh_hands registerTask/feed_topup (fh_hands/server/main.lua:80-99);
  - rsg-core items: seeds, feedtrough, feedbag (items.lua:185-191, 415-417);
  - `vs --help`.
  - No existing farming or trough system (grep: only an rsg-core item def plus spec mentions).
- Migration: new table `fh_plot_beds(plot_id, bed, crop, planted_at)` gets placeholder 0099, renumbered at merge to main's highest + 1.
- Attribution: original design, no plugin source.

## Blocks
| Block | Touches | Clashes with | Root cause / Workaround | Done-check |
|---|---|---|---|---|
| H18 garden pure rules | `shared/garden.lua` (crop table, ready(at, now), harvest yield), config crops, spec | none | Root cause | spec: not ready before timer, ready at/after, unknown seed refused, yield from config |
| H19 garden server + persistence | `server/garden.lua`, migration 0099 `fh_plot_beds`, slot config `garden`, /fh_plant + /fh_harvest, unclaim guard in main.lua, README, OWNER-TESTS | H13 unclaim code (main.lua) | Root cause | spec: plant takes seed (all-or-nothing), restart keeps timer, harvest to backpack then chest with H14b refund rules, offline growth, unclaim blocked `fh_garden_not_empty`, admin force clears + logs; mutation: drop the timer check, spec goes red |
| H20 trough slot + refill | `server/trough.lua`, client refill on mount (flagged), slot config `trough`, container `fh:trough:<plot>` feedbag-only, export getTrough, README, OWNER-TESTS | client props (H2) | Root cause | spec: refill consumes 1 feedbag, cooldown respected, empty trough = no refill, non-owner = no refill, non-feedbag refused; unclaim blocked while the trough holds items (same H13 rule) |
| H21 request to @progression | `vs inbox add --lane progression` | @progression fh_hands | Root cause (request) | @progression switches feed_topup to `getTrough` + feedbag. After that, H13b's hired-hand block could be relaxed (Open) |

Order: H18 → H19 (garden first: crafting consumes now) → H20 → H21 sent when H20 is on main. H18 can run while H20's pure part is drafted, but H19 and H20 both touch main.lua unclaim, so they merge in serial.

## Open (owner, non-blocking)
1. Garden and trough, garden only, or neither (plan default: both, garden first).
2. Grow time (2h real) and yield (3 per bed): config, tune after playtest.
3. Once hands feed the trough, relax H13b (allow abandon with a hand hired)? Default: keep it.

## Lead
Hom3 rn-8ca5c7592ea0. Normal builds go to Implement - Gemini with a Review - Sonnet review. H19 moves items and needs a migration, so it is Tier A (Claude build, Gemini review).

## Out of scope
Fruit trees, crop quality and watering, pests/weather, NUI farm screens (@ui), selling produce (@roads/@trade), horse ownership/stables, editing fh_hands, pushing.
