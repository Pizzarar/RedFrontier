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

## Homestead (H1-H4): slots, stations, comfort

Resource: `fh_homestead`. The build commands (slot tiers, trophy place/unplace) do not exist yet: H2 adds them, and trophies also need Hunting plus core B7. So only steps 1, 2, 9 and 10 can be run today; the rest are marked "after H2" and stay `SKIP` until then. Start from a character with no plot.

1. Stand inside the plot circle at (-300, 790, 118) and run `/fh_claim`.
   Expected: `fh_claim: claimed plot heartlands_01`. Run it again: it refuses (you already own a plot).
   RESULT:
2. Press E at the chest (-296, 790, 118) and put 1 bread in.
   Expected: the plot chest opens and takes it.
   RESULT:
3. Set slot tiers (build the workbench, campfire, tanning rack, trophy wall, cabin). After H2: there is no console or admin command for this in H1-H4.
   Expected (after H2): each build is saved; the server console shows no errors.
   RESULT:
4. Stations seen from crafting (after H2, needs @crafting). Stand within 3 m of a built workbench.
   Expected: crafting accepts the workbench for you (`isNearStation`), but not for another player or on a plot you do not own. Walk away: refused.
   RESULT:
5. Comfort value (after H2). With the cabin tier 1 (10) and the workbench (3) built.
   Expected: `getComfort` reads 13. Add the trophy wall (5): 18. A fresh character with no plot reads 0.
   RESULT:
6. Place a trophy (after H2, needs Hunting and core B7). Put one trophy item in the plot chest and place it on the wall.
   Expected: the item leaves the chest (count 1 to 0) and comfort rises by its points. With no trophy wall built: refused `fh_no_trophy_wall`, item stays in the chest.
   RESULT:
7. Unplace that trophy (after H2).
   Expected: the item is back in the chest exactly once (count 1, never 2) and comfort drops back. Doing it a second time is refused (`fh_no_trophy`), no extra item.
   RESULT:
8. Unclaim clears comfort (after H2, with slots and a trophy in place). Run `/fh_unclaim`.
   Expected: `fh_unclaim: released plot heartlands_01`; comfort reads 0. Claim again: slots and trophies are gone (a fresh plot).
   RESULT:
9. Claim and unclaim a plot with no builds.
   Expected: `/fh_unclaim` replies `fh_unclaim: released plot heartlands_01`, no red errors in the server console. (Known gap: bread left in the chest stays there and the next owner of the plot gets it.)
   RESULT:
10. Server restart: claim a plot, stop the server, start it, rejoin, press E at the chest.
    Expected: you still own the plot (`/fh_claim` there refuses) and the chest still holds its items. After H2, repeat with built slots and a placed trophy: the same tiers, comfort value and trophy are back.
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
5. Bounty rearm: relog. Accept a bounty ("Wanted: ..."; if step 4 used both, wait for the next rotation in step 8), note where
   the NPC stands, do NOT kill it, then quit and rejoin.
   Expected: while you are offline the NPC is gone (a second client sees it disappear), and about 3 s after your character loads
   a fresh NPC stands at the same spot (console has no `not re-armed` line). Kill it: the job completes for you and pays once,
   same `quest:job:bounty:bounty_<name_key>` ledger reason.
   RESULT:
6. Bounty rearm: disconnect. Accept a bounty you have not taken yet and note its spot, then quit and stay offline. As a second
   character/client, go to the spot and open the board.
   Expected: the NPC is gone, and that bounty is offered again: accepting it spawns a new NPC, with no `fh_bounty_taken`
   ("Somebody is already after that one."). Rejoin while that player still holds the offer: your old job row stays active
   without an NPC (console `not re-armed`); abandon it from My active jobs, which is the designed outcome. If they already
   finished or abandoned it, your NPC re-arms instead and the job plays normally.
   RESULT:
7. camp_clear. Accept "Clear out: Heartlands outlaw camp" and clear the camp (about -145, 845, 117) while standing inside it.
   Expected: console `camp heartlands_t1_01 cleared` and the job completes: you are within `activationRadius`, so you are in
   `payload.participants`; paid once, ledger reason `quest:job:camp_clear:camp_heartlands_t1_01`. No 0/1 no-op. Clearing it from
   outside the radius credits nobody (empty `participants`), which is specified.
   RESULT:
