# core-03 · Carried-inventory API + spawn release

Lead: @core lead rn-f602a24ed9c2. Base: local main (B7 334642c, idea-614 b63a340).

## Idea
Five sibling lanes need server-trusted add/remove/edit on a player's carried inventory (backpack/equipped). Today fh_core refuses carried refs (`fh_core/server/inventory.lua:233,247` → `fh_not_registrable`), so they route around it with rsg-compat adapters or stubs. Give them one sanctioned primitive, and retire the adapters.

## Requests (verbatim, condensed)
- @roads (B7 gap): "allow removeItem on carried refs (id = online src; same all-or-nothing + fh_not_enough), or name the intended primitive." R3 fh_trade main.lua:104 sell, R2 fh_cargo consumeWheel.
- idea-615 @crafting: "player-scoped all-or-nothing removeItem/addItem (+ setItemInfo(src, slot, info)) on carried refs". fh_crafting/server/inv.lua compat path today.
- idea-643 @quests Q2: "allow addItem({type='backpack', id=src})". Quest rewards stay owed until then.
- idea-687 @hunting H3: removeItem on carried refs. Workaround in fh_hunting shared/sell.lua.
- idea-689 @crafting C3: "setItemInfo(ref, slot, info)" for gunsmith restore (inv.lua:126 stub 'no_set_info').
- idea-616(1) @hunting: "export to end an adopted spawn's lifecycle, e.g. requestOfNetId(netId)". spawn.lua:237-239 re-requests deleted adopted entities, so skinned deer / H4 bear respawn.

## Decided
- Extend the existing exports; no new add/remove names. Checked: fh_core exports (inventory.lua:375+, spawn.lua despawn:245 / getSpawn:273), fh_inventory fh_api.lua. `despawn(requestId)` already ends a lifecycle, so 616(1) only needs the netId→requestId lookup.
- addItem/removeItem accept carried refs `{type='backpack'|'equipped', id=src}`. Rules: src must be an online player with a loaded character, otherwise `fh_player_offline`. Same all-or-nothing + `fh_not_enough` as B7. Same fh_inventory veto (size_class rules: bulky still can't enter backpack).
- New `setItemInfo(ref, slot, info)` for any valid ref (carried or registered). It replaces the slot's info table (caller merges). Refuse an empty slot (`fh_empty_slot`). Name check optional: `setItemInfo(ref, slot, info, expectName)` → `fh_wrong_item` on mismatch (prevents a slot swap race between read and write).
- clearContainer/deleteContainer/registerContainer/setContainerCoords stay refused on carried (destructive/world-only).
- New `requestOfNetId(netId) -> requestId|nil`. Hunting calls `despawn(requestOfNetId(netId))` when skinning. No release-on-death option for now.
- 692 (charge) and 600 (getRep) are already covered by B7 334642c. Close them.
- Carried calls emit the same fh events/ledger as world calls, with the player as actor.

## Plan
| Block | Touches | Clashes with | Kind |
|---|---|---|---|
| C3a carried add/remove | fh_core/server/inventory.lua addItem/removeItem, specs, README | none in flight | Root cause |
| C3b setItemInfo | fh_core/server/inventory.lua (new fn+export), fh_inventory fh_api.lua if no SetItemData path, specs, README | C3a (same file: one worker, sequential) | Root cause |
| C3c requestOfNetId | fh_core/server/spawn.lua, specs, README Spawn contract | none | Root cause |

C3a+C3b are one worker. C3c is a parallel worker. Gemini tierA review per block (inventory = trust boundary). Done-check: specs green incl. offline src, bulky→backpack veto, short-count all-or-nothing, setItemInfo empty/wrong-name, requestOfNetId hit/miss; syntax clean.
After merge: notify @roads, @crafting, @quests, @hunting to swap their adapters/stubs for fh_core exports (their follow-up, their lanes). Close idea-615/643/687/689/692/600 and 616(1).

## Open
- (none) — idea-616(2) closed: covered by @roads fh_cargo nearestWagon+getWagon (roads-r1 32817e7).

## Out of scope
Pane toggle (B6f), horse ownership, the release-on-death spawn option, and changes to sibling adapters.
