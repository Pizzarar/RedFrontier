# Owner tests (one ordered checklist)

Run top to bottom in your first in-game session (boot, then each block in plan order). Each block appends its own
section here; keep the order. Fill every `RESULT:` with `PASS`, `FAIL <what you saw>` or `SKIP <why>`, then send the
file back. Setup for the first join is in `OWNER-STEPS.md`. Admin commands need your account in `group.admin`.

## Core: B-access (owner auto-admin, friend allowlist) - do this first

1. Join (OWNER-STEPS step 4). On the DevPC, `server/logs/fxserver.log` has exactly one line `granted group.admin to license:<hash>`.
   RESULT:
2. In game, run an fh_ admin command, e.g. `fh_dump backpack <yourId>`: it replies (no "no permission").
   RESULT:
3. Restart the server (close its window, run `first-run.cmd`), rejoin: still admin (step 2 works), and no new `granted` line in fxserver.log.
   RESULT:
4. Friend (optional, needs a second account): a not-yet-allowlisted connect is rejected with "You're not on this private server's allowlist. Ask the owner to add you..." (rsg-core's message; no `[RSGCORE]` prefix, shown once), and the server console prints one `allowlist: rejected <name> license:<hash>` line.
   RESULT:
5. Run `fh_allow license:<hash>` with that license; the friend reconnects and gets in, and `fh_dump backpack <theirId>` from THEIR client says no permission (they are not admin).
   RESULT:

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


## B6b: one T1 outlaw camp (fh_zones)

Server console lines start with `[fh_zones]`. Coordinates/models/weapons in `fh_zones/config.lua` are guesses: if a step
fails because of a bad model/coords, note the value that worked. `set fh_spike_gated true` (default). Admin: `group.admin`.

1. Start the server (fh_zones ensured after fh_homestead) and join.
   Expected: no `[fh_zones]` error lines; no `stash register failed` / `item registration failed`.
   RESULT:
2. Ride to the camp (about -145, 845, 117 in the Heartlands) and stop within ~40 m.
   Expected: console `camp heartlands_t1_01 activated`; 4 outlaws appear at the camp (visible, not invisible), each armed,
   and they attack you (hostile). If they stand around, note it.
   RESULT:
3. Kill all four outlaws.
   Expected: console `camp heartlands_t1_01 cleared, 2 loot entries` once the last one dies (within ~2 s); the bodies vanish at that moment. No clear while one is alive.
   RESULT:
4. Walk to the camp center (within 2 m) and press E at `[E] Outlaw camp stash`.
   Expected: the stash opens with a Worn Rifle (condition between 20 and 45 shown or in item info) and a Small Safe.
   Standing 10 m away and pressing E does nothing.
   RESULT:
5. Move the Small Safe into your backpack.
   Expected: refused (it is `bulky`: spec 4.1 allows saddlebag, wagon and chest only, not the backpack). The Worn Rifle (bulky) is refused by the backpack too. Both may go into a saddlebag or a chest.
   RESULT:
6. Wait `respawnMinutes` (10 min; lower it in config for the test). Stay away from the camp.
   Expected: console `camp heartlands_t1_01 respawned (idle)`, stash empty. Ride back within 40 m: the outlaws are there again.
   RESULT:
7. (Gated path) While the outlaws are alive and you are the only player, quit and rejoin.
   Expected: console `owner <id> dropped, despawned and re-requested`; after you return the outlaws come back hostile (once each, not doubled); killing them still clears the camp.
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

## B6d: M1 stash home + end-to-end card (fh_homestead, fh_zones, fh_death)

Changes in this block: the Small Safe is now `bulky` (was `cargo`); big safes and bullion stay `cargo` for M4 wagons.
A test-only cargo item `test_cargo_crate` exists so the cargo rule can still be proven. Not runtime-tested (no Cfx key).
KNOWN GAP: the backpack refuses `bulky`, and there is no horse/saddlebag stash yet (`fh_death` `saddlebagOf` returns nil),
so in game you cannot carry the rifle or safe home yourself. Steps 8-9 below tell us what actually happens; report it.

1. Cargo refusal. As admin run `fh_give <yourId> test_cargo_crate 1`.
   Expected: the reply is a refusal (`fh_refused` or `fh_size_class`); no crate in your backpack. Cargo is refused by the
   backpack AND the saddlebag (the saddlebag half is covered by `spec/camp_rules_spec.lua` only: no horse yet).
   RESULT:

## M1 end-to-end

One pass, one character, starting with an empty hotbar/backpack. Console lines start with `[fh_homestead]`, `[fh_zones]`, `[fh_death]`.

1. Stand on the plot (about -300, 790, 118) and run `fh_claim`; a chest prop appears; press E at it.
   Expected: `claimed plot heartlands_01`, chest opens.
   RESULT:
2. Fill the backpack: `fh_give <yourId> bread 3`. Equip a weapon in the hotbar (`/giveitem <yourId> weapon_revolver_cattleman 1`).
   Expected: 3 bread in the backpack, revolver in the hotbar.
   RESULT:
3. Spawn a horse with `fh_spawn_horse` (admin), mount it, ride to the camp (-145, 845, 117) and kill all four outlaws.
   Expected: `camp heartlands_t1_01 cleared, 2 loot entries`.
   RESULT:
4. Press E at the camp stash.
   Expected: Worn Rifle (condition 20-45) and Small Safe (both bulky).
   RESULT:
5. Try to drag the Worn Rifle and the Small Safe into your backpack (refused: bulky). Then, with the camp stash still open and your horse within 3.5 m of you AND of the stash, run `/saddlebag in <slot>` for each (`<slot>` = the item's slot in the camp stash).
   Expected: the backpack refuses both; each `/saddlebag in` replies `saddlebag: moved (in)` and the open camp stash pane drops the item (if it does not, close and reopen the stash with E and note that in RESULT). Open the saddlebag (`/saddlebag`) and confirm both are inside. (A horse farther than 3.5 m, or a non-horse ped: `saddlebag: fh_out_of_reach` / `fh_not_a_horse`.)
   RESULT:
6. Die once (fall or NPC) and respawn.
   Expected: `[fh_death] ... bag fh:dropbag:... moved`; revolver still in the hotbar; backpack empty.
   RESULT:
7. Walk to the bag, press E, take everything back.
   Expected: bread returns to the backpack; the bag empties and is swept.
   RESULT:
8. Ride the horse home. Open the plot chest (E) and move the bread in. With the chest open and the horse within 3.5 m of you and the chest, run `/saddlebag out <slot>` for the rifle and the safe (`<slot>` = their slots in the saddlebag; run `/saddlebag` first to read them, then press E at the chest again).
   Expected: `saddlebag: moved (out)` for both and the open chest pane shows them (if not, reopen the chest with E and note it); the chest now holds the rifle (condition intact) and the safe.
   RESULT:
9. Restart persistence: put an item in the chest, stop the server, start it, rejoin, open the chest.
   Expected: the item is still there with its condition intact (check a rifle if you got one home).
   RESULT:

## B6e saddlebag

1. Spawn a horse (`fh_spawn_horse`), stand beside it, run `/saddlebag`. Put 1 bread in it.
   Expected: the saddlebag opens (20 slots); bread accepted.
   RESULT:
2. Cargo refusal is SPEC-ONLY for the saddlebag (`spec/containers_spec.lua`): no in-game path puts `test_cargo_crate` anywhere the saddlebag can pull it from (`fh_give` goes through a drop bag and the backpack, which refuse cargo). Nothing to test by hand; skip.
   RESULT: n/a
3. Walk 10+ m from the horse and run `/saddlebag`.
   Expected: `saddlebag: no horse in reach` (client) and nothing opens. Also stand next to a non-horse ped: same.
   RESULT:
4. Mount the horse and run `/saddlebag`.
   Expected: opens with the bread still inside.
   RESULT:
5. Die with bread in the saddlebag and the backpack. Respawn and find the drop bag.
   Expected: bag holds the saddlebag bread too (`[fh_death]` console line); the saddlebag is empty.
   RESULT:
6. Put an item in the saddlebag, restart the server, rejoin, spawn a horse, `/saddlebag`.
   Expected: the item is still there.
   RESULT:
7. Transfer path: open the plot chest (E) with bread inside, stand with your horse within 3.5 m of you and the chest, run `/saddlebag in <slot>` for the bread, then `/saddlebag out <slot>` for it again. Try `/saddlebag in <slot>` with no container open, and with the horse 6+ m away.
   Expected: moved both ways with no duplicate or lost bread (count it before/after; if the open pane looks stale, reopen the chest with E and note it); with nothing open `saddlebag: fh_nothing_open`; far horse `saddlebag: fh_out_of_reach`. Spamming the command faster than twice a second is silently ignored.
   RESULT:

## UI (fh_ui shell, buff/bag HUD, screens)

Covers U1 shell, U2 passive HUD, U3 screens. Setup: `server.cfg` already has `ensure fh_ui`, `add_ace group.admin command allow`
(covers `command.fh_ui_demo`) and `set fh_spike_gated true` (leave it true). Also ensure `fh_buffs`, `fh_death` and `fh_heat`
if they exist in your cfg; screens whose lane is absent simply stay empty. Join as a `group.admin` account. Open the F8
console and keep it visible for steps that say "check F8". Server console lines start with `[fh_ui]`. Fixture button
actions relay to lanes that may not exist yet; "unhandled" is expected.

1. Start the server and join. Run `/fh_ui_demo insurance`.
   Expected: the Tracker Insurance dialog appears, the mouse cursor works, no `[fh_ui]` errors in the server console.
   RESULT:
2. Press Esc.
   Expected: the dialog closes, the cursor goes away and you can walk and move the camera again (NUI focus released).
   RESULT:
3. Run `/fh_ui_demo insurance`, then `/fh_ui_demo close`. Then open it again and click the dialog's Cancel button.
   Expected: both ways close it and release the mouse; movement works after each.
   RESULT:
4. Run `/fh_ui_demo bogus` and, if you can, as a non-admin account `/fh_ui_demo heat`.
   Expected: a chat line `fh_ui_demo: ...` (usage or `not allowed`); nothing opens, no focus taken.
   RESULT:
5. Buff HUD: get a buff (consume a buff item, or whatever fh_buffs gives you). Watch the widget for ~15 s.
   Expected: it lists the active buff with its remaining time counting down. Until fh_buffs sends `remaining` on
   `fh:buffs:sync` (core ideas 609/610 pending), the row shows `--` instead of a time: that is the expected degradation,
   note which you saw. With no buffs the widget is hidden.
   RESULT:
6. Drop-bag countdown: die and respawn (see B6c), then watch the bag widget for 20 s.
   Expected: your own bag shows a time that counts DOWN every second and does NOT jump back up every 5 s. Until
   fh_death sends `mine`/`remaining` per owner (core ideas 609/610), the widget shows nothing: expected degradation, note it.
   RESULT:
7. Walk and drive/ride around while the bag widget is up (if it showed in step 6).
   Expected: direction (N..NW, `here` when on it) and distance in metres update as you move.
   RESULT:
8. Run `/fh_ui_demo heat`.
   Expected: a heat indicator with factions, levels, tiers and a lay-low note appears; the mouse is NOT captured and you
   can keep moving. Run `/fh_ui_demo close heat` to remove it.
   KNOWN GAP (idea-648): the heat indicator and buff panel may overlap top-right. Note it under RESULT; do not FAIL for it.
   RESULT:
9. Run `/fh_ui_demo insurance`. Press Enter.
   Expected: Enter confirms (server console shows a relayed/unhandled `confirm`, no crash). After closing the dialog,
   press Enter again: nothing happens (Enter only works while the dialog is open).
   RESULT:
10. Run `/fh_ui_demo jobs`.
    Expected: Jobs Board lists three rows: one contract, one bounty, one hunt, each with region, payout and risk. No
    button is auto-focused and pressing Enter does nothing. Click Accept on a row: unhandled relay, no error. Esc closes.
    RESULT:
11. Run `/fh_ui_demo station`, then Esc; then `/fh_ui_demo fence`, then Esc.
    Expected: station shows craft options (Craft disabled where `can_craft` is false); fence shows buy and sell lists
    with qty controls (clamped to 1..listed qty). No autofocus, Enter does nothing, Esc closes and releases focus each time.
    RESULT:
12. Long and empty lists (only if you can push custom data, e.g. a test client script sending `fh:ui:open`; otherwise SKIP).
    Open `jobs` or `fence` with 30+ rows: the list scrolls inside the panel and the panel stays on screen. Open it with an
    empty list: panel shows an empty state, and F8 shows no JS or Lua error.
    RESULT:
13. Check F8 after steps 1-11.
    Expected: no red errors from fh_ui.
    RESULT:
14. `restart fh_ui` while a screen is open.
    Expected: the screen disappears, the mouse is released, movement works.
    RESULT:

## Q5: quests (fh_quests)

Server console lines start with `[fh_quests]`. Needs the `fh_quest_state` table (`server/migrations/0007_quest_state.sql`,
applied by `tools/setup-server.ps1`); `server.cfg` now ensures `fh_quests` after `fh_hunting`. `/jobs` opens the ox_lib fallback
board (the @ui board later). All coordinates, models and camp ids in it are guesses (TODO-verify-in-game). The ledger check means
the `fh_ledger` table on the DevPC DB, newest row for your citizenid. A step that needs another lane says so: mark it
`SKIP expected-blocked on <lane/block>`, not `FAIL`.

1. Boot with `ensure fh_quests` in `server.cfg` and join.
   Expected: no `[fh_quests] fh_quest_state missing` line, no `family ... rejected`/`failed to load`, no `built-in job type ...
   not registered`; `fh_quest_state` exists in the DB. `/jobs` opens the "Jobs board" menu (a missing table would answer
   `Board unavailable: fh_not_ready`).
   RESULT:
2. Board. Run `/jobs` (it works anywhere; the board spot/prop is at about -297, 795, 118).
   Expected: 3-5 Heartlands offers (pelt requests, "Clear out: Heartlands outlaw camp", wanted NPCs), each with a reward, plus
   "My active jobs" at the bottom. Accept a hunt offer: `Accepted: ...`; it comes back checked/disabled and shows under My active
   jobs. Abandon it there (confirm the dialog): `Job abandoned.`, and it is selectable on the board again.
   RESULT:
3. hunt_request. Take a pelt offer from step 2 and note its title (animal and stars, e.g. 2-star wolf). Sell a pelt of that animal
   and quality (or better) at the trapper (until @hunting H3 puts `animal` in the sold payload, any pelt of that quality counts).
   Expected: the job leaves My active jobs and pays its money once (+1 rep); the newest `fh_ledger` pay row has reason
   `quest:job:hunt_request:<animal>_<stars>star` (e.g. `quest:job:hunt_request:wolf_2star`). Sell a second matching pelt: no
   second payment and no second `quest:` row (no double reward). If this build has no trapper sell point yet (@hunting H3 not
   landed), the pelt cannot be sold: `RESULT: SKIP expected-blocked on @hunting H3`, and rerun this step then.
   RESULT:
4. bounty. Find a "Wanted: ..." offer, accept it and ride to the wanted NPC (Silas Crow about -128, 826, 117; Mabel Teague about
   -170, 860, 118).
   Expected: the NPC is there, visible and hostile. Kill it: the job completes for you, the acceptor, paid once; ledger reason
   `quest:job:bounty:bounty_<name_key>`. Then take the other bounty if it is on the board, confirm its NPC spawns, and abandon it
   from My active jobs: the NPC disappears and the job is gone with no payment.
   RESULT:
5. camp_clear (expected no-op). Accept "Clear out: Heartlands outlaw camp" and clear the camp (about -145, 845, 117).
   Expected: console `camp heartlands_t1_01 cleared`, but the job stays active at 0/1 and pays nothing: it credits only
   `payload.participants`, which fh_zones does not send yet (core idea-614). Specified, not a bug. Abandon the job afterwards.
   RESULT:
6. Board rotation. Note the current offer titles, keep the server up across the next hour boundary (rotation is a fixed 60 min
   board epoch) and run `/jobs` again.
   Expected: 3-5 offers again with a different set of titles (some may repeat); active jobs are untouched. A restart inside the
   same hour gives the same board. If you cannot wait out the boundary, `RESULT: SKIP` with the offers you saw.
   RESULT:
7. Givers, Hale. Find Ruth Hale (`u_f_m_tumgeneralstoreowner_01`) at about -296, 788, 118 and press E ("Talk to Ruth Hale").
   Expected: two intro lines, then "Will you take the job?" -> "I will" -> `Quest started.`; pressing E again says "Nothing more
   to say right now." until the steps are done. Claim a plot (`fh_claim`, about -300, 790, 118), earn $15+ in one payment (a
   sale, or console `fh_pay <yourId> 20`), then talk to her again: two closing lines and the reward. Cash +$40, +5 rep, ledger
   reason `quest:family_hale` exactly once; talking again pays nothing.
   RESULT:
8. Givers, Marrow. Sheriff Dell Marrow (`u_m_m_valsheriff_01`) at about -280, 805, 118. Same talk flow; the line starts on
   "Clear an outlaw camp."
   Expected: step 1 is EXPECTED-BLOCKED until core idea-614 lands: clear a camp and the step does not advance. If idea-614 has
   landed, clear a camp, sell 2 pelts (@hunting H3), report back: $60, +8 rep, reason `quest:family_marrow` once. Otherwise
   `RESULT: SKIP expected-blocked on idea-614` after confirming the dialogue/start part.
   RESULT:
9. Givers, Whitlock. Eli Whitlock (`cs_mp_oldtimer`) at about -315, 780, 118. Same talk flow; the line starts, and step 1 (sell a
   2+ star pelt, @hunting H3) advances.
   Expected: step 2 is EXPECTED-BLOCKED until @hunting H4 ships `fh:hunting:chain_complete` with `chain_id = legendary_bear`. If it
   has landed, finish the Legendary Bear hunt and report back: $120, +12 rep, reason `quest:family_whitlock` once. Otherwise
   `RESULT: SKIP expected-blocked on @hunting H4` after confirming step 1 advances and the line parks on step 2.
   RESULT:
10. Re-fire, relog, restart. With an active line mid-step (Marrow's pelt step, or Whitlock step 1) note its count; after a
    completed family line note your cash and rep. Quit and rejoin, then restart the server and rejoin.
    Expected: the `fh_quest_state` row (your citizenid + quest id) still has the same `step` and `progress.count`, and the line
    keeps going (family lines are not in `/jobs`; talking to the giver offers no new start). A done one-time line stays `done`
    and offers nothing to restart. Cash and rep unchanged and the ledger has no second `quest:` row: no double reward on relog
    or restart.
    RESULT:
11. TODO-verify-in-game (report values, not failures). Giver points/models: Hale -296, 788, 118.2 / `u_f_m_tumgeneralstoreowner_01`;
    Marrow -280, 805, 118.5 / `u_m_m_valsheriff_01`; Whitlock -315, 780, 118 / `cs_mp_oldtimer`. Board prop `p_notice_board01x`
    at -297, 795, 118 (the sphere target sits at the same point). Bounty model `g_m_m_unibanditos_01`; camp id
    `heartlands_t1_01`. Also the built-in job types registering through fh_quests' own export with same-resource function hooks:
    the boot console has no `built-in job type ... not registered`, the board listing all three types proves registration, and
    one bounty accept -> kill -> abandon runs the `accept`, `onEvent` and `abandon` hooks. Note any model or coordinate that
    needed changing.
    RESULT:

Known limits (not failures):
- Item rewards stay owed: fh_core refuses `backpack`/`equipped` item adds (idea-643), so a quest with `items` keeps
  `reward_pending`, pays money/rep once, retries on each load, and a repeatable with items cannot be taken again
  (`fh_reward_pending`). No shipped content uses item rewards yet.
- An active bounty is watched in memory: restarting the server loses its NPC and the job never completes. Abandon it from My
  active jobs (no cooldown) and accept it again; the NPC respawns.
