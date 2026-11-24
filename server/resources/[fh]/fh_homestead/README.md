# fh_homestead

Seed of lane L1 (spec L87, L107, L138-139): fixed homestead plots, one owner-only chest per plot. Two plot classes
(plan homestead-02): a free, large, raidable **wilderness claim** (`class = 'claim'`, `/fh_claim`) and a bought, small,
law-safe **town lot** (`class = 'town_lot'`, `/fh_buylot`). One of each per character.

- `config.lua`: plots (id, region, center, radius, chest coords/heading). Coordinates are approximate: verify in game.
- `shared/plot_rules.lua`: pure rules (in-radius, free, one-per-player, owner-only chest); specced in `spec/plot_rules_spec.lua`.
- `server/main.lua`: `/fh_claim`, `/fh_buylot`, `/fh_unclaim [plot_id]` (owner, or admin with a plot id), exports
  `claim`, `unclaim`, `buyLot`, `getPlot`, `isInSafeZone`, `plotInfo`, `lawSafeAt`. DB: `server/migrations/0003_homestead.sql`,
  plot class `0018_homestead_plot_class.sql`.
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
| `claim(src, class?)` | `true, plot_id` or `false, reason` | `class` defaults to `'claim'`; the plot you stand in must be of that class (`/fh_claim` = class `claim` only; town lots are bought, H8). One plot per character per class. Reasons: `fh_not_ready`, `fh_no_character`, `fh_no_player`, `fh_not_in_plot`, `fh_wrong_plot_class`, plus the `plot_rules` refusals (`fh_plot_taken`, `fh_already_has_plot`, `fh_already_has_lot`, `fh_not_claimable`), `fh_claim_failed` |
| `unclaim(src, plot_id?)` | `true, plot_id` or `false, reason` | owner, or admin / console (`src` 0) with a plot id. The class comes from the plot's row. No `plot_id` = the caller's **claim** (a town lot is only released by naming its id). `fh_not_ready`, `fh_no_plot`, rule refusals, `fh_claim_busy` (that plot's claim is still writing; retry), `fh_unclaim_failed` |
| `getPlot(citizenid, class?)` | plot id or `nil` | `class` defaults to `'claim'`: `getPlot(cid)` is the homestead claim only, never a town lot (`nil` for a lot-only owner). `getPlot(cid, 'town_lot')` = the lot |
| `buyLot(src)` | `true, plot_id` or `false, reason` | `/fh_buylot`: buy the town lot you stand in. See "Town lots" below for the flow and reasons |
| `claimedPlots()` | `{ plot_id, ... }` | every claimed plot, all classes (fh_ui `/where plot`) |
| `isInSafeZone(coords)` | boolean | true within the safe radius of a CLAIMED plot: `baseSafeRadius` (else the plot radius) plus the built fence's `safeRadiusBonus` (+10 m). An owned town lot counts out to its own `radius` (no base, no fence bonus). Unclaimed plots (either class) never count; `false` until claims are loaded; before the slot cache is loaded the fence bonus is not counted. Query only: nothing enforces it (TODO fh_zones) |
| `plotInfo(plot_id)` | `{ class, raidable, lawSafe, owner }` or `nil` | `raidable` = class `claim`, `lawSafe` = class `town_lot`; `owner` = citizenid or `nil`; `nil` for an unknown id. Report only (for @alife raids / law AI, idea-803) |
| `lawSafeAt(coords, citizenid)` | plot id or `nil` | the town lot `citizenid` OWNS that contains `coords` (within the lot `radius`, edge inclusive; same rule as `isInSafeZone`). `nil` for claims, unowned lots, someone else's lot, `nil`/empty citizenid, bad coords, and before claims load; never throws. fh_heat skips law encounters (roadblock/ambush/chase) for a player inside their own lot |
| `getStations(citizenid)` | `{ {plot_id, slot_id, station_type, coords}, ... }` | built stations on that character's own plots (claim first, then town lot); `{}` before the load or without a plot. Used by @crafting |
| `stationAt(coords, maxDist)` | `{plot_id, slot_id, station_type}` or `nil` | nearest built station on ANY plot within `maxDist` (default 3.0 m). Used by @crafting |
| `isNearStation(src, stationType, maxDist)` | boolean | OWNER-ONLY: only stations on the plots (claim or town lot) the asking character owns, measured from the server-side ped. Used by @crafting |
| `getComfort(citizenid)` | number (0 with no claim) | slot comfort plus trophy comfort (see Config) of the **claim** only: a town lot adds no comfort and a lot-only character has 0. @survival reads this; homestead applies no buffs itself |
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
`fh_slot_save_failed`; tier 0 deletes the row), `plotOf(citizenid, class?)` (default `'claim'`), `plotsOf(citizenid)` (claim then lot). It does no costs or rules: H2 charges first.

