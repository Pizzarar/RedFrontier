# core-05 · gun_parts outlaw loot (idea-717); idea-721 declined

Lead: @core lead Cor2. Base: main 018df02 (core-04 done).

## Requests (verbatim, condensed)
- idea-717 (from @crafting idea-712): "add gun_parts to the outlaw camp loot table in fh_zones/config.lua:26 (data-only; suggested chance ~0.8, amount 2-3; gun_parts is registered by fh_crafting). It's the only source for gun_parts, which restore needs." Crafting's ruling is in plans/crafting-01-l5.md Decided (C8, gun_parts = LOOT only).
- Lead note: the same branch MUST drop gun_parts from the pending list in spec/crafting_sources_spec.lua:16.
- idea-721 (@progression, LOW): add an optional per-call timeout to fh_core container ops that returns 'fh_timeout'.

## Decided
- K1: add `{ name = 'gun_parts', chance = 0.8, amount = {2,3} }` to the outlaw camp table (fh_zones/config.lua ~line 28). Use the existing amount format if the roll supports ranges (check rules.rollLoot). If it only takes fixed amounts, either add range support to rollLoot with a spec, or use a fixed 2. Lean: add range support if it's a few lines, since sibling lanes will want it.
- gun_parts is registered by fh_crafting, not fh_zones, so don't add it to fh_zones `items`. If fh_crafting isn't running, addItem fails and clear() already logs "loot not placed" (fh_zones/server/main.lua:126). That's acceptable; no hard dependency.
- Same branch: remove `gun_parts = 'idea-717'` from the pending list in spec/crafting_sources_spec.lua:16, so the sources spec now checks the real source. Crafting agreed (lead note).
- **idea-721 declined for core.** A timeout in fh_core can't stop the late write. The fh_inventory call still completes after the deadline and lands in the stash anyway, so 'fh_timeout' only returns sooner and leaves the window open. fh_fence already documents this residual window as LOW (fh_fence/server/trade.lua:10-11). If it's ever needed, the root fix sits fence-side: a per-trade stash id or a generation token, not a deadline. Archive 721 and tell @progression.
- Checked: fh_zones loot table shape (config.lua:24-29), clear()/rollIntoStash (server/main.lua:118-137), crafting sources spec pending list.

## Plan
| Block | Touches | Clashes with | Kind |
|---|---|---|---|
| K1 gun_parts loot + spec unpend | fh_zones/config.lua, maybe fh_zones rules.rollLoot + spec, spec/crafting_sources_spec.lua | crafting lane (spec file; their ruling, a one-line delete) | Root cause |

One worker. Gemini review (normal tier; loot data).
Done-check: specs green (~/.venvs/rf/bin/python tools/run-specs.py), crafting_sources_spec passes with gun_parts no longer pending, and a rollLoot spec covers the gun_parts entry (and ranges, if added). Add an OWNER-TESTS line: clear outlaw camp → stash holds gun_parts sometimes.
After merge: notify @crafting (717 shipped), @progression (721 declined + why). Archive 717, 721.

## Open
- (none)

## Out of scope
Fence-side generation token (progression's call if they want it), other loot sources.
