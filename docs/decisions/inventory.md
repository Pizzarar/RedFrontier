# Decision: rsg-inventory — FORK-AND-PATCH (B3)

**Verdict: FORK-AND-PATCH** into `server/resources/[fh]/fh_inventory`, routing every move/add through `fh_core.canFit`.
WRAP fails the decision rule: there is **no** server-side veto point (no hook, callback, cancellable event or override
export; grep for hook/canMove/veto/beforeMove over the vendored resource = 0 hits). Everything else is workable, so REPLACE
is not needed. The fork is cheap: 2004 lines of Lua, one container model, one move handler.

Path prefix below: `main.lua`, `shops.lua`, `compat.lua` = `server/resources/[rsg]/rsg-inventory/server/`;
`core/` = `server/resources/[rsg]/rsg-core/`. Vendored at base commit ee8eef5.

## Why wrap can't work
The UI drag is `RegisterNetEvent('rsg-inventory:server:move')` (main.lua:880). Other resources can listen to a net event
but cannot cancel it, and the handler does its own inline weight checks (main.lua:940, 950, 958) and commits (968) with no
external call. Only API-driven adds (`AddItem`) could be wrapped; UI moves, give, drop and sort could not. So `size_class`
rules (§4.1) could be enforced for scripts but never for a player dragging a safe into a pocket-only bag.

## Evidence table
`Veto?` = does the path pass through a function where an fh_core check could cancel it today.
"Client-trusted" = client-sent value used without server revalidation.

| Path | file:line | Veto today? | Client-trusted? |
|---|---|---|---|
| UI drag player<->stash/drop/other, swap, split, merge | main.lua:880 `server:move`; weight checks 940/950/958; commit 968 | NO. Inline weight check only; own code path, does not use AddTo | No. Ids gated by `CanAccess` (776); `OpenInv` is set server-side (810); slot/amount bounds 889-929; item read from server state (923) |
| Shop buy / sell via UI | main.lua:905 -> shops.lua:114 `Buy` (`CanCarry`+`AddItem`), shops.lua:145 `Sell` (`RemoveItem`) | Only indirectly via AddItem/CanCarry; no hook | No. Price/stock server-side; range check shops.lua:109 |
| Give to player | main.lua:1126 `server:give`; `AddTo` 265, `RemoveFrom` 321 | NO (AddTo checks weight/slots only) | No. Slot/amount/name/target revalidated; range `GiveDistance` |
| Drop to ground | main.lua:1218 `server:drop`; `CreateDrop` 628 | NO | No. Slot/amount checked |
| Trash (destroy) | main.lua:1191 `server:trash` | NO (removal only) | No. Revalidated |
| Sort / auto-stack | main.lua:1035 `server:sort` -> `SortItems` 1000 | n/a (intra-container) | `which` only 'player'/'other' |
| Use item | main.lua:1091 `server:useItem` | n/a | Slot only; item read server-side |
| Open container | main.lua:843 `server:open` (drop id from client, distance-checked); stashes opened server-side via `API.OpenStash` 818 | n/a | `dropId` is a client string but validated |
| Script add/remove | `API.AddItem` 369, `API.RemoveItem` 389, `AddTo` 265, `RemoveFrom` 321; `Player.Functions.AddItem/RemoveItem` compat.lua:114-120 (used by core/server/moneyitems.lua:61,79,171) | NO hook, but one choke point per op (good patch site) | n/a (server callers) |
| Script bulk writes | `SetInventory` compat.lua:33 (overwrites items wholesale), `SetItemData` compat.lua:40 (sets any item key), `API.SetItemInfo` 470, `API.ClearInventory` 480, `ForceDropItem` compat.lua:83, direct `SetPlayerData('items')` in `Commit` 194 | BYPASS: none go through any rule check | n/a (server-only), but violates "no lane writes inventory directly" (§4.2) |
| Capacity overflow | `EnforceCapacity` 705 (moves overflow to free slots or ground) | BYPASS (internal move) | n/a |
| Stash create/load | `API.RegisterStash` 539; `GetContainer` 170 auto-registers any string id | n/a | `CanAccess` blocks use unless the server opened it |
| Carry check for scripts | `API.CanCarry` 435; `core/server/functions.lua:803` `CanCarryItem` | Weight/slots only, ignores container rules | n/a |

Bypasses of a future veto: the move handler's inline code plus the bulk/internal writers above. All fixable in a fork.

## Client-trust findings (§2 server-authoritative)
No unchecked amount/slot/target: move/give/drop/trash revalidate against server state, with per-source cooldowns
(50 ms move, 500 ms drop/trash, 1 s give). Gaps to close in the fork:
1. `CanAccess` returns true for `'newdrop'` (main.lua:785) and for any stash without `coords` (main.lua:788-790): a
   server-opened stash is reachable at any distance. fh_core must set `coords` on every world container (chest, wagon, fence).
2. `GetContainer` (main.lua:170-175) registers an arbitrary client-named string as a stash; only `CanAccess`/`OpenInv`
   stops use. Do not add any client-callable stash open.