## Events (server-local `TriggerEvent`)

| Event | Payload | Fires |
|---|---|---|
| `fh:homestead:claimed` | `{ src, citizenid, plot_id, region_id, class }` | after a successful claim or lot purchase |
| `fh:homestead:lot_bought` | `{ src, citizenid, plot_id, region_id, price }` | after a town lot purchase (right after `claimed`) |
| `fh:homestead:unclaimed` | `{ src, citizenid, plot_id }` | after a successful unclaim (slots and trophies go with the plot) |
| `fh:homestead:slot_changed` | `plot_id, slot_id, tier` (positional) | a slot tier was saved and changed |
| `fh:homestead:station_built` | `citizenid, plot_id, slot_id, station_type` (positional) | a station slot went from tier 0 to 1 or more |
| `fh:homestead:comfort_changed` | `citizenid, newComfort, oldComfort` (positional) | only when the value actually changes (also to 0 on unclaim) |
| `fh:homestead:trophy_placed` | `{ citizenid, trophy_id, comfort }` | after `placeTrophy` succeeds (`comfort` = that trophy's points) |
| `fh:homestead:trophy_removed` | `{ citizenid, trophy_id, comfort }` | after `unplaceTrophy` succeeds |

Client to server: `fh:homestead:open_chest { plot_id, chest? }` (owner check; `chest` 2/3 needs the `chest_2`/`chest_3` slot
built, else `chest: fh_chest_not_built`; then fh_core `open`). Callbacks `fh:homestead:plots` and `fh:homestead:slot_props`
(H2: `{ [plot_id] = props }` for every claimed plot, `nil` = not loaded yet, the client retries).
Server to client (H2): `fh:homestead:slot_props` `(plot_id, props)` to everyone on claim, build and unclaim (empty list);
`props` = `{ slot_id, kind, tier, model, coords, heading, chest? }` per built slot, drawn client-local and non-networked.

## Config keys (`config.lua`, `FhHomesteadConfig`)

- `verifiedProps` (false): `false` = every slot uses its fallback `prop` (model + offset from plot center). Set `true` only
  after real `propVerified` data exists; station positions use the same choice.
- `baseSafeRadius` (25.0), `plots[<id>]`: `id`, `name`, `class` (`'claim'` default, or `'town_lot'`), `region`, `center`, `radius`,
  `claimable` (only `false` refuses), `price` (town lot, optional), `chest { coords, heading, model, label }`, `slots`.
- `townLot = { price = 300, rep = 25 }`: `/fh_buylot` price in dollars (a lot's own `price` overrides it) and the rep given
  in the lot's region on purchase (taken back on abandon).
- `slotTemplates.claim()` / `slotTemplates.town_lot()`: a plot's slots come from its class template (applied at the end of
  `config.lua`; a town lot always gets the lot template, even if its entry lists `slots`). Town lot = `chest_2` (no cabin
  prerequisite) and `station_1` workbench only: no cabin, fence, campfire, tanning rack, trophy wall or chest_3.
- `slots[<slot_id>]` (claim template): `kind` (`cabin`, `fence`, `station`, `trophy_wall`, `chest`), `maxTier`,
  `stationType` (stations), `requires = { slot = minTier }`, `prop`, and `tiers[n] = { cost { money, items }, comfort,
  unlocks { chests, safeRadiusBonus, stationType, trophyComfort } }`. Slots: `cabin` (2 tiers), `fence`, `station_1`
  workbench, `station_2` campfire, `station_3` tanning_rack, `trophy_wall`, `chest_2` (needs cabin 1), `chest_3` (needs cabin 2).
  Costs are charged by the H2 build flow (below).
- `buildItems` (H2): the build materials `lumber` and `nails`, full §4.1 item defs, registered with
  `exports.fh_core:registerItems` from this resource only (at start and again when fh_core restarts).
- `trophyComfortCap` (20): max total trophy points. `trophyMaxByWallTier` (`{ [1] = 6 }`): how many trophies (best first) count.
  Trophy comfort counts only with the trophy wall built.

## Tables

- `fh_plots` / `fh_plot_chests` (0003): claim and chest rows. `fh_plots.class` (0018) `'claim'` | `'town_lot'`,
  `UNIQUE(citizenid, class)`: one plot per character per class.
- `fh_plot_slots` (0005): `plot_id`, `slot_id`, `tier`, `built_at`. PK `(plot_id, slot_id)`. Tier 0 = no row. FK to `fh_plots` ON DELETE CASCADE.
- `fh_plot_trophies` (0011): `plot_id`, `trophy_id` (varchar 64), `points`, `placed_at`. PK `(plot_id, trophy_id)`. FK to `fh_plots` ON DELETE CASCADE.

## Build flow (H2, `server/build.lua`)

`/fh_build <slot>` builds the next tier of a slot on the plot you own and stand in: a claim (`cabin`, `fence`,
`station_1..3`, `trophy_wall`, `chest_2`, `chest_3`) or a town lot (`chest_2`, `station_1`; any other slot there is
`fh_unknown_slot`). Materials come from that plot's own main chest. `/fh_build` with no slot lists every slot as `slot tier/max next: $money, n item` (or `(max)`).
Success reply: `fh_build: built <slot> tier <n> ($<money>, <n> <item>, ...)`. Server-local entry point:
`FhHomesteadBuild.build(src, slotId)` -> `true, tier, cost` or `false, reason, detail`.

Order (tier A: no dupes, no free builds, no lost items):

1. Checks, nothing taken yet: slot cache loaded (`fh_not_ready`), slot id (`fh_unknown_slot`), character
   (`fh_no_character`), own a plot (`fh_no_plot`), ped (`fh_no_player`), standing inside the plot (`fh_not_in_plot`),
   lock (`fh_build_busy`), then the H1 rules (`fh_not_owner`, `fh_max_tier`, `fh_prereq_missing`, ...).
2. Materials come out of the plot's main chest `fh:chest:<plot>:1` (NOT the player's inventory), one
   `fh_core.removeItem` per item in name order, each all-or-nothing. A shortfall returns `fh_not_enough` with the item
   name (`fh_build: fh_not_enough (not enough nails in your plot chest ...)`); items already taken go back first.
3. Money: `fh_economy.charge(src, money, 'homestead build', plot region)`, skipped when the tier costs $0. Right before
   it the flow checks the same character is still loaded on `src` (else `player_changed`). Any charge error
   (`fh_insufficient_funds`, `fh_charge_busy`, `ledger_failed`, `removemoney_refused`, `no_player`, `player_changed`,
   ...) is returned as is, after the items went back. `fh_charge_busy` is not retried: the command says
   `another payment is in progress, try again in a moment`.
4. `FhHomesteadSlots.setTier` (writes only while `fh_plots` still says this character owns the plot).

Refunds: any failure after step 2 puts back exactly what was taken. Items go back into the same chest with
`fh_core.addItem`; money goes back with `fh_economy.credit(citizenid, amount, 'homestead build refund', region)` to
the citizenid captured when the build started (never by `src`). If that character is online it is paid at once (mode
`paid`); if the player logged off or switched character since the charge, the money is queued in `fh_pending_credit`
and paid on that character's next load (mode `pending`, logged at info level). Each refund runs at most once and is
checked. A failed refund is logged on the server console as
`ITEM LOST: build refund failed: citizenid=... plot=... slot=... item=... amount=...` or
`MONEY LOST: build refund of $<n> to citizenid=... failed: <err>` (only when `credit` refuses or errors), and the build
returns `fh_build_refund_failed` (`tell an admin`). These two are the only credit paths and `charge` the only debit
path.

Lock: one build per plot and per character at a time (a second gets `fh_build_busy`), held across every await and
released on every path, Lua errors included (`pcall`; the error path is guarded too). A Lua error before the tier is
saved refunds and returns `fh_build_failed`. If the error comes after the tier was saved (for example in a
`slot_changed` handler), the build stands, nothing is refunded and the console logs `tier <n> was saved before the
error; kept`.

Ownership: every unclaim bumps a per-plot counter. After each await the flow re-checks that the same character owns
the same plot with no unclaim in between (also unclaim + re-claim): otherwise `fh_no_plot` and a full refund.

Other reasons: `fh_removeitem_unavailable` / `fh_charge_unavailable` (the fh_core / fh_economy export threw),
`fh_slot_busy`, `fh_plot_free`, `fh_slot_save_failed` (setTier; full refund), `fh_bad_cost` (config error, logged).

Also in H2:

- Extra chests: a built `chest_2` / `chest_3` is registered as an fh_core `chest` container `fh:chest:<plot>:<n>` at its
  prop position (on build, at start and when fh_core restarts), opened with `[E] Homestead chest <n>` at the prop.