8. Board rotation. Note the current offer titles, keep the server up across the next hour boundary (rotation is a fixed 60 min
   board epoch) and run `/jobs` again.
   Expected: 3-5 offers again with a different set of titles (some may repeat); active jobs are untouched. A restart inside the
   same hour gives the same board. If you cannot wait out the boundary, `RESULT: SKIP` with the offers you saw.
   RESULT:
9. Giver reach and ped behaviour. Use Whitlock (his line is still unstarted) at about -315, 780, 118. Press E and let the intro
   lines run to "Will you take the job?", then move 6+ m away and confirm "I will".
   Expected: a `fh_too_far` notify (no `Quest started.`) and the line does not start: back within 5 m, E shows the intro and the
   start offer again. (The target prompt itself only reaches ~2.5 m, so this is the only by-hand path; if the open dialog pins
   your movement, mark `SKIP` with that note.) Then shoot the giver from close range, fire a shot beside him, sprint into him and
   wait a few seconds: he stays in place, does not flee or fight, takes no damage and cannot be killed.
   RESULT:
10. Givers, Hale. Find Ruth Hale (`u_f_m_tumgeneralstoreowner_01`) at about -296, 788, 118 and press E ("Talk to Ruth Hale").
    Expected: two intro lines, then "Will you take the job?" -> "I will" -> `Quest started.`; pressing E again says "Nothing more
    to say right now." until the steps are done. Claim a plot (`fh_claim`, about -300, 790, 118), earn $15+ in one payment (a
    sale, or console `fh_pay <yourId> 20`), then talk to her again: two closing lines and the reward. Cash +$40, +5 rep, ledger
    reason `quest:family_hale` exactly once; talking again pays nothing.
    RESULT:
11. Givers, Marrow. Sheriff Dell Marrow (`u_m_m_valsheriff_01`) at about -280, 805, 118. Same talk flow; the line starts on
    "Clear an outlaw camp."
    Expected: clear a camp from inside it (you must be in `payload.participants`) -> step 1 advances; sell 2 pelts, report back:
    $60, +8 rep, reason `quest:family_marrow` once. If this build has no trapper sell point yet (@hunting H3 not landed), mark
    the pelt half `SKIP expected-blocked on @hunting H3` and keep the step 1 result.
    RESULT:
12. Givers, Whitlock. Eli Whitlock (`cs_mp_oldtimer`) at about -315, 780, 118. Same talk flow (start the line now: step 9 only
    proved the far refusal); step 1 (sell a 2+ star pelt, @hunting H3) advances.
    Expected: step 2 is EXPECTED-BLOCKED until @hunting H4 ships `fh:hunting:chain_complete` with `chain_id = legendary_bear`. If it
    has landed, finish the Legendary Bear hunt and report back: $120, +12 rep, reason `quest:family_whitlock` once. Otherwise
    `RESULT: SKIP expected-blocked on @hunting H4` after confirming step 1 advances and the line parks on step 2.
    RESULT:
