# fh_death: soft death (spec L4, B6c)

On death: `equipped` (the hotbar) stays with the character. The backpack, and the saddlebag once a horse system
exists, move into a new owner-only **drop bag** at the death spot. The owner recovers it by walking up and pressing E.
A bag nobody empties is deleted after `despawnMinutes` (default 30), and what it held is logged as lost.
Tier A: this resource moves player items. NOT runtime-tested yet (no Cfx key); see OWNER-TESTS.md "B6c".

## Flow

1. **Detect.** rsg-core fires `RSGCore:Server:OnPlayerDeath` (server-only, from the victim client's rate-limited
   report). fh_death does not trust the report alone: it re-reads the ped health server side (`GetEntityHealth`,
   up to `deathCheckTries` x `deathCheckIntervalMs`) and needs `<= 0`.
2. **Once per life.** `FhDeathRules.onDeath` flips `alive -> dead` synchronously, before anything yields, so a
   repeated, duplicate or concurrent death event for that life is refused (`fh_already_dead`). The character is alive
   again (a new life, which may drop again) only when the server reads health `> 0` at least `minDeadSeconds` after
   the death (polled every `aliveCheckMs`).
3. **Drop.** Snapshot backpack (+ saddlebag). All empty: no bag. Otherwise, in this order:
   insert the `fh_death_drops` row -> `fh_core:registerContainer({ type = 'drop_bag', id })` (a registered fh stash
   sized to fit the contents) -> `fh_core:transferAll(source, bag)` per source -> prop through
   `fh_core:requestSpawn({ kind = 'object', tag = 'fh_death:<id>' })` -> `fh:death:dropped`.
4. **Recover.** `fh:death:open { id }`: owner (citizenid) and reach checked from the server ped
   (`FhDeathRules.canOpen`), then `fh_core:open`, which re-checks reach (and fh_inventory once more). The sweep
   (every `sweepMs`) deletes a bag that is empty and not open (`fh_core:deleteContainer`), despawns the prop and
   emits `fh:death:recovered`.
5. **Expire.** The sweep deletes an expired bag the same way, logs `lost: ...` and emits `fh:death:expired`.

## No dupe / no loss

- Each item moves in one fh_inventory `MoveBetween` step: removed from the source and added to the bag in the same
  Lua call, then both database rows are saved. A refused step leaves that item in its source (logged, in `kept`).
  There is no "create the items in the bag, then delete them from the player" step, so a failure cannot dupe.
- The `fh_death_drops` row is written before any item moves. If it fails nothing moves. A crash after it leaves a
  tracked bag; on restart it is re-registered and the sweep deletes it if it is empty.
- A bag is forgotten only after fh_inventory deleted its stash. `deleteContainer` is refused while anyone has the bag
  open (`fh_in_use`, retried next sweep), so an open inventory UI can never put items into a deleted bag.
- If fh_inventory restarted and lost the registration (`fh_unknown_container`), the bag is registered again and
  retried; it is never dropped from tracking.
- A bag is `busy` while it is being filled or deleted (both yield on MySQL): the sweep, the open request and an
  fh_core restart skip it, so nothing re-registers or re-props a container mid-delete.
- An expired bag cannot be opened, gets no prop and is not listed to clients; on start, expired rows are swept
  before the first broadcast.
- The only intended deletion of items is expiry, and it is logged item by item.

## Persistence

Bags survive a resource or server restart: `fh_death_drops` (`server/migrations/0004_death.sql`) holds id, owner,
coords, shape and `expires_at` (unix seconds); the contents are the stash's row in fh_inventory's `inventories`
table. On start every row is re-registered and its prop re-requested. On an fh_core restart (which drops all
registrations and spawn requests) they are re-registered and re-requested too.

## Gating

The prop is a plain B4c `kind='object'` request, so `fh_spike_gated` applies as for any spawn (see
`fh_core/docs/spike-gated.md` row 3). The stash is the truth: a failed prop never blocks the bag.

## Not done yet / known limits

- **Saddlebag:** no horse system yet. `FhDeathConfig.saddlebagOf(src, citizenid)` returns nil, so only the backpack
  moves. The horse lane returns the saddlebag stash id (`fh:saddle:<horse_id>`) there.
- Leaving the game before rsg-core's death report reaches the server drops nothing (combat logging is not handled).
- The owner can put items into their own bag; they expire with it.
- Insurance and the doctor fee (rest of L4) are later blocks; `exports.fh_death:getBags()` lists live bags for them.

## Files

`config.lua`, `shared/death_rules.lua` (pure, `spec/death_rules_spec.lua`), `server/main.lua`, `client/main.lua`
(E prompt via `FH.wrap` / `FH.onNet`). fh_core gained `deleteContainer` (fh_inventory `FhDeleteContainer`), covered
in `spec/fh_inventory_smoke_spec.lua` "fh_death hookup". Events: `fh_core/docs/events.md`. Natives:
`fh_core/docs/natives.md` "fh_death (B6c)".