- Props: every built slot gets a client-local, non-networked prop (see Events for the feed).
- `/fh_trophy place <item>` / `/fh_trophy remove <trophy_id>` (the `placeTrophy` / `unplaceTrophy` exports, item from the
  plot chest), `/fh_comfort` (prints your `getComfort`) and `/fh_station <type>` (prints `isNearStation` for you:
  `fh_station: workbench near=true|false`). All three are thin wrappers so the owner tests can run; they add no rules.

## Town lots (H8-H10)

`/fh_buylot` (export `buyLot(src)`): stand inside a town lot and buy it. Order: checks (nothing charged) -> reserve the
lot + per-plot lock -> `fh_economy.charge(src, price, 'town_lot:<id>', region)` -> write the `fh_plots` row (class
`town_lot`) + chest row + chest registration -> `fh_economy.rep(src, region, townLot.rep, 'town_lot')` -> events
`fh:homestead:claimed` then `fh:homestead:lot_bought`. Reply: `fh_buylot: bought lot <id>`.

Finding a lot: use `/where` (lots are listed as `<name> (town lot)`; `(coming soon)` while a lot is not claimable). Not
`/where plot`: that one finds wilderness claims only (world block D). A `/where lot` command is a separate follow-up.

- Refused before any money moves: `fh_not_ready`, `fh_no_character`, `fh_no_player`, `fh_not_in_plot`,
  `fh_wrong_plot_class` (a claim: use `/fh_claim`), `fh_not_claimable`, `fh_plot_taken`, `fh_already_has_lot` (one lot per
  character; owning a claim is fine), `fh_claim_busy` (that lot is mid-write, retry), `fh_lot_unpriced` (price not a
  positive whole number).
- Charge errors are returned as is (`fh_insufficient_funds`, `fh_charge_busy`, `ledger_failed`, `no_player`, ...), or
  `fh_charge_unavailable` when the export threw. Nothing is written.
- Write fails after the charge: exactly one `fh_economy.credit(citizenid, price, 'town_lot_refund:<id>', region)` (paid
  now, or queued if offline) and `fh_claim_failed`; no rep. A failed refund logs `MONEY LOST` (pay back by hand).
- A failed rep bump after a good purchase is logged, the lot stays bought.

Abandon: `/fh_unclaim <lot_id>` (a bare `/fh_unclaim` releases the **claim**). **No refund.** The purchase rep is taken back
(`rep(-townLot.rep, 'town_lot_abandon')`) BEFORE the row is deleted; if that fails for the owner the abandon is refused
with `fh_rep_failed` and nothing changes. An admin release while the owner is offline goes through and logs the skipped
rep-back (fh_economy has no rep path by citizenid). Buy, abandon, buy again nets one rep bump.

On a lot: chest 1 (`fh:chest:<lot>:1`) works as on a claim; `/fh_build chest_2` and `/fh_build station_1` (workbench, used
by crafting via `isNearStation`). No comfort. Safety: `isInSafeZone` covers the owned lot out to its `radius`, `plotInfo`
says `lawSafe = true, raidable = false`, and `lawSafeAt(coords, cid)` gives the owner's lot id (fh_heat uses it to skip
law encounters for the owner only).

## Open

- Nothing enforces "safe" beyond fh_heat's own-lot skip: `isInSafeZone` / `plotInfo` are queries only (law AI and raids:
  idea-803 @a-life, fh_zones).

- Spill-on-unclaim gap: chest contents stay in the stash and pass to the next owner of the plot (see Known gaps above).
  The same holds for the extra chests (`fh:chest:<plot>:2` / `:3`): their stashes stay after an unclaim too.
- Build materials must be in the plot chest: fh_core `removeItem` works on registered world containers only, not on
  the player's own inventory, so `/fh_build` cannot take lumber/nails from the pockets.
- `lumber` ($3) and `nails` ($2) are bought at any trade post (fh_trade supplies, idea-716/719); admins can still `/giveitem` them.
- Plots 2-4 coordinates (`heartlands_02..04`) are placeholders: TODO-verify in game. Slot prop offsets and the `p_chest01x` fallback model are also TODO-verify.
- `fh_hunting:getTrophyComfort` is guarded (`GetResourceState` plus `pcall`): until Hunting merges, `placeTrophy` returns `fh_hunting_unavailable`.
- `placeTrophy` needs fh_core `removeItem` (core B7): until it exists it returns `fh_removeitem_unavailable`.
