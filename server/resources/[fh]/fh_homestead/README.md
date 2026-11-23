# fh_homestead

Seed of lane L1 (spec L87, L107, L138-139): fixed homestead plots, one claim per character, one owner-only chest per plot.

- `config.lua`: plots (id, region, center, radius, chest coords/heading). Coordinates are approximate: verify in game.
- `shared/plot_rules.lua`: pure rules (in-radius, free, one-per-player, owner-only chest); specced in `spec/plot_rules_spec.lua`.
- `server/main.lua`: `/fh_claim`, `/fh_unclaim [plot_id]` (owner, or admin with a plot id), exports
  `claim`, `unclaim`, `getPlot`, `isInSafeZone` (stub, TODO fh_zones). DB: `server/migrations/0003_homestead.sql`.
- Chest = fh_core `chest` container (`fh:chest:<plot>:1`) with coords; open goes through `exports.fh_core:open`
  (server-side reach check) after the owner check.
- Client draws the chest as a local, non-networked prop. TODO(waits on B4c): anything networked.
- Events: `fh:homestead:claimed`, `fh:homestead:unclaimed` (see fh_core/docs/events.md).
- Known gaps: unclaiming leaves chest contents in the stash (TODO: spill to a drop bag); nothing stops another
  resource from opening the stash id directly (owner-only is enforced on this resource's open path).
- Not runtime-tested (no Cfx key yet).

## M1 loop (B6d)

Claim plot -> chest -> camp loot -> die once -> recover bag -> stash in the chest. No new code was needed for the stash:
the plot chest is an fh_core `chest` (accepts pocket, bulky, cargo), persisted by fh_inventory in `inventories`, and
`condition` / `stars` live in `item.info`, which every move keeps. The Small Safe and Worn Rifle are `bulky`: they fit the
saddlebag, wagon and chest but not the backpack (spec 4.1). **Gap:** no horse/saddlebag exists yet, so carrying them home
needs the horse lane (`FhDeathConfig.saddlebagOf`, `fh:saddle:<horse_id>`). Cross-resource names checked: `worn_rifle`,
`small_safe` (fh_zones registers them), `drop_bag` accepts what the backpack holds (pocket), `chest` for camp and plot.
See OWNER-TESTS.md "B6d" and "M1 end-to-end".

## Exports (server side, `exports.fh_homestead:<name>`)

Every export that touches slots or trophies returns `false, 'fh_not_ready'` (or an empty result) until the boot load of
claims and `fh_plot_slots` has finished.

| Export | Returns | Notes |
|---|---|---|
| `claim(src)` | `true, plot_id` or `false, reason` | reasons: `fh_not_ready`, `fh_no_character`, `fh_no_player`, `fh_not_in_plot`, plus the `plot_rules` refusals (plot taken, already own one), `fh_claim_failed` |
| `unclaim(src, plot_id?)` | `true, plot_id` or `false, reason` | owner, or admin / console (`src` 0) with a plot id. `fh_not_ready`, `fh_no_plot`, rule refusals, `fh_unclaim_failed` |
| `getPlot(citizenid)` | plot id or `nil` | |
| `isInSafeZone(coords)` | boolean | stub: true inside ANY configured plot, claimed or not (TODO fh_zones) |
| `getStations(citizenid)` | `{ {plot_id, slot_id, station_type, coords}, ... }` | built stations on that character's own plot; `{}` before the load or without a plot. Used by @crafting |
| `stationAt(coords, maxDist)` | `{plot_id, slot_id, station_type}` or `nil` | nearest built station on ANY plot within `maxDist` (default 3.0 m). Used by @crafting |
| `isNearStation(src, stationType, maxDist)` | boolean | OWNER-ONLY: only stations on the plot the asking character owns, measured from the server-side ped. Used by @crafting |
| `getComfort(citizenid)` | number (0 with no plot) | slot comfort plus trophy comfort (see Config). @survival reads this; homestead applies no buffs itself |
| `placeTrophy(src, itemId)` | `true, trophy_id` or `false, reason` | owner-only; takes ONE `itemId` out of the plot chest. Trophy ids look like `trophy_deer#1` |
| `unplaceTrophy(src, trophy_id)` | `true` or `false, reason` | owner-only; the row is deleted first, then the item goes back into the chest |
| `addTrophy(citizenid, trophy_id, points)` | `true` or `false, reason` | internal/admin: writes the wall row, no item movement |
| `removeTrophy(citizenid, trophy_id)` | `true` or `false, reason` | internal/admin: deletes the wall row, no item movement |

Trophy error codes: `fh_not_ready`, `fh_no_character`, `fh_no_plot` (no plot, or the plot changed hands mid-call),
`fh_plot_free`, `fh_not_owner`, `fh_no_trophy_wall` (trophy wall not built), `fh_not_a_trophy` (`getTrophyComfort`
returned nothing), `fh_hunting_unavailable`, `fh_wall_full`, `fh_trophy_cap`, `fh_bad_trophy`, `fh_bad_points`,
`fh_trophy_duplicate`, `fh_no_trophy` (not on the wall), `fh_busy` (another trophy change on this plot is in flight),
`fh_trophy_failed` (DB), `fh_removeitem_unavailable` (fh_core B7 `removeItem` missing), `fh_item_not_in_chest`,
`fh_additem_unavailable`, `fh_place_refund_failed` / `fh_unplace_refund_failed` (item could not be returned; logged as
`ITEM LOST`). Any other reason comes from fh_core (for example a full chest on unplace; the trophy then stays on the wall).

Slot interface (server-local table `FhHomesteadSlots`, for H2, not an export): `isReady()`, `getTiers(plot_id)`,
`setTier(plot_id, slot_id, tier)` (reasons `fh_not_ready`, `fh_no_slot`, `fh_bad_tier`, `fh_plot_free`, `fh_slot_busy`,
`fh_slot_save_failed`; tier 0 deletes the row), `plotOf(citizenid)`. It does no costs or rules: H2 charges first.

## Events (server-local `TriggerEvent`)

| Event | Payload | Fires |
|---|---|---|
| `fh:homestead:claimed` | `{ src, citizenid, plot_id, region_id }` | after a successful claim |
| `fh:homestead:unclaimed` | `{ src, citizenid, plot_id }` | after a successful unclaim (slots and trophies go with the plot) |
| `fh:homestead:slot_changed` | `plot_id, slot_id, tier` (positional) | a slot tier was saved and changed |
| `fh:homestead:station_built` | `citizenid, plot_id, slot_id, station_type` (positional) | a station slot went from tier 0 to 1 or more |
| `fh:homestead:comfort_changed` | `citizenid, newComfort, oldComfort` (positional) | only when the value actually changes (also to 0 on unclaim) |
| `fh:homestead:trophy_placed` | `{ citizenid, trophy_id, comfort }` | after `placeTrophy` succeeds (`comfort` = that trophy's points) |
| `fh:homestead:trophy_removed` | `{ citizenid, trophy_id, comfort }` | after `unplaceTrophy` succeeds |

Client to server: `fh:homestead:open_chest { plot_id }` (owner check, then fh_core `open`). Callback `fh:homestead:plots`.

## Config keys (`config.lua`, `FhHomesteadConfig`)

- `verifiedProps` (false): `false` = every slot uses its fallback `prop` (model + offset from plot center). Set `true` only
  after real `propVerified` data exists; station positions use the same choice.
- `baseSafeRadius` (25.0), `plots[<id>]`: `id`, `region`, `center`, `radius`, `chest { coords, heading, model, label }`, `slots`.
- `slots[<slot_id>]` (same template on every plot): `kind` (`cabin`, `fence`, `station`, `trophy_wall`, `chest`), `maxTier`,
  `stationType` (stations), `requires = { slot = minTier }`, `prop`, and `tiers[n] = { cost { money, items }, comfort,
  unlocks { chests, safeRadiusBonus, stationType, trophyComfort } }`. Slots: `cabin` (2 tiers), `fence`, `station_1`
  workbench, `station_2` campfire, `station_3` tanning_rack, `trophy_wall`, `chest_2` (needs cabin 1), `chest_3` (needs cabin 2).
  Costs are data only until H2.
- `trophyComfortCap` (20): max total trophy points. `trophyMaxByWallTier` (`{ [1] = 6 }`): how many trophies (best first) count.
  Trophy comfort counts only with the trophy wall built.

## Tables

- `fh_plots` / `fh_plot_chests` (0003): claim and chest rows.
- `fh_plot_slots` (0005): `plot_id`, `slot_id`, `tier`, `built_at`. PK `(plot_id, slot_id)`. Tier 0 = no row. FK to `fh_plots` ON DELETE CASCADE.
- `fh_plot_trophies` (0011): `plot_id`, `trophy_id` (varchar 64), `points`, `placed_at`. PK `(plot_id, trophy_id)`. FK to `fh_plots` ON DELETE CASCADE.

## Build flow (H2, pending @core B7)

H2 fills this in (build command/UI, money and material debit, build materials registered through `fh_core:registerItems`).

## Open

- Spill-on-unclaim gap: chest contents stay in the stash and pass to the next owner of the plot (see Known gaps above).
- Plots 2-4 coordinates (`heartlands_02..04`) are placeholders: TODO-verify in game. Slot prop offsets and the `p_chest01x` fallback model are also TODO-verify.
- `fh_hunting:getTrophyComfort` is guarded (`GetResourceState` plus `pcall`): until Hunting merges, `placeTrophy` returns `fh_hunting_unavailable`.
- `placeTrophy` needs fh_core `removeItem` (core B7): until it exists it returns `fh_removeitem_unavailable`.
- No player or admin command sets slot tiers or places trophies yet; that arrives with H2.