3. Drops are memory-only unless `Config.Drop.Persist` (shared/config.lua:70, default false): a restart wipes ground items.

## Item data mapping (§4.1)
- Definitions: `RSGCore.Shared.Items` (core/shared/items.lua:4): `name,label,weight,type,image,unique,useable,shouldClose,description,category`.
  `BuildItem` (main.lua:88-98) copies a fixed whitelist to the runtime item; fh_core can read `RSGCore.Shared.Items[name]` directly.
- Per-instance data: only `info` (free table, deep-compared for stacking by `CanStack` main.lua:138).
  **Persistence stores only `{name, amount, info, slot}`** (`Serialize` main.lua:520-526), so any new top-level item key is
  silently lost on save. Instance data MUST live in `info`.

| §4.1 field | Where | Note |
|---|---|---|
| id, label, weight, stackable | existing (`name`, `label`, `weight`, `not unique`) | `unique=true` = one per slot, never stacks |
| size_class, value_base, illicit | static keys added to shared/items.lua entries | read via an fh_core item registry, validated at boot; defaults pocket / 0 / false |
| condition (nullable 0-100) | `info.condition` | differing values prevent stacking (desired) |
| quality (1-3 stars) | `info.stars` | **CONFLICT:** `info.quality` already means 0-100 freshness for decay (main.lua:59-63, 271), shop pricing (shops.lua:155-160) and weapon defaults (main.lua:255). Do not reuse the name; Core lead to confirm the spec wording |

## Container mapping (§4.2)
rsg-inventory has 3 container kinds: `player` (slots, maxWeight; `GetContainer` main.lua:176-186), `stash` (string id, per-id
slots/maxWeight clamped to `Config.Stash.Max*`; `RegisterStash` 539-554; DB table `inventories`), `drop` (coords + TTL;
`CreateDrop` 628). It has no per-container item rules; fh_core adds them.

| fh container | rsg-inventory realisation |
|---|---|
| equipped | player container, first `Config.HotbarSlots` (shared/config.lua:15) slots |
| backpack | the rest of the player container; capacity via `API.AddCapacityBonus` (main.lua:741), memory-only so fh_core re-applies on load/equip |
| saddlebag | stash `fh:saddle:<horse_id>`, slots/weight from horse tier |
| wagon | stash `fh:wagon:<wagon_id>` with `coords` set (reach check) |
| chest | stash `fh:chest:<homestead_id>:<n>` with `coords` |
| fence_stash | stash `fh:fence:<citizenid>:<fence_id>` |
| drop_bag | `CreateDrop` today (ground pile). Needs fork work: persistence, owner/TTL rules, id `fh:dropbag:<n>` |

Per-container rules (size_class allow-list, `cargo` blocks fast travel) live in fh_core as `rules[containerType]`, checked by the veto.

## B4 implementation sketch (fork)
1. Copy rsg-inventory to `server/resources/[fh]/fh_inventory`; keep LICENSE and credit (RSGCore by Rexshack-RedM). The
   manifest has no `provide`, so add `provide 'rsg-inventory'` so `exports['rsg-inventory']` (core/server/player.lua:146,
   functions.lua:809) resolves; drop the vendored copy from the start order.
2. Add `InvCore.Veto(op, src, fromC, toC, item, amount)` calling `exports.fh_core:canFit(...)`; default-allow when fh_core is
   absent so boot-to-M1 still works.
3. Call it in: `server:move` after main.lua:923 and the swap leg at 957 (both directions), `AddTo` 265 (covers give, drop,
   AddItem, EnforceCapacity), `CanCarry` 435 (shops/UI agree), `ForceDropItem`.
4. Make `SetInventory`/`SetItemData`/`SetItemInfo`/`ClearInventory` internal: allow-list `GetInvokingResource()` (fh_core, rsg-core).
5. fh_core API (`move, canFit, getWeight, snapshot, transferAll`) is a thin layer over `GetContainer`, `AddTo`, `RemoveFrom`,
   `Commit`; export them from the fork (they are locals now).
6. Add static fields to core/shared/items.lua plus a fh_core boot validator (size_class enum, `value_base >= 0`).
7. Close the trust gaps (main.lua:785, 788-790); set `Config.Drop.Persist = true`; add a `drop_bag` constructor.
8. busted tests on pure parts (TotalWeight, CanStack, rule table); manual checklist for drag/give/drop/shop.

## Risks
- Fork drift: upstream rsg-inventory fixes won't merge cleanly. Keep patches in marked `-- FH:` blocks (about 6 call sites) and record base commit ee8eef5.
- Other RSG resources call `Player.Functions.AddItem` and legacy exports; compat.lua keeps them, but the `provide` swap must be tested with character create/spawn.
- `info.quality` clash (above): any resource writing `quality` with its own meaning collides.
- Items saved before the new fields exist lack them; fh_core must default missing `info.condition/stars`, not reject.
- Per-item `condition` creates many single-item stacks (slot pressure; a balance issue).
- Stash/player moves write DB rows synchronously (main.lua:972-979); fine for 1-4 players.
- Not reviewed: the `html/` NUI and client/main.lua; assumed to be display-only since the server revalidates every event.