13. Re-fire, relog, restart. With an active line mid-step (Marrow's pelt step, or Whitlock step 1) note its count; after a
    completed family line note your cash and rep. Quit and rejoin, then restart the server and rejoin.
    Expected: the `fh_quest_state` row (your citizenid + quest id) still has the same `step` and `progress.count`, and the line
    keeps going (family lines are not in `/jobs`; talking to the giver offers no new start). A done one-time line stays `done`
    and offers nothing to restart. Cash and rep unchanged and the ledger has no second `quest:` row: no double reward on relog
    or restart.
    RESULT:
14. TODO-verify-in-game (report values, not failures). Giver points/models: Hale -296, 788, 118.2 / `u_f_m_tumgeneralstoreowner_01`;
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

## Progression (fh_progression, fh_fence, fh_hands)

Needs `ensure fh_progression`, `ensure fh_fence`, `ensure fh_hands` (shipped in `server.cfg`) and the `fh_ledger` / `fh_rep` / `fh_hands` tables (migrations 0002 and 0009). Admin test commands (console, or `group.admin` via ACE `command.<name>`; anything else is ignored): `/fh_rep <id> <region> <delta>` (lives in fh_progression and calls `fh_economy`'s `rep`; fh_economy still carries its older console-only `fh_rep <id> <delta>` with the same name, so if `fh_rep <id> heartlands 99` answers with no `fh_rep: ok` line or acts on heartlands without the region argument, the old one won: write FAIL and say so), `/fh_fence_next`, `/fh_hand_tick <id>`, plus `fh_pay <id> <amount>` from the server console. Use `heartlands` as the region. Tier gates: tier 2 at 100 rep, tier 3 at 400. `<id>` is your server id (`status` in F8, or the player list). Start with a fresh character at 0 rep and $0 unless a step says otherwise. Run with `set fh_spike_gated true` (as shipped) until step 4.

1. Rep tier gate: in the server console run `fh_rep <id> heartlands 99`. Walk to the fence (step 3 explains finding it) and open the menu with E.
   Expected: console `fh_rep: ok (heartlands +99 for <id>)`. Menu lists only common stock (bread, water); no gunsmith parts, no treasure lead.
   RESULT:
2. Run `fh_rep <id> heartlands 1` (rep 100 = tier 2), then reopen the fence menu. Then run `fh_rep <id> heartlands 300` (rep 400 = tier 3) and reopen it. Finally try bad input: `fh_rep abc heartlands 5`, `fh_rep <id> nowhere 5`, `fh_rep <id> heartlands 0`, `fh_rep <id> heartlands 2.5`, `fh_rep <id> heartlands 5000`.
   Expected: at 100 rep rare parts appear (gunsmith parts; at the camp stop saddlery fittings too) but no treasure lead. At 400 the treasure lead appears. Bad input prints `fh_rep: fh_bad_target`, `unknown_region`, `invalid_delta`, `invalid_delta`, `delta_too_large` and changes nothing. (`canUnlock` is exactly this gate: `contracts_t2`, `wagon_t2`, `fence_rare_stock`, `hire_hand` need tier 2, `fence_treasure_leads` needs tier 3.) Going back below the line (`fh_rep <id> heartlands -300`) hides the lead again on the next menu open.
   RESULT:
3. Fence schedule: in F8 or the console read the log line `[fh_fence] fence now at <stop>`. The fence rotates between `heartlands_road` and `heartlands_camp` every 20 minutes. Walk to the current stop (road: about -280 800 118; camp: about -170 830 117; coords are approximate, `fh_tp` helps). Run `fh_fence_next` in the console.
   Expected: console `[fh_fence] fh_fence_next: now at <the other stop> (next <the first>)` and a `fence now at` line. Menu E at the old stop now answers `Step closer to the fence.`; at the new stop it opens. Run `fh_fence_next` again: it returns to the first stop. (The test command skips the wait only; with no command the stop changes by itself on the 20 minute boundary.)
   RESULT:
4. `fh_spike_gated` on and off. With `set fh_spike_gated true` (default) stand at the current stop.
   Expected: no fence ped appears (spawn is held back), but the E prompt and menu still work. Now run `set fh_spike_gated false` in the console and wait up to 5 s (or run `fh_fence_next` twice).
   Expected: a fence ped spawns at the current stop (`[fh_core:spawn]` lines); on `fh_fence_next` it despawns and respawns at the new stop. Set it back to `true` afterwards: the ped goes away within 5 s.
   RESULT:
5. Tier-gated stock, per stop: at 100 rep (`fh_rep` to adjust) open the menu at each stop (use `fh_fence_next`).
   Expected: road stop: gunsmith parts $90; camp stop: gunsmith parts $95 and saddlery fittings $100. At 400 rep the lead is $250 (road) / $300 (camp). Common stock is bread and water ($3, $2) at the road stop and bread only at the camp.
   RESULT:
6. Buy rare parts: give yourself money (`fh_pay <id> 1000` in the server console), at 100+ rep buy 2 gunsmith parts. Check your backpack.
   Expected: `Bought.`, backpack holds 2 `Gunsmith Parts`, cash down by 2 x the price. A second look at the menu shows the same price (stock is not limited).
   RESULT:
7. Buy a treasure lead at 400+ rep.
   Expected: `Bought.`, backpack holds 1 `Treasure Lead` ($250 or $300 less cash). The item info carries the target hint text (inspect the item if your UI shows it; otherwise check the `fh_dump backpack <id>` console output).
   RESULT:
8. Sell: with parts in your backpack choose `Sell Gunsmith Parts` (pays $30 each) or saddlery ($35 each). Try selling more than you carry.
   Expected: `Sold N for $X.` with your cash up by exactly X and the parts gone. Selling more than you hold says `You don't have that to sell.` and nothing moves. The menu works again straight away.
   RESULT:
9. Insufficient funds: with less cash than a part costs (spend it or start at $0) try to buy 1 gunsmith part.
   Expected: `You can't afford that.` No item arrives, cash unchanged, and an immediate second attempt behaves the same (no stuck `The fence is still handling your last deal.`).
   RESULT:
10. charge_unavailable: only if core B7 (`fh_economy` `charge` export) is NOT merged on this server. Have cash and try to buy.
    Expected: `The fence is not taking payment right now.` No item, no cash change. Selling still works (it uses `pay`). If B7 IS merged, write `SKIP B7 merged` (the buy works as in step 6).
    RESULT:
11. One hand hired: at 100+ rep, with a homestead plot and its chest, run `fh_hand_hire <id> ranch_hand` (a test wrapper over the hire export, same admin restriction). Put $50 in cash (`fh_pay <id> 50`), keep feed under 40 in the plot chest (open with E), then run `fh_hand_tick <id>`. Below 100 rep the hire is refused with `locked`.
    Expected: console `fh_hand_tick: ticked <id>`. The ranch hand is paid $5 (`wage:ranch_hand` ledger row) and the chest feed went up by 10 (cap 40). Run it again: +10 more, until the chest holds 40, then the tick adds 0. The timer also runs on its own every 10 minutes (do not wait for it; this is the same code path).
    RESULT:
12. Unpaid wage: spend your cash to $0, then run `fh_hand_tick <id>` once.
    Expected: `fh_hand_tick: ticked <id>`, cash stays $0 (never negative), the chest feed does NOT rise (hand idles), `fh:hands:unpaid` appears in the server log if verbose. After 3 unpaid ticks in a row the hand quits; one paid tick before that resets the count. With B7 not merged the same happens with reason `charge_unavailable` even with cash (nothing is debited).
    RESULT:
13. Offline catch-up: with the hand hired and $50+ cash, note cash and the chest feed. Disconnect. In the server DB run `UPDATE fh_hands SET last_tick = last_tick - 3600;` (simulates an hour offline, 6 ticks, the cap). Rejoin and open the chest.
    Expected: on login the missed ticks run once each, capped at 6: at most $30 wages taken and feed topped up to the cap of 40. Wait 30 s: no extra ticks beyond that (no double charge).
    RESULT:
14. Fire: run `fh_hand_fire <id> ranch_hand`. Then `fh_hand_tick <id>`.
    Expected: `fh_hand_fire: ok (ranch_hand)`; `fh_hand_tick: no_hands`; no more wages or feed. Re-hiring with `fh_hand_hire` works again (no `already_hired`). Also try `fh_hand_tick` with a bad id (`abc`, `0`, a disconnected id): `fh_bad_target` / `no_player`.
    RESULT:
15. Permission check: as a non-admin player run `/fh_rep <id> heartlands 5`, `/fh_fence_next`, `/fh_hand_tick <id>` and `/fh_hand_hire <id> ranch_hand` from F8.
    Expected: nothing happens (no rep change, the fence does not move, no tick). The same three from the server console or as `group.admin` work.
    RESULT:

## Hunting

### H2 skin flow (fh_hunting)

All unverified in-game.

1. Spawn a test deer: `fh_spawn_ped a_c_deer_01` (note the id it prints). Kill it with a head shot, stand within 5 m, use the rsg-target "Skin" option. Expected: progress bar, then a `pelt_deer` with 3 stars in your saddlebag; the carcass is deleted.
2. Spawn another deer, shoot it in the gut (belly). Skin it. Expected: a `pelt_deer` with 1 star.
3. Kill a bear (no wagon nearby) and try to skin it. Expected: refused with a notification (no wagon), no pelt, the carcass is still there and stays skinnable. Bring a wagon within 8 m and skin again: the pelt goes into the wagon.
4. Spam the Skin option twice on one carcass. Expected: exactly one pelt, the second request is refused or ignored.
5. After skinning a test deer, run `fh_despawn <id>` from step 1: fh_core re-requests an adopted carcass that disappears, so the deer respawns otherwise (see Known gaps).

   RESULT:

### H3 trapper (fh_hunting)

All unverified in-game. Needs `fh_economy` and the database running. Trapper coordinates are approximate: if `[E] Sell pelts` does not show, stand where the trapper should be, read your coordinates and adjust `Trapper.coords` in `fh_hunting/config.lua`.

1. Put a 1 star and a 3 star `pelt_deer` in your saddlebag (skin two deer: a gut shot gives 1 star, a head shot 3 stars). Note your cash.
2. Walk to the trapper (default near the Heartlands homestead), press E at the prompt. Expected: a menu listing both pelts with prices ($6 for the 1 star, $25 for the 3 star).
3. Sell the 1 star. Expected: "Sold Deer (1 star) for $6", cash +6, the pelt is gone from the saddlebag. Sell the 3 star: +$25, the pelt is gone.
4. Check the ledger: `SELECT kind, amount, reason, region_id FROM fh_ledger ORDER BY id DESC LIMIT 2;` Expected: two `pay` rows with reason `hunting:pelt`, region `heartlands`, amounts 25 and 6.
5. Try to sell from more than 4 m away (a stale menu, or a second client). Expected: refused, nothing paid, the pelt stays.
6. Big game: kill a bear (or bison), bring an owned wagon within 8 m (needs `fh_cargo`, roads-r1) and skin it. Expected: the pelt goes into the wagon. Skin one with no wagon: refused, the carcass stays and can be skinned again once the wagon is near.
7. With the wagon at the trapper, sell the bear pelt from the menu. Expected: $45 x 1.8 = $81 for a 3 star, and removed from the wagon.

   RESULT:

### H5 trophy comfort

Hunting only exposes `exports.fh_hunting:getTrophyComfort(item)` (`trophy_legendary_bear` = 25, nil otherwise); what Homestead shows when a trophy is placed (comfort gain, trophy_wall slot) is checked in the Homestead section.

### H4 legendary bear chain (fh_hunting)

All unverified in-game. One hunt per character. Marker/trapper coordinates are approximate: if a prompt does not show, stand where it should be, read your coordinates and adjust `LegendaryBear` in `fh_hunting/config.lua`.

1. New character (step 1): walk to the trapper. Expected: the prompt reads `[E] Ask about the legendary bear` (not `[E] Sell pelts`). Press E. Expected: cash -$25 (rsg-core `RemoveMoney`, no `fh_ledger` row until @core ships `fh_economy:charge`), and the server emits `fh:hunting:clue_found { step = 1 }`.
2. Go to the track marker (`markers[2]`, roughly -260, 800, 116). Expected: `[E] Inspect Bear tracks` shows; E emits `clue_found { step = 2 }`. A marker you are not on (or the carcass marker out of order) shows no prompt and is refused server-side.
3. **Relog mid-chain.** After step 2, leave and rejoin. Expected: the chain resumes at step 3 — the carcass marker (not the track) now shows its prompt, and the rumour is not re-buyable (the trapper prompt is back to `Sell pelts`).
4. Inspect the carcass marker (`markers[3]`, roughly -215, 812, 115). Expected: `clue_found { step = 3 }`, then the bear spawns at the final area and `fh:hunting:legendary_spawned` fires once. Inspecting the marker again changes nothing (one spawn per chain).
5. Kill the bear. Stand over it **without a wagon nearby** and use "Skin". Expected: refused with a notification (no wagon), no pelt, no trophy, the carcass stays and is still skinnable (the legendary pelt is cargo).
6. Bring a wagon within 8 m and skin again. Expected: `pelt_legendary_bear` (3 stars, cargo) lands in the wagon, `trophy_legendary_bear` (bulky) lands in your saddlebag, and `fh:hunting:chain_complete` fires once. Skinning again (or rebuying the rumour) is refused.

   RESULT:



## Crafting (fh_crafting, fh_gunsmith)

Preconditions: stations come from @homestead H3 (without fh_homestead started, crafting refuses `no_homestead` unless you
turn on `fh_dev 1` and use the dev stations), @core B7 `removeItem` is on main, and item moves need idea-615
(carried-inventory add/remove refuses, so crafting, restore and tonics refuse safely instead of eating items), the tonic
buff needs idea-612 (caps in fh_buffs), and `/fh_restore` needs an @core `setItemInfo` contract (idea-689, not built
yet: it refuses `no_set_info`). Fill every `RESULT:` with `PASS`, `FAIL <what you saw>` or `SKIP <why>`.

1. Loot the worn rifle. Clear the T1 camp (-145, 845, 117) and press E at the camp stash.
   Expected: the stash holds a Worn Rifle with `condition` between 20 and 45 in its item info (M1 "Worn Rifle
   (condition 20-45)"). It is `bulky`, so the backpack and the hotbar refuse it; it fits saddlebag and chest.
   RESULT:
2. Put the rifle where `/fh_restore` can read it: a chest, wagon or saddlebag near the bench. Open that container (press
   E) and note the rifle's slot inside it for step 4.
   Expected: the rifle is `bulky`, so the backpack and hotbar refuse it; it fits a saddlebag, wagon or chest. With the
   container open, the rifle shows in one of its slots.
   RESULT:
3. Have the open container (from step 2) within reach of a gunsmith station: build one on your plot (needs @homestead
   H3), or with `fh_dev 1` place the container near the dev gunsmith (-280.0, 805.0, 119.0). Run
   `fh_give <yourId> gun_parts 5`.
   Expected: 5 Gun Parts in the backpack. Nothing says `no_station` anymore.
   RESULT:
4. With the container still open, run `/fh_restore <slot>` (the rifle's slot from step 2) with 5 gun parts.
   Expected: chat `Restored to 60% condition using N gun parts.` (a worn rifle has no stars, so its cap is 60); the
   slot's condition info reads 60 and you hold `5 - N` parts. N is `ceil((60 - condition) / 20)`, e.g. condition 45 ->
   1 part, condition 20 -> 2 parts.
   RESULT:
5. Run `/fh_restore <slot>` again at 60.
   Expected: chat `That weapon is already at its best condition.` and no gun parts are taken.
   RESULT:
6. Craft rifle ammo. Stand at the reload station (-283.0, 805.0, 119.0 with `fh_dev 1`), run
   `fh_give <yourId> resource_gunpowder 2`, `fh_give <yourId> lead 2`, `fh_give <yourId> casings 2`, then
   `/fh_craft ammo_rifle`.
   Expected: chat `Done: Reload rifle ammo.`; inventory loses 2 Gun Powder, 2 Lead and 2 Brass Casings and gains 1
   Ammo Box Rifle (N). `/fh_craft ammo_revolver` with powder 1, lead 2, casings 2 gives 1 Revolver Ammo box instead.
   RESULT:
7. Brew a tonic. Stand at the apothecary (-286.0, 805.0, 119.0 with `fh_dev 1`), run
   `fh_give <yourId> herb_american_ginseng 2`, `fh_give <yourId> herb_wild_mint 1`, then `/fh_craft tonic_vigor`.
   Expected: chat `Done: Brew Vigor Tonic.`; 2 American Ginseng and 1 Wild Mint are gone and 1 Vigor Tonic is in the
   backpack. `/fh_craft tonic_steady` uses 2 Oregano + 1 Red Sage for 1 Steady Tonic.
   RESULT:
8. Drink the tonic from the inventory (use it, do not craft it again).
   Expected with idea-612 landed: the toast says `You drink the tonic.` and the Vigor Tonic count drops by 1. Without
   the caps: `The tonic has no effect right now. It was returned to you.` and the count is unchanged (safe refusal).
   RESULT:
9. Check the buff. `fh_buffs` has no HUD yet (client is a stub), so from the server console run
   `fh_buff <yourId> tonic_vigor 1.0 600`.
   Expected: the printed result keeps magnitude 1.15 (same-buff refresh uses `max(old, new)`), proving the drink applied
   it; the printed active list shows `tonic_vigor` with an expiry about 600 s out. Without idea-612 the list is empty.
   RESULT:
10. Failure path, no station. Have the open container (chest/wagon/saddlebag) itself 10+ m from every station, then run
    `/fh_craft ammo_rifle` and `/fh_restore <slot>`.
    Expected: `You need to be at the right station.` and `You need to be at a gunsmith station.` (the container is too
    far from the bench); no items move.
    RESULT:
11. Failure path, out of reach. Open the chest (or wagon/saddlebag) at the bench, then walk 10+ m away from it and run
    `/fh_restore <slot>`.
    Expected: `You are too far from that container.`; no items move. (The container stays open server-side after you
    walk away, so reach is re-checked.)
    RESULT:
12. Failure path, missing input and unknown recipe. With no lead in the pack run `/fh_craft ammo_rifle`; then run
    `/fh_craft nonsense`.
    Expected: `Missing: 2x resource_gunpowder (have 0), 2x lead (have 0), 2x casings (have 0)` (only short lines are
    listed, in recipe order) and `Unknown recipe.`; nothing is consumed. With no parts run `/fh_restore <slot>`: `You
    need gun parts.`
    RESULT:
13. Failure path, wrong slot. Run `/fh_restore 99` (empty), `/fh_restore x`, and `/fh_restore <slot>` on a container
    slot holding an item without condition.
    Expected: `Nothing in that slot.`, `Usage: /fh_restore <slot>`, and `That item has no condition to restore.`
    RESULT:
14. Failure path, wrong station type. With the open container near the reload station (not the gunsmith), run
    `/fh_restore <slot>`; at the gunsmith run `/fh_craft ammo_rifle`.
    Expected: both `no_station` messages (`You need to be at a gunsmith station.` / `You need to be at the right
    station.`); the station types do not substitute for each other.
    RESULT:
