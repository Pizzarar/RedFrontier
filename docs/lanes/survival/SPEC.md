# Survival lane SPEC (fh_survival)

## Goal
Needs as positive timed buffs (well_fed, hydrated, rested, warm, clean) on fh_buffs. A sluggish penalty is derived from missing needs (level 0-3) and is never lethal. Relog persistence uses the lane table fh_survival_needs (migration 0012) plus a 10-minute grace period for new characters.

## Shipped (survival-01, all on local main)
- S1 pure needs logic (9730266). S2 server core, state event `fh:survival:state`, persistence (1408a01, mig 0012).
- S3+S3b food (fh_jerky/fh_biscuit/fh_stew), canteen charges, /refill, /wash, campfire warmth. Items are registered via fh_core registerItems (883d46c).
- S4 bedroll and homestead bed rest, Well-Rested from comfort (c0dafc1). S4b uses direct fh_homestead isNearStation/getComfort calls with a GetResourceState gate (caebf25).
- S5 sluggish effect: `notify` is the default and `native` is opt-in. Includes the ## Survival OWNER-TESTS card (e9a2efc). playtest-ready logged at e9a2efc.

## Done-when gaps (candidates for survival-02)
- The owner runs the ## Survival card in-game. Fix whatever it finds. Its steps 8/10/13 depend on core idea-613 caps, which are now on main (1013520).
- Unverified natives: IsEntityInWater (WaterCheck='native') and the sluggish `native` stamina/clipset path. Each needs an in-game spike before its default can flip.
- WaterZones and Campfires are seeded with approximate coords near the heartlands homestead and camp. They need owner-verified coords, or a data source shared with fh_zones.
- ColdRegions={} because the fh_core region registry only has 'heartlands'. warm becomes a real need once cold regions exist.
- @ui: the sluggish level on `fh:survival:state` has no HUD consumer yet. Hand this to @ui; no UI work in this lane.
- Deferred alternative: fh_buffs.remove plus debuff ids, instead of the derived sluggish level. This goes through @core.
- Cross-lane: cooked food from @crafting and meat from @hunting feeding well_fed through the I.ITEMS path.

## Rules
Only edit fh_survival and the survival specs. Work in vs worktrees. Merge through the Overlord slot. Run specs with ~/.venvs/rf/bin/python tools/run-specs.py; the result must show 0 failures and 0 load errors.
