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
