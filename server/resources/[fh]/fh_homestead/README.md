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
