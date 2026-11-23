# Owner tests (one ordered checklist)

Run top to bottom in your first in-game session (boot, then each block in plan order). Each block appends its own
section here; keep the order. Fill every `RESULT:` with `PASS`, `FAIL <what you saw>` or `SKIP <why>`, then send the
file back. Setup for the first join is in `OWNER-STEPS.md`. Admin commands need your account in `group.admin`.

## B4c: spawn-request contract (fh_core)

Server console lines start with `[fh_core:spawn]`. `server.cfg` ships `set fh_spike_gated true` (the conservative path).

1. Start the server and join. In F8 run `fh_spawn_horse`.
   Expected: chat `fh_spawn_horse: request N sent (a_c_horse_morgan_bay)`, then within ~10 s `request N ready, netId M
   (fh_despawn N)`, and a horse stands about 2 m in front of you. Server console: `request N adopted netId M from <your id>`.
   If chat says `failed: fh_spawn_client:model_timeout`, the default model name is wrong: retry with
   `fh_spawn_horse <another horse model>` and note the name that worked.
   RESULT:
2. Run `fh_spawn_ped`.
   Expected: same messages for a ped (`g_m_m_unibanditos_01`); the ped is visible (not invisible) in front of you.
   RESULT:
3. Spawner relogs (gated path). With the horse from step 1 still there, disconnect (F8 `quit` or `disconnect`) and
   rejoin. With a second client nearby the horse is recreated from that client right away; alone it waits until you are back.
   Expected: server console `request N: owner <old id> dropped, despawned and re-requested`, then
   `request N adopted netId <new netId> from <your new id or the other client>`. Exactly one horse at the original
   spot (not two, none missing).
   RESULT:
4. Run `fh_despawn N` (N from step 1).
   Expected: chat `fh_despawn: request N despawned`, the horse disappears, no new one comes back within 30 s.
   Running `fh_despawn N` again says `fh_spawn_unknown_request`.
   RESULT:
5. Run `fh_spawn_horse`, then right away `restart fh_core` in the server console.
   Expected: the horse is removed when fh_core stops; nothing is left behind after the restart.
   RESULT:

## B6c: soft death (fh_death)

Server console lines start with `[fh_death]`. Needs the `fh_death_drops` table (`server/migrations/0004_death.sql`,
applied by `tools/setup-server.ps1`). You need two characters: a second client, or a second character you switch to.
`equipped` = the hotbar slots; everything else in your inventory is the backpack.

1. Give yourself a weapon and some items: `/giveitem <yourId> weapon_revolver_cattleman 1` and drag it into a hotbar
   slot; `fh_give <yourId> bread 3` and leave the bread in the backpack (not the hotbar).
   Expected: the revolver sits in the hotbar, 3 bread in the backpack.
   RESULT:
2. Die (fall from a height, or let an NPC kill you) and respawn.
   Expected: server console `[fh_death] <citizenid> life 1: bag fh:dropbag:<t>-<n> at <x y z>, 1 stack(s) moved, 0 kept`.
   After respawning the revolver is still in your hotbar and the backpack is empty.
   RESULT:
3. Go back to where you died.
   Expected: a bag prop lies at the death spot (if no prop shows, note it, the console will say `prop for ... failed`,
   and carry on: the bag must still work). Standing on the spot shows `[E] Dropped belongings`.
   RESULT:
4. As the OTHER character, stand on the bag and press E.
   Expected: chat `fh bag: fh_not_owner`; no inventory opens.
   RESULT:
5. As the owner, press E on the bag.
   Expected: the inventory opens with the bag on the other side holding the 3 bread. From 5 m away pressing E (if the
   prompt still showed) does nothing / says `fh_out_of_reach`.
   RESULT:
6. Drag the bread back into your backpack and close the inventory. Wait up to 15 s.
   Expected: console `[fh_death] bag fh:dropbag:... recovered by <citizenid>`; the prop and the E prompt are gone.
   You have exactly 3 bread (no dupe, none missing).
   RESULT:
7. Die with nothing in the backpack (the revolver stays in the hotbar).
   Expected: console `<citizenid> died with nothing to drop; no bag`. No prop appears.
   RESULT:
8. Expiry: set `despawnMinutes = 1` in `fh_death/config.lua`, `restart fh_death`, put 1 bread in the backpack, die,
   respawn and do NOT open the bag. Wait about 2 minutes.
   Expected: console `bag ... expired; lost: 1xbread`; the prop and prompt are gone. Set `despawnMinutes` back to 30.
   RESULT:
9. Restart survival: put 1 bread in the backpack, die, respawn, then `restart fh_death` (or restart the server).
   Expected: console `[fh_death] 1 bag(s) loaded`; the prop comes back at the same spot and the owner can still open
   it and take the bread out.
   RESULT:
