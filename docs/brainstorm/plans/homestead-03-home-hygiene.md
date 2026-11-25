# Plan homestead-03 · home hygiene: no inherited stashes, build from pockets, best-home comfort, plot check tool (`fh_homestead`, lane @homestead)

## Idea
Close the real gaps left in `fh_homestead/README.md` Open (lines 201-213) after homestead-01/02, plus one lead candidate (lot comfort).
Owner words (via Overlord Red3, 2026-11-24): "owner has ~75% Claude quota for the next 1-2 days and wants it USED. Keep your lane working its goals: no parking without a real blocker."
Lead Hom2 candidates: lot-specific comfort, lot upgrades/extra slots, plot coords verification tooling, trophy wall on lots.

## Done-when
- H11-H14 merged to main (review PASS, `~/.venvs/rf/bin/python tools/run-specs.py` green, range-diff '=' pasted in slot ask).
- `vs log decision "homestead-03 playtest-ready <hash>"`; OWNER-TESTS homestead card updated per block.

## Decided
- **Spill gap is an exploit, fix first:** today a plot's chest stashes survive unclaim and pass to the next owner (README:206-207). Player unclaim/abandon is REFUSED while any plot chest (main, `:2`, `:3`) holds items: `fh_chests_not_empty`. Admin unclaim needs an explicit force flag, logs the full item list per stash (server print + `fh:homestead:spilled` event), then `fh_core.clearContainer`. No new container kind.
- **Build from pockets:** `/fh_build` takes materials from the player's pockets first, then the plot chest, all-or-nothing across both. Needs fh_core `removeItem` on the player's own inventory (README:208-209: world containers only today) → **request to @core** (H12a), homestead consumes it guarded (H12b); until it lands, chest-only behaviour stays.
- **Comfort = best home:** `getComfort(cid)` returns max(claim comfort, lot comfort). A lot scores only its own slots (chest_2, workbench), so it never beats a built-out claim; a lot-only character gets a little comfort instead of zero. Event payload unchanged.
- **Plot check tool:** admin-only `/fh_plotcheck [plotId|all]` prints per plot: ground z vs config z, water at center, overlap with other plots/lots at max radius, distance to nearest road/town. Reuses @world D's downward ground probe (do not write a second probe). Lets the owner verify all placeholder coords in one sitting instead of walking each plot.
- **Not doing (owner defaults stand):** trophy wall and extra slots on lots. homestead-02 decided lots are small (chest + workbench). Listed as Open owner question.
- Checked existing primitives: fh_core README (removeItem/transferAll/clearContainer, world containers only), fh_homestead comfort.lua (claim-only plotOf), @world D ground probe (fh_homestead client, d966dcf), `/where` + idea-815 `/where lot` (3307497), `vs --help`. New command `/fh_plotcheck` has no existing equivalent.
- Merge rules unchanged: no migration expected; if one appears, placeholder 0099, renumbered at merge.

## Blocks
| Block | Touches | Clashes with | Root cause / Workaround | Done-check |
|---|---|---|---|---|
| H11 no inherited stashes | `server/main.lua` (unclaim paths, claim + lot), README Open, OWNER-TESTS | @death if it writes into plot chests (insurance delivery): check, don't edit | Root cause | spec: unclaim with items in any chest = `fh_chests_not_empty`, nothing deleted; empty = ok; admin force logs + clears all 3 stashes; next owner opens empty chests; mutation: drop the check → test fails |
| H13b hired hand blocks abandon (idea-859) | `server/main.lua` unclaim paths, stash spec | fh_hands (read-only via `getHands` export) | Root cause | spec: hand hired = `fh_hand_active`; none = ok; fh_hands missing = ok (pcall); admin force skips |
| H12a removeItem on player inventory | request only: `vs inbox add --lane core` | @core | Root cause (request) | @core ships `removeItem({kind='player', src}, item, n)` all-or-nothing, or says no |
| H12b build from pockets | `server/build.lua`, `build_flow_spec` | H12a | Workaround until H12a lands (chest-only fallback stays; replaced by H12a) | spec: pockets+chest split take, all-or-nothing rollback on partial, refund once on charge fail; guarded when export missing |
| H13 best-home comfort | `server/comfort.lua`, comfort spec, README | @survival reads getComfort (API unchanged) | Root cause | spec: claim-only, lot-only, both (max), unclaim of one recomputes; comfort_changed fires once per real change |
| H14 /fh_plotcheck | new `server/plotcheck.lua` + client probe call, fxmanifest, README, OWNER-TESTS | @world D client probe (reuse, read-only) | Root cause | spec on pure part (overlap/distance math); in-game: owner runs `/fh_plotcheck all` once |

Order: H11 → H13 (both server, serial on main.lua/comfort) ∥ H12a sent now → H14 → H12b when @core answers.

## Open (owner, non-blocking)
1. Trophy wall / extra slots on town lots? Default no (lots stay small).
2. Admin force-unclaim: clear items (default) or move them somewhere recoverable?

## Lead
- Block ids renamed at dispatch (Hom2, 2026-11-24): H11/H12 were already used by homestead-02, so plan H11→**H13** stashes, H12a→**H14a** core request, H12b→**H14b** pockets, H13→**H15** best-home comfort, H14→**H16** /fh_plotcheck. H13, H15 and H16 run in parallel (separate files; README/OWNER-TESTS conflicts resolved at rebase). idea-599 closed as delivered (Cra2 agreed).
Hom2 rn-4b289c2c0700. Ask Cra2's crafting gaps into H-blocks only if concrete; idea-599 already covered (getStations/stationAt/isNearStation, H3+H9).

## Out of scope
Raids/law enforcement (@a-life), lot trophies/extra slots, new regions/coords (@world), pushing.
