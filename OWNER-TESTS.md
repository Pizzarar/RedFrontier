# Owner tests (one ordered checklist)

Run in the order of the "Playtest order" table below (the detailed sections are in lane-merge order, not run order). Each block appends its own
section here; keep the order. Fill every `RESULT:` with `PASS`, `FAIL <what you saw>` or `SKIP <why>`, then send the
file back. Setup for the first join is in `OWNER-STEPS.md`. Admin commands need your account in `group.admin`.

## Playtest order (start here)

One in-game session, in this order (it groups sections so state carries over: gear and money from early sections feed later ones). Setup is in `OWNER-STEPS.md`; give yourself the materials from its section 7 before Homestead and Crafting. Section headings below are links. Times are rough, about 390 minutes total.

| # | Section | ~min | Notes |
|---|---|---|---|
| 1 | [Core: B-access (owner auto-admin, friend allowlist) - do this first](#core-b-access-owner-auto-admin-friend-allowlist---do-this-first) | 5 | Steps 4-5 need a friend (second account); skip them if solo |
| 2 | [Tutorial (fh_tutorial): first-join intro](#tutorial-fh_tutorial-first-join-intro) | 15 | needs a NEW character (second slot); solo. Do it before anything else touches that character; the claim/pelt/jobs steps double as early checks of homestead, hunting and jobs |
| 3 | [World-01: walk the claims (fh_core regions, fh_homestead, fh_zones, fh_trade, fh_ui)](#world-01-walk-the-claims-fh_core-regions-fh_homestead-fh_zones-fh_trade-fh_ui) | 30 | solo; do early: it verifies and fixes coordinates (claims, camps, trade posts) that later sections walk to. Ride it; note corrected coords from `/where` |
| 4 | [B4c: spawn-request contract (fh_core)](#b4c-spawn-request-contract-fh_core) | 10 | solo |
| 5 | [B6b: one T1 outlaw camp (fh_zones)](#b6b-one-t1-outlaw-camp-fh_zones) | 15 | solo; also feeds spike S1 |
| 6 | [B6c: soft death (fh_death)](#b6c-soft-death-fh_death) | 15 | needs two characters (second client or character switch) |
| 7 | [B6d: M1 stash home + end-to-end card (fh_homestead, fh_zones, fh_death)](#b6d-m1-stash-home--end-to-end-card-fh_homestead-fh_zones-fh_death) | 10 | solo |
| 8 | [M1 end-to-end](#m1-end-to-end) | 20 | solo; the main one-pass check, do it with an empty inventory |
| 9 | [A-life: camp ownership (fh_alife, fh_zones)](#a-life-camp-ownership-fh_alife-fh_zones) | 15 | solo; right after M1 (needs the Heartlands camp cleared and `ensure fh_alife`); step 6 uses `/alife tick 30` (admin) |
| 10 | [B6e saddlebag](#b6e-saddlebag) | 10 | solo |
| 11 | [Homestead (H1-H4 + H2): slots, build, stations, comfort](#homestead-h1-h4--h2-slots-build-stations-comfort) | 30 | step with a second player at your workbench/comfort needs a friend (or 2nd character); get `lumber`/`nails` first: buy at the Valentine trade post or give via OWNER-STEPS section 7 |
| 12 | [Homestead > Town lots (H8-H10): buy, build, abandon, law-safe](#town-lots-h8-h10-buy-build-abandon-law-safe) | 15 | right after Homestead; needs $500 cash and lumber; step 5 needs a second character with under $300 and step 7 (law-safe) a second character too; find a lot with `/where lot` |
| 13 | [Survival (fh_survival, plan survival-01, S1-S5 combined)](#survival-fh_survival-plan-survival-01-s1-s5-combined) | 25 | solo; shorten durations in fh_survival/config.lua first; SKIP steps marked needs @core caps (idea-613). Its "S1-S5" are survival steps, not the spike verdicts |
| 14 | [Crafting (fh_crafting, fh_gunsmith)](#crafting-fh_crafting-fh_gunsmith) | 25 | solo; give materials first (OWNER-STEPS section 7) |
| 15 | [Hunting](#hunting) | 25 | solo; H2 skin flow, H3 trapper, H5 trophy comfort, H4 legendary bear chain (long), H7 |
| 16 | [Progression (fh_progression, fh_fence, fh_hands)](#progression-fh_progression-fh_fence-fh_hands) | 20 | solo; step 15 permission check needs a non-admin account (friend) |
| 17 | [Roads](#roads) | 40 | M4 wagon/freight and M5 heat; the second-character `fh_not_owner` check needs a friend; ungated passes only after spike verdicts S2/S3 are GO |
| 18 | [Q5: quests (fh_quests)](#q5-quests-fh_quests) | 25 | solo; do after Roads, freight needs quests + core B7; giver talk/accept now opens the fh_ui dialogue screen (reach steps need walking >5 m away) |
| 19 | [UI (fh_ui shell, buff/bag HUD, screens)](#ui-fh_ui-shell-buffbag-hud-screens) | 40 | solo; do last, live fence/jobs steps need those resources already exercised; steps 19-24 giver dialogue (step 23 walk >5 m away) |

Needs another person (table rows): 1 (B-access steps 4-5), 6 (death, two characters), 11 (Homestead second player), 12 (Town lots steps 5 and 7, second character), 16 (step 15 permission check as non-admin), 17 (`fh_not_owner` from a second character). Row 2 (Tutorial) needs a brand-new character slot, not a friend. Get your friend allowlisted first (OWNER-STEPS section 6) and run those steps in one go.

Out of order is fine for the HUD-only checks in UI, but run sections 1-8 first so there is state to look at. The Hunting subsections sit under one `## Hunting` heading ([Hunting](#hunting)).

### Spike verdicts you must record

Spikes are separate 5-minute cards in `server/resources/[spikes]/TEST-CARDS.md` (not in server.cfg: type `ensure spk_<name>` in the server console, run the `/spk_...` command in game, then write the last line `RESULT: GO|NO-GO|PARTIAL - <why>` in `server/resources/[spikes]/spk_<name>/README.md`). Do these after the sections they gate, or before if you want the ungated passes:

- **S1 `spk_camp`** (camp spawn + ownership, the M1 blocker): GO lets you flip `fh_spike_gated` to false for entity-ownership behaviour (see `server/resources/[fh]/fh_core/docs/spike-gated.md`, row 1). Run before/with section 3 and 6.
- **S2 `spk_chase`** (mounted wagon chase): gates night ambush + mounted chase (Roads M5 steps 22-23, `fh_heat`).
- **S3 `spk_wheel`** (wheel break): gates the ungated wheel break (Roads M4 step 7) and `fh_cargo`.
- S4 `spk_pelt` and S5 `spk_wear` have cards too; record them if time allows (not gated in this build).

After recording, flip with `set fh_spike_gated false` in the console only for the ungated passes in Progression step 4 and Roads steps 7, 23. Not to be confused with the Survival section's "S1-S5", which are survival steps.

---

## Core: B-access (owner auto-admin, friend allowlist) - do this first

1. Join (OWNER-STEPS section 4). On the DevPC, `server/logs/fxserver.log` has exactly one line `granted group.admin to license:<hash>`.
   RESULT:
2. In game, run an fh_ admin command, e.g. `fh_dump backpack <yourId>`: it replies (no "no permission").
   RESULT:
3. Restart the server (close its window, run `first-run.cmd`), rejoin: still admin (step 2 works), the console printed `access: re-applied 1 admin ...` at boot, and no new `granted` line in fxserver.log.
   RESULT:
4. Friend (optional, needs a second account): a not-yet-allowlisted connect is rejected with "You're not on this private server's allowlist. Ask the owner to add you..." (rsg-core's message; no `[RSGCORE]` prefix, shown once), and the server console prints one `allowlist: rejected <name> license:<hash>` line.
   RESULT:
5. Run `fh_allow license:<hash>` with that license; the friend reconnects and gets in, and `fh_dump backpack <theirId>` from THEIR client says no permission (they are not admin).
   RESULT:

## Tutorial (fh_tutorial): first-join intro

Resource: `fh_tutorial` (plan guide-02), built on fh_quests (quest `tutorial_intro`, kind `tutorial`; step order is `FhTutorialConfig.order` = greeting, inventory, eat_drink, claim_plot, stash, trade_post, hunt, gunsmith, jobs, cargo, fence, family). It auto-starts once on a character's first load (no `fh_tutorial_state` row), is skippable and never blocks anything. Prompts are plain `ox_lib` notifications titled `Tutorial`; steps with a place also draw a yellow GPS route. Needs `ensure fh_tutorial` after `fh_quests`, plus `fh_homestead`, `fh_trade`, `fh_hunting`, `fh_buffs`/`fh_survival`, `fh_gunsmith`, `fh_cargo`, `fh_fence` for their steps. Do this with a NEW character (create a second slot; an existing character that already has a row will not auto-start, see step 15). Everything here is read from code and is unverified in game; items that code cannot confirm say TODO-verify-in-game. Waypoint coordinates are copied from other lanes' configs and are approximate.

1. New character spawns clothed. Create a new character in the creator and finish it WITHOUT picking any clothes, then spawn.
   Expected: the character is wearing the default outfit (shirt, pants and boots from `RSG.DefaultClothes` in `rsg-character/shared/config.lua`, the frontier shirt/pants/boots for male or chemise/pants/boots for female), not underwear. TODO-verify-in-game: the hashes are from a data file and were never seen on screen.
   RESULT:
2. Wardrobe. Run `/wardrobe` (anywhere outside the clothing store and character select).
   Expected: the saved-outfits menu opens (`exports['rsg-character']:OpenWardrobe`); it is a no-op in a clothing store or character select. TODO-verify-in-game: whether a fresh character's default outfit is listed in it or the list starts empty.
   RESULT:
3. Greeting (step `greeting`). On first load, watch the notification area.
   Expected: a `Tutorial` notification: `Welcome to RedFrontier. This short guide covers your first day and never blocks you (skip any time with /tutorial skip).` No action needed: about 2.5 s later (client ack) it advances by itself to the next prompt. Console has no `[fh_tutorial] registerQuest failed`.
   RESULT:
4. Inventory (step `inventory`). Press `I`.
   Expected: prompt `Press I to open your inventory and see what you are carrying.` appears after the greeting; opening the inventory (client event `rsg-inventory:client:open`) advances to the eat/drink prompt. Pressing `I` during the 2.5 s greeting window does nothing (no skip). TODO-verify-in-game: that `I` really fires `rsg-inventory:client:open` in this build.
   RESULT:
5. Eat and drink (step `eat_drink`). Eat a food item and drink water (or any item that applies the `well_fed` or `hydrated` buff).
   Expected: prompt `Eat and drink to keep your needs up — a hungry rider is a slow one.`; the step advances on server event `fh:buffs:applied` with `well_fed` or `hydrated`. Buffs re-applied within 10 s of loading the character are ignored, so a relog does not skip the step. If you only ate, check whether one buff alone is enough (code accepts either); note which you used.
   RESULT:
6. Claim a plot (step `claim_plot`). Follow the yellow route to the Heartlands plot (about -500, 750, 105) and run `/fh_claim`.
   Expected: prompt `Find a homestead plot and claim it with /fh_claim.` with a route labelled `Homestead plot`; `fh_claim: claimed plot heartlands_01` advances it (event `fh:homestead:claimed`). TODO-verify-in-game: the route draws (RDR3 has no SET_NEW_WAYPOINT; the multi-route natives and `COLOR_YELLOW` are a guess).
   RESULT:
7. Stash (step `stash`). At your claimed plot, walk to the homestead chest and press `E` to open it.
   Expected: prompt `Open your homestead chest to stash what you cannot carry.` with a route labelled `Homestead chest` (about -496, 750, 105); opening the chest advances (client event `rsg-inventory:client:open` where the opened container id starts `fh:chest:`). TODO-verify-in-game: that pressing `E` on the chest opens `fh:chest:<plot>:1`, and that pressing `I` here does NOT advance it (plain inventory reports `inventory`, not `stash`).
   RESULT:
8. Trade post (step `trade_post`). Ride to the Valentine Trade Post (about -176, 630, 114) and open its menu.
   Expected: prompt `Ride to the Valentine Trade Post and open its menu to quote or sell goods.` with a route labelled `Valentine Trade Post`; opening the trade menu (client event `fh:trade:menu`) advances. You do not have to sell anything.
   RESULT:
9. Hunt (step `hunt`). Hunt an animal, skin it and sell the pelt to the trapper (about -299, 792, 118).
   Expected: prompt `Hunt an animal, skin it, then sell the pelt to the trapper — your first sale.` with a route labelled `Trapper`; the pelt sale (`fh:hunting:pelt_sold`) advances. Fastest in a test session: any pelt, see Hunting H2/H3.
   RESULT:
10. Gunsmith (step `gunsmith`). Restore a worn gun at your workbench with `/fh_restore` (needs a built workbench on your plot, or `fh_dev 1` dev stations, plus a worn gun and gun parts).
   Expected: prompt `Restore a worn gun at your workbench with /fh_restore.`; a successful restore advances it (client event `fh_gunsmith:conditionChanged`, emitted after `/fh_restore`). TODO-verify-in-game: the gunsmith has no menu — opening the workbench alone does NOT advance it, only a successful restore does.
   RESULT:
11. Jobs (step `jobs`). Run `/jobs`.
   Expected: prompt `Open the jobs board with /jobs to take on paid work.`; the board opens (`fh:ui:open` screen `jobs`) and the step advances. Close the board.
   RESULT:
12. Cargo (step `cargo`). Spawn a wagon and move a cargo crate into it.
   Expected: prompt `Haul a cargo run: get a wagon and move a crate into it.`; the step advances on the server event `fh:cargo:wagon_spawned` (fires when a wagon actually spawns). TODO-verify-in-game: wagons are not player-spawnable yet (`/fh_wagon` is admin-only; fh_core spawn kind `wagon` is unmerged), so an admin must `/fh_wagon t1` for the owner to advance this step.
   RESULT:
13. Fence (step `fence`). Find the roving fence and open its menu (press `E` near the current stop; it roves between two Heartlands stops every ~20 min).
   Expected: prompt `Find the fence and sell your illicit goods.` (no route: the fence roves); opening the fence screen (`fh:ui:open` screen `fence`) advances. You do not have to sell anything. TODO-verify-in-game: the fence moves, so find it by its map blip / `/where fence`, not a fixed route.
   RESULT:
14. Family giver (step `family`, the last). Walk to Ruth Hale (about -296, 788, 118) and talk to her (E, see Q5 step 10 for the dialogue).
   Expected: prompt `Meet a family quest giver — find Ruth Hale and introduce yourself.` with a route labelled `Ruth Hale`; talking to her advances it (fh_quests `talk` npc `npc_hale`), then the final notification `Tutorial complete — you know your way around now. Stay sharp out there.` TODO-verify-in-game: that opening Hale's dialogue counts as a `talk` for this step even before you accept her quest. The tutorial never blocks her normal family quest.
   RESULT:
15. Commands and persistence. At any step run `/tutorial`; then `/tutorial skip`; relog; then `/tutorial restart`.
   Expected: `/tutorial` re-shows the current step prompt and re-sets its route (with none active: `No active tutorial. Use /tutorial restart to replay it.`). `/tutorial skip` shows `Tutorial skipped. Bring it back any time with /tutorial restart.` and it does not return after a relog (row in `fh_tutorial_state`: `SELECT * FROM fh_tutorial_state WHERE citizenid = '<cid>';` shows `skipped = 1`). `/tutorial restart` clears the skip and starts again from the greeting, also after a completed run (the quest is repeatable with no cooldown). A relog mid-tutorial re-shows the current step. A finished tutorial never auto-starts again. To rerun it on an old character use `/tutorial restart`, not a new row; no admin command exists to delete the row.
   RESULT:
16. Never blocking. Skip the tutorial at step 1 (new character again, or `/tutorial restart` then `/tutorial skip`) and do the claim, a sale and Ruth Hale's quest normally.
   Expected: all of them work exactly as without the tutorial; no step is refused because the tutorial is skipped or incomplete.
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
   Expected: console `camp heartlands_t1_01 cleared, 2 loot entries` (3 when gun_parts drops, about 80%) once the last one dies (within ~2 s); the bodies vanish at that moment. No clear while one is alive.
   RESULT:
3b. (gun_parts, core-05 K1) Clear the outlaw camp several times (respawn between runs) and open the stash each time.
   Expected: it sometimes (about 80%) also holds 2-3 `gun_parts` (never 1, never 4+); other times none.
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
   Expected: `camp heartlands_t1_01 cleared, 2 or 3 loot entries` (3 when gun_parts drops).
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
8. Optional, B6f pane toggle (off by default: `set fh_saddlebag_pane false` in `server/server.cfg`). First confirm the inventory shows no Saddlebag/Backpack button. Then change it to `set fh_saddlebag_pane true`, restart, open the plot chest (E) with your horse beside you, click "Saddlebag" on your pane, drag bread chest -> pane (and a bulky item such as the Worn Rifle, if the chest has one), then walk 10+ m away.
   Expected: flag off: no button. Flag on: the pane shows the saddlebag's contents, the bread (and bulky item) land in the saddlebag (check with `/saddlebag` later), and walking away flips the pane back to the backpack within about a second with "You are too far away from that". Set the convar back to `false` after.
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
   Expected: it lists the active buff with its remaining time counting down live every second (core idea-610: the buff sync
   carries `remaining`; a `--` instead of a time is now a FAIL). With no buffs the widget is hidden.
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
   No overlap (idea-648): the heat indicator sits on the left edge below the chat box (about 36% down), clear of the chat, minimap and the right-side buff/bag panels. The card shows at most the 3 highest-heat factions (highest first) and, when more exist, one muted "+K more" line (it does not scroll, because the HUD ignores the mouse, and it never grows into the minimap); that only matters with 4+ factions, today there are 2. The /forecast panel may cover the heat card while it is open (accepted).
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
11b. Live fence (needs `ensure fh_fence`): stand at the current fence stop and press E. Elsewhere, press E and stay out of range.
    Expected: the fh_ui fence screen opens (no ox_lib menu): buy rows show item, price, category and a qty box (treasure lead fixed
    at 1), sell rows show what you hold. No autofocus, Enter does nothing. Buy 1 bread: an inline notice `Bought.` appears and the
    lists refresh. Try an unaffordable buy or a sell with 0 held (Sell is disabled): the refusal text shows inline on the screen.
    Walk out of range and click Buy: `Step closer to the fence.` shows inline. Esc closes and releases the mouse. Out of range with
    the screen closed, E shows the toast `Step closer to the fence.`.
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

15. Live jobs board (needs `ensure fh_quests`): run `/jobs`, then walk to the board spot (about -297, 795, 118) and use the target zone.
    Expected: both open the fh_ui Jobs Board (no ox_lib menu), the mouse works, no autofocus, Enter does nothing. Click Accept on an
    offer: the row flips to `Accepted` (no Accept button) and an inline notice confirms; the other offers stay. Try an offer
    that already left the board (e.g. a second client accepted it, or the board rotated under you): an inline refusal notice shows and
    the list refreshes. Expired state (a sync arriving after the board's expiry time, hard to force): the panel shows only `The board
    is being restocked.` with no old rows; `SKIP` if you cannot reach it. Esc closes.
    RESULT:
16. Journal: run `/journal` with two or more active jobs (accept some from step 15), one of which you started earlier.
    Expected: the journal screen opens with active entries first, then history. Click Abandon on an entry: the button changes to a
    confirm state and nothing is abandoned yet; click it again: the job is abandoned and leaves the active list. There is no click-away or timeout: an armed
    `Confirm abandon?` only reverts when you arm Abandon on another row (the first button goes back to `Abandon`, that job stays active),
    when an update/sync arrives, or when the screen closes (Esc, then `/journal` again: nothing was abandoned).
    RESULT:
17. Journal while the character is not loaded (e.g. `/journal` at the character-select screen, or right after login before spawn).
    Expected: the journal opens empty with an error notice, no Lua error in F8.
    RESULT:
18. Switch characters (log out to character select, load another), then `/journal`.
    Expected: only the new character's jobs show; the previous character's entries and notices are gone.
    RESULT:
19. `/fh_ui_demo dialogue`.
    Expected: a dialogue screen with the speaker name and the first page; Next pages through; after the last page the offer shows `I will` / `Not yet`; Enter does nothing; Esc closes and controls return.
    RESULT:
20. Walk to a family giver (Hale, Marrow or Whitlock) and use "Talk to <name>".
    Expected: the fh_ui dialogue screen opens (no ox_lib popups) with the giver's intro lines, then the `I will` / `Not yet` offer.
    RESULT:
21. Click `I will`.
    Expected: a `Quest started.` notice, the offer is gone; the quest appears in `/journal`.
    RESULT:
22. Talk to the same giver again.
    Expected: talk-step lines show if a step advanced, otherwise `Nothing more to say right now.` with a `Goodbye` button.
    RESULT:
23. Talk to a giver, walk more than 5 m away with the screen open, then click `I will`.
    Expected: a `You are too far away.` error notice and the quest is not started.
    RESULT:
24. Run `grep -rn "lib.alertDialog\|giver:talk\|giver:start" server/resources/[fh]/fh_quests`.
    Expected: no matches.
    RESULT:

## Homestead (H1-H4 + H2): slots, build, stations, comfort

Resource: `fh_homestead`. Everything runs today except steps 6-7, which need Hunting's `getTrophyComfort` (today step 6 shows the refusal). `<id>` is your server id (as in the fh_economy tests). Start from a character with no plot and an empty plot chest. Materials are taken from the plot chest, never from your pockets. If a `/giveitem` is refused as too heavy, give 20 at a time and move each batch into the chest.

1. Stand inside the plot circle at (-500, 750, 105) and run `/fh_claim`.
   Expected: `fh_claim: claimed plot heartlands_01`. Run it again: it refuses (you already own a plot).
   RESULT:
2. Press E at the chest (-496, 750, 105) and put 1 bread in.
   Expected: the plot chest opens and takes it.
   RESULT:
3. Build. Prepare: `/giveitem <id> lumber 65` (or buy 65 lumber at any trade post, $3 each, then give yourself that money back), move all 65 lumber into the plot chest, then `/givemoney <id> cash 500`. Note your cash (call it C).
   a. `/fh_build`
      Expected: `fh_build: plot heartlands_01: cabin 0/2 next: $150, 20 lumber; chest_2 0/1 next: $40, 8 lumber; chest_3 0/1 next: $60, 10 lumber; fence 0/1 next: $100, 15 lumber; station_1 0/1 next: $60, 10 lumber; station_2 0/1 next: $25, 5 lumber; station_3 0/1 next: $80, 12 lumber; trophy_wall 0/1 next: $120, 10 lumber`
   b. `/fh_build chest_2` (needs the cabin first).
      Expected: `fh_build: fh_prereq_missing`. Chest still 65 lumber, cash still C.
   c. Run these in order. After each one, check the reply and the lumber left in the plot chest:
      `/fh_build cabin` -> `fh_build: built cabin tier 1 ($150, 20 lumber)` (45 left)
      `/fh_build chest_2` -> `fh_build: built chest_2 tier 1 ($40, 8 lumber)` (37 left)
      `/fh_build station_1` -> `fh_build: built station_1 tier 1 ($60, 10 lumber)` (27 left)
      `/fh_build station_2` -> `fh_build: built station_2 tier 1 ($25, 5 lumber)` (22 left)
      `/fh_build station_3` -> `fh_build: built station_3 tier 1 ($80, 12 lumber)` (10 left)
      Expected: cash is now C - 355. A placeholder prop (`p_chest01x`) stands at each built slot. Walk up to the chest_2 prop at about (-504, 750): `[E] Homestead chest 2` shows, and E opens an empty chest.
   d. No trophy wall yet: `/fh_trophy place bread` (the bread from step 2; the wall is checked before anything else).
      Expected: `fh_trophy: fh_no_trophy_wall`. The bread is still in the chest (count 1).
   e. `/fh_build trophy_wall`
      Expected: `fh_build: built trophy_wall tier 1 ($120, 10 lumber)`. 0 lumber left, cash C - 475.
   f. Money refund: `/setmoney <id> cash 50`, give 15 lumber and move it into the chest, run `/fh_build fence`.
      Expected: `fh_build: fh_insufficient_funds (not enough cash)`. The chest still has 15 lumber (taken and put back), cash is still $50.
      Then `/givemoney <id> cash 100` and `/fh_build fence`.
      Expected: `fh_build: built fence tier 1 ($100, 15 lumber)`, cash $50, 0 lumber left.
   g. Item refund: give 40 lumber and 5 nails, move both into the chest, run `/fh_build cabin` (tier 2 needs 40 lumber + 20 nails).
      Expected: `fh_build: fh_not_enough (not enough nails in your plot chest (materials are taken from the chest))`. The chest still has 40 lumber and 5 nails, cash is still $50.
   h. DB: `SELECT kind, amount, reason FROM fh_ledger WHERE reason LIKE 'homestead%' ORDER BY id;`
      Expected: exactly 7 rows, all `charge`, `homestead build`, amounts 150, 40, 60, 25, 80, 120, 100. No row for the refused attempts and no `homestead build refund` row.
      The server console shows no red errors and no `ITEM LOST` / `MONEY LOST` line.
   RESULT:
4. Stations (what @crafting will ask through `isNearStation`). Prop spots: workbench about (-494, 754), campfire (-494, 746), tanning rack (-490, 750).
   Expected:
   - At the workbench: `/fh_station workbench` -> `fh_station: workbench near=true`; `/fh_station campfire` -> `fh_station: campfire near=false`.
   - At the campfire: `/fh_station campfire` -> `fh_station: campfire near=true`.
   - Walk to the plot center (-500, 750): `/fh_station workbench` -> `fh_station: workbench near=false` (more than 3 m away).
   - A second player with no plot stands at your workbench and runs `/fh_station workbench` -> `fh_station: workbench near=false` (owner-only).
   RESULT:
5. Comfort. Built after step 3: cabin 1 (10), chest_2 (2), the three stations (3 each), trophy wall (5), fence (5).
   Expected: `/fh_comfort` -> `fh_comfort: 31`. The second player (no plot) -> `fh_comfort: 0`.
   RESULT:
6. Place a trophy.
   Today (Hunting has no `getTrophyComfort` yet): run `/fh_trophy place bread`.
   Expected: `fh_trophy: fh_hunting_unavailable`, the bread is still in the chest (count 1), `/fh_comfort` is still 31, and the console warns `fh_hunting:getTrophyComfort failed`.
   Once Hunting has it: put one `trophy_legendary_bear` in the plot chest (it is bulky: carry it by saddlebag or wagon, it does not fit the backpack) and run `/fh_trophy place trophy_legendary_bear`.
   Expected: `fh_trophy: place ok trophy_legendary_bear#1`, the chest count goes 1 -> 0, and `/fh_comfort` rises by the trophy's points (trophy comfort is capped at 20 in total).
   RESULT:
7. Unplace that trophy (only after step 6 placed it; SKIP until then). Run `/fh_trophy remove trophy_legendary_bear#1`.
   Expected: `fh_trophy: remove ok`, the trophy is back in the chest exactly once (count 1, never 2), and `/fh_comfort` -> `fh_comfort: 31`. Run it a second time: `fh_trophy: fh_no_trophy`, and the count stays 1.
   RESULT:
8. Unclaim clears the plot, and no chest contents pass to the next owner (H13). The main chest still holds the bread, 40 lumber and 5 nails from step 3; put 1 more bread into chest 2.
   a. Run `/fh_unclaim`.
      Expected: `fh_unclaim: fh_chests_not_empty`. Nothing changes: the props stay, `/fh_build` still lists your tiers, both chests keep their items.
   b. (Needs the friend, a non-admin.) The friend runs `/fh_unclaim heartlands_01 force`.
      Expected: `fh_unclaim: fh_not_admin`, nothing changes.
   c. Admin force: on the server console run `fh_unclaim heartlands_01 force`.
      Expected: `[fh_homestead] fh_unclaim: released plot heartlands_01`, and before it one yellow line per item: `force unclaim: plot=heartlands_01 owner=<cid> stash=fh:chest:heartlands_01:1 slot=<n> item=bread count=1 cleared` (then the lumber and nails lines), plus one for the bread in `fh:chest:heartlands_01:2`. No red lines. All slot props disappear. `/fh_comfort` -> `fh_comfort: 0`. `/fh_build` -> `fh_build: fh_no_plot`.
      DB: `SELECT * FROM fh_plot_slots WHERE plot_id = 'heartlands_01';` -> 0 rows.
   d. Run `/fh_claim` there again: `fh_claim: claimed plot heartlands_01`; `/fh_build` lists every slot at 0 again (`cabin 0/2 next: $150, 20 lumber; ...`); `/fh_comfort` -> `fh_comfort: 0`. E at the main chest opens an EMPTY chest (no bread, lumber or nails).
   RESULT:
9. Unclaim a plot with no builds (you hold heartlands_01 from step 8d). Put 1 bread in the plot chest and run `/fh_unclaim`.
   Expected: `fh_unclaim: fh_chests_not_empty`. Take the bread back out of the chest and run `/fh_unclaim` again: `fh_unclaim: released plot heartlands_01`, no red errors in the server console.
   RESULT:
10. Server restart. Claim heartlands_01 again with `/fh_claim` (step 9 left you without a plot). Make sure the plot chest holds at least 30 lumber and you have at least $210 cash. Run `/fh_build cabin`, then `/fh_build station_1`, put 1 bread in the chest, then stop the server, start it and rejoin.
    Expected:
    - `/fh_claim` at the plot refuses (you still own it).
    - `/fh_build` shows `cabin 1/2 next: $400, 40 lumber, 20 nails` and `station_1 1/1 (max)`.
    - The cabin and workbench props are back.
    - `/fh_comfort` -> `fh_comfort: 13`.
    - At the workbench, `/fh_station workbench` -> `fh_station: workbench near=true`.
    - E at the chest shows the bread and the leftover lumber.
    After Hunting: also build the trophy wall and place a trophy before the restart; after it, the trophy is still on the wall (`/fh_trophy remove` works once) and comfort is the same as before the restart.
    RESULT:

### Town lots (H8-H10): buy, build, abandon, law-safe

Resource: `fh_homestead` (+ `fh_economy`, `fh_heat` for step 7). One lot AND one claim per character. Lots are found with `/where lot` (routes to the nearest free lot, labelled `<name> (town lot)`; an owned or not-yet-claimable lot is skipped), not `/where plot` (claims only). The Valentine lot `heartlands_lot_01` is at (-180, 620, 113), radius 14 m; its chest is at the center. Start with no lot, at least $500 cash (note it as C) and 0 rep in heartlands (`SELECT value FROM fh_rep WHERE region_id = 'heartlands' AND citizenid = '<cid>';`).

1. Buy. Stand in the lot and run `/fh_buylot`.
   Expected: `fh_buylot: bought lot heartlands_lot_01`. Cash C - 300. heartlands rep +25. E at the lot chest opens it.
   DB: `SELECT plot_id, class FROM fh_plots WHERE citizenid = '<cid>';` -> `heartlands_lot_01 town_lot` (plus your claim if you hold one). `SELECT kind, amount, reason FROM fh_ledger WHERE reason LIKE 'town_lot%' ORDER BY id;` -> exactly two rows: `charge` 300 `town_lot:heartlands_lot_01`, then `rep` 25 `town_lot` (fh_economy writes rep changes to the ledger too). No `town_lot_refund` row.
   RESULT:
2. Refusals (no money moves). `/fh_buylot` again in the same lot -> `fh_buylot: fh_plot_taken`; walk to the Emerald Ranch lot (1420, 345, 96) and run it -> `fh_buylot: fh_already_has_lot`; stand in a claim and run `/fh_buylot` -> `fh_buylot: fh_wrong_plot_class`. Cash still C - 300 after all three.
   RESULT:
3. One of each. Walk to a free claim (for example heartlands_01 at (-500, 750, 105)) and `/fh_claim`.
   Expected: `fh_claim: claimed plot heartlands_01` while you still own the lot.
   RESULT:
4. Build on the lot. Put 20 lumber in the LOT chest, have $100+ cash, stand in the lot.
   - `/fh_build` -> `fh_build: plot heartlands_lot_01: chest_2 0/1 next: $40, 8 lumber; station_1 0/1 next: $60, 10 lumber` (no cabin, fence or trophy wall).
   - `/fh_build cabin` -> `fh_build: fh_unknown_slot`, nothing taken.
   - `/fh_build station_1` -> `fh_build: built station_1 tier 1 ($60, 10 lumber)`; `/fh_build chest_2` -> `fh_build: built chest_2 tier 1 ($40, 8 lumber)` (no cabin needed). The lumber came out of the lot chest, not the claim chest.
   - At the workbench prop about (-174, 624): `/fh_station workbench` -> `near=true`. `[E] Homestead chest 2` at about (-184, 620) opens.
   - `/fh_comfort` is the same as before the lot builds (a lot gives no comfort).
   RESULT:
5. Cannot afford. With a second character (no lot) holding less than $300, stand in a free lot and `/fh_buylot`.
   Expected: `fh_buylot: fh_insufficient_funds`, cash unchanged, no `fh_plots` row for that lot.
   RESULT:
6. Abandon (no refund, rep taken back). With the 2 lumber from step 4 still in the lot chest, run `/fh_unclaim heartlands_lot_01`.
   Expected: `fh_unclaim: fh_chests_not_empty`, heartlands rep unchanged (H13: a lot with items in chest 1 or chest 2 is not released). Take the lumber out (and anything in chest 2), then, in or out of the lot, run `/fh_unclaim heartlands_lot_01` again.
   Expected: `fh_unclaim: released plot heartlands_lot_01`. Cash unchanged (no refund). heartlands rep -25 (back to what it was before step 1). The lot props disappear; your claim is untouched (`/fh_build` at the claim still works). A bare `/fh_unclaim` would release the claim, not the lot.
   Buy it again (`/fh_buylot` in the lot): cash -300, rep +25 again, so buy-abandon-buy nets one +25 bump.
   Admin abandon with the owner OFFLINE: quit the game, then on the server console run `fh_unclaim heartlands_lot_01`.
   Expected: `released plot heartlands_lot_01`, no `without rep-back` line, and `SELECT value FROM fh_rep WHERE region_id = 'heartlands' AND citizenid = '<cid>';` is 25 lower than before (the rep is taken back while you are offline; ledger row `rep` -25 `town_lot_abandon`). Rejoin and buy the lot back (`/fh_buylot`) for step 7.
   RESULT:
7. Law encounters skipped in your own lot, not in a stranger's. Roadblocks fire when heat CROSSES the roadblock level (as in M5 step 17), so each check is: heat to 0, then to 55. Own heartlands_lot_01 (step 6) and stand in the middle of it. Run `exports.fh_heat:set(<yourId>, "outlaws", 0)`, then `exports.fh_heat:set(<yourId>, "outlaws", 55)`.
   Expected: no roadblock spawns; the console shows once `[fh_heat] <id>/<cid> law-safe in own lot heartlands_lot_01: skipping spawn`. Walk out of the lot (more than 14 m from its center), set heat 0 then 55 again: the roadblock spawns as in M5 step 17 (the skipped one started no cooldown). Set heat back to 0.
   Second character (no lot of their own) stands in YOUR lot and does the same 0 -> 55: their roadblock spawns normally and there is no law-safe line for them. Also at your wilderness claim (step 3) a 0 -> 55 spawns normally (claims are not law-safe).
   RESULT:

## Q5: quests (fh_quests)

Server console lines start with `[fh_quests]`. Needs the `fh_quest_state` table (`server/migrations/0007_quest_state.sql`,
applied by `tools/setup-server.ps1`); `server.cfg` now ensures `fh_quests` after `fh_hunting`. `/jobs` opens the fh_ui jobs
board. All coordinates, models and camp ids in it are guesses (TODO-verify-in-game). The ledger check means
the `fh_ledger` table on the DevPC DB, newest row for your citizenid. A step that needs another lane says so: mark it
`SKIP expected-blocked on <lane/block>`, not `FAIL`.

1. Boot with `ensure fh_quests` in `server.cfg` and join.
   Expected: no `[fh_quests] fh_quest_state missing` line, no `family ... rejected`/`failed to load`, no `built-in job type ...
   not registered`; `fh_quest_state` exists in the DB. `/jobs` opens the fh_ui Jobs Board (a missing table would answer
   `Board unavailable: fh_not_ready`).
   Also: fh_quests starts with no ox_lib or script errors in the server console (ox_lib dependency removed).
   RESULT:
2. Board. Run `/jobs` (it works anywhere; the board spot/prop is at about -297, 795, 118).
   The board region is picked automatically from where you stand (`/jobs` uses the nearest enabled board spot in `fh_quests/client/board.lua`; there is no region selector). Enabled regions today: heartlands, scarlett_meadows, bayou_nwa, great_plains (`FhRegions.isEnabled`); only heartlands and scarlett_meadows have a board spot (Rhodes board at about 1288, -1278, 77, unverified) and only heartlands has job templates, so the Rhodes board answers with an empty list (no offers) and bayou_nwa/great_plains have no board and no offers. Standing anywhere else, `/jobs` falls back to the nearest enabled spot. The Cormier and Ashby family steps (12b/12c) are covered below, not here.
   Expected: 3-5 Heartlands offers (pelt requests, "Clear out: Heartlands outlaw camp", wanted NPCs), each with a reward and an Accept button.
   Accept a hunt offer: its row shows `Accepted` instead of the button and an inline notice confirms. Abandon it in `/journal`: click
   Abandon, then click the `Confirm abandon?` button a second time; the job leaves the journal and its offer is selectable on the board again.
   RESULT:
3. hunt_request. Take a pelt offer from step 2 and note its title (animal and stars, e.g. 2-star wolf). First sell a pelt of
   another animal with enough stars at the trapper (e.g. a deer pelt for a wolf request): the job stays in My active jobs and
   no `quest:` row is paid. Then sell a pelt of that animal and quality (or better).
   Expected: the job leaves My active jobs and pays its money once (+1 rep); the newest `fh_ledger` pay row has reason
   `quest:job:hunt_request:<animal>_<stars>star` (e.g. `quest:job:hunt_request:wolf_2star`). Sell a second matching pelt: no
   second payment and no second `quest:` row (no double reward).
   RESULT:
4. bounty. Find a "Wanted: ..." offer, accept it and ride to the wanted NPC (Silas Crow about -128, 826, 117; Mabel Teague about
   -170, 860, 118).
   Expected: the NPC is there, visible and hostile. Kill it: the job completes for you, the acceptor, paid once; ledger reason
   `quest:job:bounty:bounty_<name_key>`. Then take the other bounty if it is on the board, confirm its NPC spawns, and abandon it
   in `/journal` (Abandon, then `Confirm abandon?`): the NPC disappears and the job is gone with no payment.
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
   without an NPC (console `not re-armed`); abandon it in `/journal` (Abandon, then `Confirm abandon?`), which is the designed outcome. If they already
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
9. Giver reach and ped behaviour. Use Whitlock (his line is still unstarted) at about -315, 780, 118. Press E and click Next through the
   intro lines on the dialogue screen until it shows "Will you take the job?", then move 6+ m away and click "I will".
   Expected: an error notice on the dialogue screen ("You are too far away.", no `Quest started.`) and the line does not start:
   back within 5 m, E opens the dialogue with the intro and the start offer again. (The target prompt itself only reaches ~2.5 m,
   so this is the only by-hand path; if the open dialogue pins your movement, mark `SKIP` with that note.) Then shoot the giver from close range, fire a shot beside him, sprint into him and
   wait a few seconds: he stays in place, does not flee or fight, takes no damage and cannot be killed.
   RESULT:
10. Givers, Hale. Find Ruth Hale (`u_f_m_tumgeneralstoreowner_01`) at about -296, 788, 118 and press E ("Talk to Ruth Hale").
    Expected: the dialogue screen opens with two intro lines (Next pages through), then "Will you take the job?" -> "I will" ->
    a `Quest started.` notice and the offer disappears; pressing E again shows "Nothing more to say right now." until the steps are done. Claim a plot (`fh_claim`, about -300, 790, 118), earn $15+ in one payment (a
    sale, or console `fh_pay <yourId> 20`), then talk to her again: two closing lines on the dialogue screen and the reward. Cash +$40, +5 rep, ledger
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
12b. Givers, Cormier (C6, Lemoyne). Odile Cormier (`a_f_m_lagtownfolk_01`) at about 2180, -1112, 25 (offset from the Lagras town
    point). Walk up within 5 m, press E: fh_ui dialogue opens with two intro lines, then "Will you take the job?" -> "I will" ->
    `Quest started.` Steps in order: (1) skin an alligator (`fh:hunting:pelt_skinned`, animal alligator); (2) clear a Swamp Gang
    camp in `bayou_nwa` (be inside it); (3) sell 2 pelts; (4) talk to Odile again for the two closing lines.
    Expected: each step advances in order; one-time payout $70, +8 rep (`bayou_nwa`), ledger reason `quest:family_cormier` once;
    talking again pays nothing. Giver coords and ped model are TODO-verify-in-game (report values, not failures).
    ALLIGATOR CHECK: the alligator is cargo-size (size_class `cargo`, weight 20000). Confirm in game that it can be skinned and that
    `fh:hunting:pelt_skinned` fires for it (step 1 advances). If it cannot be skinned or the event never fires, FAIL and note it
    (the step then cannot be completed).
    RESULT:
12c. Givers, Ashby (C6, West Elizabeth). June Ashby (`a_f_m_blwtownfolk_01`) at about -850, -1330, 44.5 (offset from the Blackwater
    town point). Same talk flow (within 5 m, accept). Steps in order: (1) skin a wolf or coyote; (2) clear a camp in `great_plains`;
    (3) sell a quality 2+ pelt; (4) talk to June again for the two closing lines.
    Expected: $75, +8 rep (`great_plains`), reason `quest:family_ashby` once; talking again pays nothing. Giver coords and ped model
    are TODO-verify-in-game (report values, not failures). If no trapper sell point exists yet, mark the pelt step
    `SKIP expected-blocked on @hunting H3` after confirming steps 1 and 2.
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

Needs `ensure fh_progression`, `ensure fh_fence`, `ensure fh_hands` (shipped in `server.cfg`) and the `fh_ledger` / `fh_rep` / `fh_hands` tables (migrations 0002 and 0009). Admin test commands (console, or `group.admin` via ACE `command.<name>`; anything else is ignored): `/fh_rep_region <id> <region> <delta>` (fh_progression; calls `fh_economy`'s `rep`. Not to be confused with fh_economy's own console `fh_rep <id> <delta>`, which these steps do not use), `/fh_fence_next`, `/fh_fence_settle <id>`, `/fh_hand_tick <id>`, plus `fh_pay <id> <amount>` from the server console. Use `heartlands` as the region. Tier gates: tier 2 at 100 rep, tier 3 at 400. `<id>` is your server id (`status` in F8, or the player list). Start with a fresh character at 0 rep and $0 unless a step says otherwise. Run with `set fh_spike_gated true` (as shipped) until step 4.

1. Rep tier gate: in the server console run `fh_rep_region <id> heartlands 99`. Walk to the fence (step 3 explains finding it) and press E to open the fence screen.
   Expected: console `fh_rep_region: ok (heartlands +99 for <id>)`. The fence screen's For sale list shows only common stock (bread, water): no gunsmith parts, no treasure lead.
   RESULT:
2. Run `fh_rep_region <id> heartlands 1` (rep 100 = tier 2), then reopen the fence screen (Esc, then E). Then run `fh_rep_region <id> heartlands 300` (rep 400 = tier 3) and reopen the fence screen (Esc, then E). Finally try bad input: `fh_rep_region abc heartlands 5`, `fh_rep_region <id> nowhere 5`, `fh_rep_region <id> heartlands 0`, `fh_rep_region <id> heartlands 2.5`, `fh_rep_region <id> heartlands 5000`.
   Expected: at 100 rep rare-category rows appear (gunsmith parts; at the camp stop saddlery fittings too) but no leads-category row. At 400 the treasure lead appears. Bad input prints `fh_rep_region: fh_bad_target`, `unknown_region`, `invalid_delta`, `invalid_delta`, `delta_too_large` and changes nothing. (`canUnlock` is exactly this gate: `contracts_t2`, `wagon_t2`, `fence_rare_stock`, `hire_hand` need tier 2, `fence_treasure_leads` needs tier 3.) Going back below the line (`fh_rep_region <id> heartlands -300`) hides the lead again on the next screen open.
   RESULT:
3. Fence schedule: in F8 or the console read the log line `[fh_fence] fence now at <stop>`. The fence rotates between `heartlands_road` and `heartlands_camp` every 20 minutes. Walk to the current stop (road: about -280 800 118; camp: about -170 830 117; coords are approximate, `fh_tp` helps). Run `fh_fence_next` in the console.
   Expected: console `[fh_fence] fh_fence_next: now at <the other stop> (next <the first>)` and a `fence now at` line. E at the old stop shows the toast `Step closer to the fence.` and the screen does not open; if the screen was left open, a Buy click shows that text inline. At the new stop it opens. Run `fh_fence_next` again: it returns to the first stop. (The test command skips the wait only; with no command the stop changes by itself on the 20 minute boundary.)
   RESULT:
4. `fh_spike_gated` on and off. With `set fh_spike_gated true` (default) stand at the current stop.
   Expected: no fence ped appears (spawn is held back), but the E prompt and fence screen still work. Now run `set fh_spike_gated false` in the console and wait up to 5 s (or run `fh_fence_next` twice).
   Expected: a fence ped spawns at the current stop (`[fh_core:spawn]` lines); on `fh_fence_next` it despawns and respawns at the new stop. Set it back to `true` afterwards: the ped goes away within 5 s.
   RESULT:
5. Tier-gated stock, per stop: at 100 rep (`fh_rep_region` to adjust) open the fence screen at each stop (use `fh_fence_next`).
   Expected: road stop: gunsmith parts $90; camp stop: gunsmith parts $95 and saddlery fittings $100. At 400 rep the lead is $250 (road) / $300 (camp). Common stock is bread and water ($3, $2) at the road stop and bread only at the camp.
   RESULT:
6. Buy rare parts: give yourself money (`fh_pay <id> 1000` in the server console), at 100+ rep buy 2 gunsmith parts. Check your backpack.
   How to trade (steps 6-9): type the qty in the row's qty box and click Buy/Sell; Enter does not submit. Result texts are unchanged but appear as an inline notice on the screen, not an ox_lib toast. The lists refresh after each trade. Sell rows show the amount held and Sell is disabled at 0. `You don't have that to sell.` only appears if the stack changed after the screen was fetched. The treasure lead row's qty is fixed at 1.
   Expected: `Bought.`, backpack holds 2 `Gunsmith Parts`, cash down by 2 x the price. The refreshed lists show the same price (stock is not limited).
   RESULT:
7. Buy a treasure lead at 400+ rep.
   Expected: `Bought.`, backpack holds 1 `Treasure Lead` ($250 or $300 less cash). The item info carries the target hint text (inspect the item if your UI shows it; otherwise check the `fh_dump backpack <id>` console output).
   RESULT:
8. Sell: with parts in your backpack, under Your goods sell `Gunsmith Parts` ($30 each) or `Saddlery Fittings` ($35 each). Also type a qty higher than `you hold N` and click Sell (or sell until 0 held).
   Expected: `Sold N for $X.` with your cash up by exactly X and the parts gone (the fence stash is emptied with fh_core `removeItem`: no `[fh_fence] WARNING sell: removing` line in the console). Typing above `you hold N` clamps to `N` (selling at most what you hold); once held reaches 0, the row's qty box and Sell button are disabled (`You don't have that to sell.` only fires if the stack drops server-side after the screen was fetched). The screen works again straight away.
   RESULT:
9. Insufficient funds: with less cash than a part costs (spend it or start at $0) try to buy 1 gunsmith part.
   Expected: `You can't afford that.` No item arrives, cash unchanged, and an immediate second attempt behaves the same (no stuck `The fence is still handling your last deal.`).
   RESULT:
10. Buy debit ledger (core B7 `charge`): after step 6, look at the `fh_ledger` table in the DB (newest rows).
    Expected: one row `kind = charge`, `amount` = 2 x the gunsmith price, `reason = fence_buy:fh_part_gunsmith`, `region_id = heartlands`; no extra charge rows for the failed attempts of step 9. (`charge_unavailable` / `The fence is not taking payment right now.` only shows if fh_economy's `charge` export throws; the specs cover it, nothing to do here.)
    RESULT:
11. One hand hired: at 100+ rep, with a homestead plot and its chest, run `fh_hand_hire <id> ranch_hand` (a test wrapper over the hire export, same admin restriction). Put $50 in cash (`fh_pay <id> 50`), keep feed under 40 in the plot chest (open with E), then run `fh_hand_tick <id>`. Below 100 rep the hire is refused with `locked`.
    Expected: console `fh_hand_tick: ticked <id>`. The ranch hand is paid $5 (`wage:ranch_hand` ledger row) and the chest feed went up by 10 (cap 40). Run it again: +10 more, until the chest holds 40, then the tick adds 0. The timer also runs on its own every 10 minutes (do not wait for it; this is the same code path).
    RESULT:
12. Unpaid wage: spend your cash to $0, then run `fh_hand_tick <id>` once.
    Expected: `fh_hand_tick: ticked <id>`, cash stays $0 (never negative), the chest feed does NOT rise (hand idles), and the server console shows `[fh_hands] unpaid <citizenid>/ranch_hand: fh_insufficient_funds`. After 3 unpaid ticks in a row the hand quits; one paid tick before that resets the count.
    RESULT:
13. Offline catch-up: wait 30 s after your last `fh_hand_tick` before starting this step. With the hand hired and $50+ cash, note cash and the chest feed. Disconnect. In the server DB run `UPDATE fh_hands SET last_tick = last_tick - 3600;` (simulates an hour offline, 6 ticks, the cap). Rejoin and open the chest.
    Expected: on login the missed ticks run once each, capped at 6: at most $30 wages taken and feed topped up to the cap of 40. Wait 30 s: no extra ticks beyond that (no double charge).
    RESULT:
14. Fire. First, with the hand still hired, run `/fh_unclaim` (H13b).
    Expected: `fh_unclaim: fh_hand_active`; you still own the claim (`/fh_build` still lists your plot). Do not unclaim after the fire below.
    Then run `fh_hand_fire <id> ranch_hand`. Then `fh_hand_tick <id>`.
    Expected: `fh_hand_fire: ok (ranch_hand)`; `fh_hand_tick: no_hands`; no more wages or feed. Re-hiring with `fh_hand_hire` works again (no `already_hired`). Also try `fh_hand_tick` with a bad id (`abc`, `0`, a disconnected id): `fh_bad_target` / `no_player`.
    RESULT:
15. Permission check: as a non-admin player run `/fh_rep_region <id> heartlands 5`, `/fh_fence_next`, `/fh_hand_tick <id>` and `/fh_hand_hire <id> ranch_hand` from F8.
    Expected: nothing happens (no rep change, the fence does not move, no tick). The same three from the server console or as `group.admin` work.
    RESULT:
16. Settle a stuck fence stash (`fh_fence_settle`). Set one up: stop the server, then in the DB run `INSERT INTO inventories (identifier, items) VALUES ('fh:fence:<citizenid>:roving', '[{"name":"fh_part_gunsmith","amount":2,"info":{},"slot":1}]') ON DUPLICATE KEY UPDATE items = VALUES(items);` (`<citizenid>` = your character's, from the `players` table). Start the server, join, note your cash, and try to buy 1 bread at the fence.
    Expected: `The fence is holding goods from an earlier deal. Ask an admin.` and a console line `[fh_fence] WARNING fence stash not empty, trade refused: ... items=[1:fh_part_gunsmithx2]`. Now fill your backpack until 2 gunsmith parts no longer fit and run `fh_fence_settle <id>` in the console: `fh_fence_settle: no_room`, nothing moves (backpack unchanged, the buy is still refused). Make room and run it again: `fh_fence_settle: ok (2 units to <id>)`, 2 `Gunsmith Parts` in the backpack, cash unchanged, and buying bread works again. Run it once more: `fh_fence_settle: nothing_pending`. Bad input: `fh_fence_settle abc`, `fh_fence_settle 0`, `fh_fence_settle 2.5` -> `fh_bad_target`; a disconnected id -> `no_player`. As a non-admin player `/fh_fence_settle <id>` from F8 does nothing.
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



### H7 skinned animals leave the spawn lifecycle (fh_hunting)

1. Adopt a hunting animal through fh_core (e.g. the legendary bear after buying the rumour), kill and skin it. Expected: the pelt is granted as usual, and the server log shows no further `requestSpawn` retries for that animal (fh_core no longer tracks the request).
2. Skin an ordinary wild deer. Expected: unchanged behaviour, no warning in the log.
3. Restart `fh_core` after skinning. Expected: the skinned animal is not re-spawned.

   RESULT:

## Crafting (fh_crafting, fh_gunsmith)

Preconditions: stations come from @homestead H3 (on main): crafting uses a built `workbench` (gunsmith, reload) or
`campfire` (apothecary) on your OWN plot, so in-game testing needs @homestead H2 `/fh_build` (on main), or `fh_dev 1` and
the dev stations. Without fh_homestead started, crafting refuses `no_homestead`. Carried item moves and `/fh_restore` use
the core-03 fh_core exports (carried add/remove, `setItemInfo`); the tonic buff caps (idea-612) are on main. Every input
has an in-game source: `lumber`, `nails`, `lead`, `casings`, `resource_gunpowder` and the `herb_*` items (ginseng,
oregano, red sage, wild mint) are bought at trade posts (idea-716/719, on main); `gun_parts` drops from the outlaw camp
(idea-717, on main); the four herbs can also be gathered from wild patches (the "Herb gathering" card below). Fill every
`RESULT:` with `PASS`, `FAIL <what you saw>` or `SKIP <why>`.

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
   Expected: the toast says `You drink the tonic.` and the Vigor Tonic count drops by 1.
   RESULT:
9. Check the buff. `fh_buffs` has no HUD yet (client is a stub), so from the server console run
   `fh_buff <yourId> tonic_vigor 1.0 600`.
   Expected: the printed result keeps magnitude 1.15 (same-buff refresh uses `max(old, new)`), proving the drink applied
   it; the printed active list shows `tonic_vigor` with an expiry about 600 s out.
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

### Herb gathering (C9)

All unverified in-game. Patch coordinates are approximate placeholders (`TODO-verify-in-game` in
`fh_crafting/config.lua` `herbPatches`): if no `[E] Pick` prompt shows where a patch should be, stand there, read your
coordinates, and adjust the config. Patches are invisible except for the prompt (a plant prop/blip is a queued
`spk_herb` spike); two patches per herb across the Heartlands and Scarlett Meadows.

1. Walk to a patch (e.g. `wild_mint_heartlands`, about -150, 840, 117) and press E at the `[E] Pick <Herb>` prompt.
   Expected: a ~4 s progress bar runs, then chat `Picked N <Herb>.` with N = 1 or 2, and your backpack gains that many
   of the herb.
   RESULT:
2. Press E again on the same patch right away.
   Expected: the server refuses with `That patch is still regrowing.` and you gain nothing (the patch is on a shared
   900 s cooldown).
   RESULT:
3. Wait out the cooldown (or restart `fh_crafting` / the server, which clears the in-memory cooldown) and pick again.
   Expected: another 1-2 herbs.
   RESULT:
4. Brew a tonic from the gathered herbs. Stand at the apothecary (dev `-286.0, 805.0, 119.0` with `fh_dev 1`, or a
   built campfire) and run `/fh_craft tonic_vigor` (or `tonic_steady`).
   Expected: `Done: Brew Vigor Tonic.` (2 American Ginseng + 1 Wild Mint) or `Done: Brew Steady Tonic.` (2 Oregano +
   1 Red Sage), using the herbs you just gathered.
   RESULT:

## Survival (fh_survival, plan survival-01, S1-S5 combined)

One card, run once. Needs are positive timed buffs (HUD buffs); what is missing becomes sluggish level 0-3. Nothing here may
ever reduce health. Server console lines start with `[fh_survival]`. Fastest way to wait out a need: set short
durations in `fh_survival/config.lua` (`Durations`, e.g. 60 s each, and `LoginGraceSeconds = 60`), restart the resource,
and put them back afterwards. `fh_give <id> <item> <n>` / `fh_buff <id> <buff> <mag> <secs>` are the admin helpers.
Steps marked "needs @core caps (idea-613)" depend on `hydrated` and `clean` caps in `fh_buffs/config.lua`; on this branch's
base they are NOT there yet (boot logs `unknown_buff hydrated` / `unknown_buff clean`). SKIP them until @core lands the caps.
Items (from `fh_survival/shared/items.lua`): `fh_jerky`, `fh_biscuit`, `fh_stew` (food), `fh_canteen`, `bedroll`; give them with `fh_give <id> <item> <n>`. Commands: `/refill` and `/wash` (client commands, they need you inside a water zone). Messages arrive as `ox_lib` notifications.

### Grace, buffs, sluggish, persistence (S1/S2)
1. Create a brand-new character and join. Do not eat, drink or sleep for the grace period (10 min by default).
   Expected: no sluggish text for the whole grace window, even though nothing is active.
   RESULT:
2. Give yourself buffs with `fh_buff <id> well_fed 1.0 600` and `fh_buff <id> rested 1.0 600`.
   Expected: both show as buffs in the HUD with a countdown.
   RESULT:
3. Let all needs lapse (short durations, grace over). Watch the level climb as needs run out.
   Expected: sluggish level rises 0 -> 1 -> 2 -> 3 as the missing count rises (3 at three or more missing); your health never drops at any level and you never die from it.
   RESULT:
4. Re-apply one need at level 3.
   Expected: level falls by one on the next tick (up to ~15 s later).
   RESULT:
5. With `well_fed` at ~5 min left, relog (disconnect, rejoin the same character).
   Expected: `well_fed` is back with about the same remaining time (never longer; time spent offline does not count down or extend it).
   RESULT:
6. With a buff active, restart the server and rejoin.
   Expected: the buff is back with about the remaining time it had.
   RESULT:
7. Quick drop: join, and within a few seconds (before the first tick) disconnect. Rejoin.
   Expected: buffs you had before are not wiped (still there with their remaining time).
   RESULT:
8. Hydrated and clean as buffs: `fh_buff <id> hydrated 1.0 600` and `fh_buff <id> clean 1.0 600`. (needs @core caps (idea-613))
   Expected: both show in the HUD; without the caps the console says `unknown_buff`.
   RESULT:

### Food, drink, wash, warmth (S3)
9. `fh_give` yourself `fh_jerky`, `fh_biscuit` and `fh_stew`, then use each from the inventory.
   Expected: item consumed, `You feel fed.`, `well_fed` appears: jerky about 30 min, hardtack about 21 min, stew about 60 min (magnitude 1.15).
   RESULT:
10. `fh_give` yourself `fh_canteen` and use it (full = 5 charges).
    Expected: `You drink. 4 charges left.`, `hydrated` appears (about 45 min). (needs @core caps (idea-613))
    RESULT:
11. Drink until the canteen is empty, then use it once more.
    Expected: `The canteen is empty. Refill it at water.`, no buff.
    RESULT:
12. Go to a seeded water spot near the homestead or the camp (coords in the fh_survival README) and run `/refill`.
    Expected: `You refill the canteen.`, charges back to full; `/refill` on a full canteen gives `The canteen is already full.` Away from water: `You need to stand in water to refill.`
    RESULT:
13. Wash at a seeded water spot near the homestead or the camp (coords in the fh_survival README) and run `/wash`.
    Expected: `You wash off the grime.`, `clean` appears (about 90 min); washing again right away says `You washed recently. Try again in N s.` (5 min cooldown). (needs @core caps (idea-613))
    RESULT:
14. Stand at a seeded fire spot near the homestead or the camp (coords in the fh_survival README).
    Expected: `warm` appears and refreshes while you stay near. `warm` is only a bonus: ColdRegions is empty, so being without it never makes you sluggish.
    RESULT:

### Rest (S4)
15. `fh_give` yourself a `bedroll` and use it anywhere.
    Expected: `rested` appears at magnitude 1.0 (about 120 min).
    RESULT:
16. Homestead bed with comfort: the server side exists (`restAtBed`, event `fh:survival:restBed`, magnitude 1.0 + comfort x 0.01, capped at 1.20) but no client or station UI triggers it yet. Expected for now: SKIP (note "no in-game trigger"). If the homestead bed/comfort exports (H3/H4) are also missing, the bed path would fall back to bedroll-only anyway.
    RESULT:

### Sluggish effect (S5)
17. Default `SluggishEffect = 'notify'`. Let a need lapse so the level rises from 0 to 1, then 2, then 3.
    Expected: one chat line per change, e.g. `You feel a little sluggish. (level 1/3)`, then level 2 and 3 texts; repeated lines are limited to once a minute; no stamina or movement change. Getting a need back down to level 0 prints nothing.
    RESULT:
18. Set `SluggishEffect = 'native'` in `config.lua`, `restart fh_survival`, rejoin, and reach level 1-3 again.
    Expected: stamina regenerates visibly slower as the level rises (about 85% / 70% / 50%), never stops; the notify text still shows. Dead-eye regen is untouched (no hash known; `SluggishDeadeyeHash` is nil). Note anything odd in F8 (a wrong hash is swallowed silently, so "no change" means the stamina hash is wrong: report FAIL).
    RESULT:
19. Still on `native`, reach level 3 with `SluggishClipset` set to a movement clipset name you want to try (leave it nil to skip).
    Expected: at level 3 your walk changes to the clipset; as soon as the level drops, the walk is back to normal. With nil, nothing changes.
    RESULT:
20. Restore a need to reach level 0 on `native`, then set `SluggishEffect = 'notify'` and restart the resource.
    Expected: stamina regen and walk are normal; health was never touched in any step.
    RESULT:

### F1 foods and drinks, F2 owned campfire, native spikes (survival-02)

The `@core` buff caps (`hydrated`, `clean`) are on this base, so steps 21-28 need no SKIP. Base rsg-core/loot foods and
drinks use the same consume path as the S3 items; fractions are of `Durations` (`well_fed` 3600 s, `hydrated` 2700 s).

21. Give yourself `bread` and `canned_beans` (`fh_give <id> bread 1`, `fh_give <id> canned_beans 1`) and use each from the inventory, with `well_fed` not active.
    Expected: each is consumed with `You feel fed.`; `well_fed` appears for 35% of `Durations.well_fed` (about 21 min) from bread and 60% (about 36 min) from canned beans. Using bread again while it is active refreshes it (duration restarts, magnitude stays 1.0) instead of stacking.
    RESULT:
22. Give yourself `water` and `coffee` and use each with `hydrated` not active.
    Expected: each is consumed with `You feel refreshed.`; `hydrated` appears for 100% of `Durations.hydrated` (about 45 min) from water and 60% (about 27 min) from coffee. Drinking at the cap (1.0) refreshes the duration but never raises the magnitude above 1.0.
    RESULT:
23. Refund when fh_buffs refuses the buff. fh_buffs clamps a known buff to its cap instead of refusing it (the food is then consumed), so the only refusal is an unknown buff id: comment out `well_fed = 1.25` in the `caps` table of `fh_buffs/config.lua`, `restart fh_buffs` (this also drops the active buffs in memory, expected), then eat a `bread` you are carrying.
    Expected: `You cannot eat right now.`, no `well_fed`, the bread is back in your inventory (refund), and the server console logs `[fh_survival] apply well_fed refused for <yourId>: unknown_buff`. Put the cap back and `restart fh_buffs` afterwards. Note that eating with `well_fed` already active does NOT refuse (cap only): record if you see otherwise.
    RESULT:
24. Build your own homestead campfire (F2): stand inside a claim you own (`/fh_claim` first if needed), put 5 `lumber` in that plot's main chest, and run `/fh_build station_2` ($25 + 5 lumber).
    Expected: `fh_build: built station_2 tier 1 ($25, 5 lumber)`; the campfire prop appears near the plot centre (offset about 6 m east, 4 m south). The seeded `Campfires` entries are separate and do not cover this: `-300,790` r8 is about 200 m from the `heartlands_01` plot centre `-500,750`. No `[fh_survival]` console errors.
    RESULT:
25. Stand within `HomesteadHeatRadius` (8 m) of that campfire and wait. F2 re-syncs owned stations every `HomesteadHeatSyncSeconds` (15 s) and the warm tick runs every `HeatCheckSeconds` (10 s), so allow up to ~25 s.
    Expected: `warm` appears at magnitude 1.0 and refreshes about every 10 s while you stay (any player near the fire, not only the plot owner). Walk more than 8 m away: no more refresh and `warm` expires on its own after `Durations.warm` (shorten it, e.g. 60 s, to see it quickly). If a seeded `Campfires` coord is off when you stand at the real fire, write the corrected `{x, y, radius}` in RESULT.
    RESULT:
26. Log off while standing at that campfire and, on a second character, stand at the same spot. Then rejoin.
    Expected per the F2 code: `playerDropped` / `RSGCore:Server:OnPlayerUnload` removes your `hs:<plot_id>:<slot_id>` heat source, so while you are offline the fire warms nobody (allow the second character's remaining `warm` to lapse with short durations). On rejoin `RSGCore:Server:PlayerLoaded` re-syncs the fire at once, and your own `warm` is restored by the S2 persistence for its remaining time. The offline half needs a second character.
    RESULT:
27. Water native spike: set `WaterCheck = 'native'` in `fh_survival/config.lua` and `restart fh_survival`. Stand in the Dakota River and run `/refill` (with a canteen that is not full) and `/wash`. Then step out of the water and try both again.
    Expected: in water `You refill the canteen.` and `You wash off the grime.`; out of water `You need to stand in water to refill.` / `You need to stand in water to wash.` In native mode the server trusts the client's `IsEntityInWater` and ignores `WaterZones`. Record PASS/FAIL per native: the default stays `'zones'` unless this is PASS. If the seeded `WaterZones` coords are off, write the corrected `{x, y, radius}` here.
    RESULT: PASS/FAIL water native:
28. Sluggish native spike: with `SluggishEffect = 'native'` and fh_survival restarted, starve the needs to level 2, then level 3 (as in steps 17-18), and sprint/swim to drain stamina at each level.
    Expected: stamina regenerates visibly slower at level 2 (~70%) then level 3 (~50%), never stops, and the notify line still shows. Dead-eye is untouched (`SluggishDeadeyeHash` nil) and health never drops. Record PASS/FAIL per native: the default stays `'notify'` unless this is PASS. Leave `SluggishEffect` back on `'notify'` and `WaterCheck` back on `'zones'` afterwards.
    RESULT: PASS/FAIL sluggish stamina:

## Roads

Wagons, cargo, freight, shortages, heat (M4 + M5). Not runtime-tested (no Cfx key); every natives side is unverified, so report what you see.
Console prefixes: `[fh_cargo]`, `[fh_trade]`, `[fh_heat]`.

Prereqs (all must be merged before this card is meaningful):
- Branches: roads-r1 + roads-r2 (fh_cargo), roads-r4 (fh_trade freight), roads-r6 (fh_heat roadblocks); core B7 (`removeItem`, `registerItems`, `fh_economy:charge`) and fh_core R0 (`requestSpawn` kind `wagon`); quests Q1+ (fh_quests with `registerJobType`).
- server.cfg: `ensure fh_core`, `fh_economy`, `fh_inventory`, `fh_quests`, `fh_cargo`, `fh_trade`, `fh_heat` (fh_quests BEFORE fh_trade, or restart fh_trade after it). Apply the fh_trade, fh_trade_contracts and fh_heat migrations (`0013`, `0014`, `0008`).
- Convars: `set fh_spike_gated true` (default) for the gated passes; `set fh_spike_gated false` for the ungated passes. To test freight with one region, set `FhTradeConfig.freight.allowSameRegion = true` (only heartlands exists), and `deadlineSeconds = 60` for step 14.
- You are an admin and have a claimed plot with a chest (see `## M1 end-to-end` step 1).

### M4: wagon, cargo, fast travel, wheel, freight, shortage

1. `ensure fh_cargo` (and `fh_core` B7+R0). As admin run `/fh_wagon t2`.
   Expected: a wagon appears about 4 m ahead; chat confirms. If chat says `fh_core cannot spawn wagons yet`, R0 is not merged: stop and report.
   RESULT:
2. Run `fh_give <yourId> test_cargo_crate 1`, drop the crate into your plot chest, open the chest (E), stand beside the wagon and run `/fh_cargo load 1`.
   Expected: the crate leaves the chest and is in the wagon (reopen the chest to see the pane update if stale).
   RESULT:
3. Walk 20 m away with the chest open (or reopen it) and run `/fh_cargo load 1` again. Try `/fh_cargo load` with `bread` in the chest.
   Expected: far: `fh_out_of_reach`; bread: `fh_not_cargo`. A second character gets `fh_not_owner` on your wagon.
   RESULT:
4. Fast travel veto. With the loaded wagon within 30 m, there is no fast-travel system yet, so check the veto from the server console: `exports.fh_cargo:canFastTravel(<yourId>)` returns false plus a reason while you own a loaded wagon. Then move the wagon 30+ m away or unload it (`/fh_cargo unload 1`) and call again.
   Expected: `false, fh_cargo_wagon_near` and a `fh:cargo:fasttravel_blocked` event on each block; `true` after unloading or going far. With `fh_inventory` stopped: `false, fh_cargo_unknown` (fails closed; restart it afterwards). This is an export check only.
   RESULT:
5. Weight/tier: fill a `t1` (`/fh_wagon t1`) past 120 kg of cargo.
   Expected: `fh_too_heavy`. `/fh_wagon t2` again later: the old wagon is replaced and its cargo is still inside.
   RESULT:
6. Wheel break, GATED (`fh_spike_gated true`). Mount the wagon, drive fast with a loaded wagon, or force it with `/fh_wheelbreak` (admin). The off-road break factor is inactive (TODO(R2 off-road): no verified road native), so only speed + load drive the roll.
   Expected: `fh:cargo:wheel_broken` fires with `native=false`; the wagon is capped to 40% of its normal speed but no wheel visibly breaks. `exports.fh_cargo:isWheelBroken(<wagonId>)` is true.
   RESULT:
7. Wheel break, UNGATED (`set fh_spike_gated false`, S3 `spk_wheel` RESULT must be GO; if not, report what happens). Spawn a fresh wagon and `/fh_wheelbreak`.
   Expected: `native=true` in the event; the client also breaks the wheel natively. Speed is still capped.
   RESULT:
8. Repair, both modes. `fh_give <yourId> hammer 1` and `fh_give <yourId> wagon_wheel 1`; stand within reach of the broken wagon and run `/fh_repair`; stand still 8 s. (Also try walking >3 m away mid-repair, and repairing with no wheel.)
   Expected: moving away cancels it; no wheel = refused; finished: one `wagon_wheel` is consumed (hammer stays), `fh:cargo:wheel_repaired` fires. Needs core B7 `removeItem`; before it `/fh_repair` ends with `fh_core_no_removeitem`.
   RESULT:
9. REQUIRED: Break a wheel (gated and ungated), repair with hammer + wagon_wheel: wagon returns to full top speed (MODIFY_VEHICLE_TOP_SPEED 0.0 reset = no modifier). Drive the repaired wagon flat out and compare with a never-broken wagon of the same tier.
   Expected: same top speed in both modes (note any residual slowdown in RESULT).
   RESULT:
10. nearestWagon for @hunting (needs @hunting's cargo-pelt flow on main; otherwise skip): `/fh_wagon t2`, kill an animal and take its pelt, stand within 25 m of your wagon and load the pelt (the hunting flow calls `exports.fh_cargo:nearestWagon`). Try again from 40 m, and with another player's wagon.
   Expected: pelt goes into YOUR wagon within 25 m; beyond 25 m or someone else's wagon it returns nil and the pelt stays on you/the carcass.
   RESULT:
11. Shortage route. In the server console: `fh_trade_shortage heartlands trade_salt 0.8`, then `/tradequote` at the trade post.
   Expected: the salt quote is higher; `exports.fh_trade:getShortages('heartlands')` lists it first.
   RESULT:
12. Freight needs fh_quests + core B7 started. `ensure fh_quests`, then `restart fh_trade`.
   Expected: log `registered job type freight with fh_quests`. Without fh_quests: no error and no registration.
   RESULT:
13. With `allowSameRegion = true`, open the quest board.
   Expected: an offer `Freight: Nx Salt Sack to heartlands`. Stand next to your wagon (within 8 m) and accept: N salt appear in the wagon. Accepting again is refused; with no wagon near: `fh_freight_no_wagon`.
   RESULT:
14. Drive the wagon into the destination radius.
   Expected: the cargo leaves the wagon, the journal completes, ONE `fh_ledger` row `quest:job:freight:<key>`, rep up. Variants: unload the cargo to a chest and wait `graceChecks x checkMs` -> fails `cargo_missing`, no payout; with `deadlineSeconds = 60` -> fails `timeout`, also if you log out first; abandon from the journal -> cargo removed, no payout.
   RESULT:
15. Trade-post sell: `fh_give <yourId> trade_salt 10`, at the post `/tradesell trade_salt 10`, repeat, then `/tradesell trade_salt 999`.
   Expected: items gone, cash up, one `fh_ledger` row; the second sale pays less (saturation); 999 refused, nothing taken.
   RESULT:
15a. Trade-post buy (needs fh_economy migration `0015` for refunds): note your cash, at the post `/tradequote` (lists 9 supplies), then `/tradebuy lumber 5` (or `/tradepost` -> Buy Lumber).
   Expected: cash -$15, 5 Lumber in the backpack, ONE `fh_ledger` row kind=charge amount=15 reason `trade_buy:lumber` region heartlands; `/tradequote` trade-good prices unchanged by the buy.
   RESULT:
15b. Buy with too little money: drop your cash below $6 (e.g. `fh_charge <yourId> <cash - 5>` from the console), then `/tradebuy nails 3`.
   Expected: "You cannot afford that.", no nails, no new `fh_ledger` row, cash unchanged.
   RESULT:
15c. Buy into a full backpack -> refund: fill the backpack (all slots, or near its weight cap), then `/tradebuy lumber 100`.
   Expected: "...your money was refunded (fh_no_slot|fh_too_heavy)", no lumber added, cash back to where it was; `fh_ledger` has a charge row `trade_buy:lumber` amount 300 AND a credit row `trade_buy_refund:lumber` amount 300. No `ALERT refund FAILED` in the console.
   RESULT:

### M5: faction heat, roadblock, decay, bounty (ambush/chase gated)

16. Give heat: `exports.fh_heat:set(<yourId>, "outlaws", 30)` (or the fh_core admin `fh_heat`), then `/paybounty`.
   Expected: the list shows outlaws 30 (level `watched`) and its cost. Clearing the heartlands camp should also add `camp_clear` heat (25) to every player standing in that territory.
   RESULT:
17. Roadblock (always on). Set outlaws heat to 55 near heartlands.
   Expected: one roadblock of about 4 outlaw peds at the nearest chokepoint, hostile; `fh:heat:roadblock_spawned` fires. Heat 30 -> 55 again: no second one. Set 20: peds vanish, `roadblock_cleared` reason `heat_dropped`. Re-raise within the cooldown: nothing spawns, log says `cooldown`. Chokepoint coords are unverified: note the real position/heading.
   RESULT:
18. Lay-low decay. Set heat 40 and stand OUTSIDE any outlaw territory for 3 minutes (2.0 per minute).
   Expected: heat drops by about 6 (`fh:heat:changed` reason `decay`); standing inside an outlaw territory does not decay.
   RESULT:
19. Bounty payoff. With heat 40 and cash on hand run `/paybounty outlaws 10`, then `/paybounty outlaws`.
   Expected: 10 points then the rest are cleared, money charged = points x `bountyPerPoint` (one `fh_ledger` charge row each); `0`, `-5`, `abc` or more than your heat: refused, nothing charged. With too little cash: `fh_insufficient_funds`, nothing changes. Needs core B7 `charge`; before it: `fh_economy_unavailable`.
   RESULT:
20. Payoff refund check. The commit-failure refund is spec-covered; in-game is optional and dev only (do NOT stop oxmysql; only if a dev build can force the heat write to fail after the charge).
   Expected: the message says you were not charged / refunded (`fh_payoff_refunded`), cash back to the exact amount, heat unchanged, retry works. If it instead reports `fh_payoff_refund_failed`, you were charged and there is an `[fh_heat] ERROR payoff ...` log line: do not retry, report it.
   RESULT:
21. Double submit: run `/paybounty outlaws` twice in quick succession.
   Expected: the second gets `fh_payoff_busy` and is never charged.
   RESULT:
22. Night ambush + mounted chase, GATED (default `fh_spike_gated true`). Set heat 80, ride a horse, at night.
   Expected: nothing spawns; logs `night ambush skipped: fh_spike_gated=true (waiting on S2 spk_chase RESULT)` and `mounted chase skipped: ...`. Roadblocks still work.
   RESULT:
23. Ambush + chase, UNGATED (`set fh_spike_gated false`; only after S2 `spk_chase` RESULT is GO, else report). Heat 80 at night, mounted.
   Expected: peds ring you (`fh:heat:ambush_spawned`), then riders spawn behind you and attack (`fh:heat:chase_started`); both clear when heat drops. No wagon pursuit (not implemented).
   RESULT:
24. `restart fh_heat`; then spawn roadblocks as 5 different players.
   Expected: restart: all roadblock peds gone; the 5th simultaneous roadblock is refused (`max_concurrent`). Heat values survive the restart (decayed).
   RESULT:

## A-life: camp ownership (fh_alife, fh_zones)

A-life camp ownership (plan a-life-01): a cleared camp flips to the region's law faction, which stops it waking, changes
whose loot is in the stash, and shifts the region's trade prices; the sim later retakes it. Console lines start with
`[fh_alife]`. Needs `fh_alife` ensured (after `fh_zones`). Admin: `group.admin`.

1. Ride to the Heartlands camp (-145, 845, 117) and kill all four outlaws (clears the camp as usual).
   Expected: the console broadcasts `Valentine Law has taken the Heartlands Outlaw Camp`, and `fh:alife:camp_flipped`
   fires with `{camp_id='heartlands_t1_01', region_id='heartlands', from='outlaws', to='lawmen'}`.
   RESULT:
2. Run `/alife`.
   Expected: the Heartlands camp shows owner `lawmen` (Valentine Law); the Scarlett Meadows camp still shows `raiders`.
   RESULT:
3. Walk into the Heartlands camp (within ~40 m of the center).
   Expected: no bandits spawn (a law-held camp does not activate); no `camp heartlands_t1_01 activated` console line.
   RESULT:
4. Go to the Valentine trade post and check prices.
   Expected: the camp's region trade prices moved now that the law holds the camp; note which prices changed in RESULT.
   RESULT:
5. Check your outlaw heat.
   Expected: clearing the camp raised outlaw heat (`fh:heat:changed` reason `camp_clear`, +25 for everyone in the territory).
   RESULT:
6. Run `/alife tick 30` (advance the sim 30 ticks) and watch the console.
   Expected: the outlaws retake the camp; a retake broadcast fires and `fh:alife:camp_flipped` fires with
   `{from='lawmen', to='outlaws'}`.
   RESULT:
7. Walk back into the camp.
   Expected: `camp heartlands_t1_01 activated`; the four outlaws spawn again and are hostile.
   RESULT:
8. Restart the server (or `restart fh_alife`), then run `/alife`.
   Expected: ownership is persisted (still shows the last owner, e.g. `outlaws` after the retake); no error lines.
   RESULT:

### Town lot is law-safe (fh_heat + fh_homestead lawSafeAt, idea-803)

Needs `fh_homestead`, `fh_heat`, `fh_economy` started and $300+ cash. Roadblocks fire when heat CROSSES `wanted` (50);
night ambush and mounted chase need `hunted` (75) plus `set fh_spike_gated false` (ambush only 21:00-05:00 game time).
Each check is: heat to 0, then up. Only spawns are suppressed; heat still accrues inside the lot.

1. Run `/where lot`, ride to the lot it routes to (Valentine: `heartlands_lot_01`, (-180, 620, 113), radius 14 m), stand in it
   and run `/fh_buylot`.
   Expected: `fh_buylot: bought lot heartlands_lot_01`.
   RESULT:
2. Stand in the middle of your lot. Run `exports.fh_heat:set(<yourId>, "outlaws", 0)`, then `exports.fh_heat:set(<yourId>, "outlaws", 55)`.
   Expected: no roadblock spawns; the console shows exactly once `[fh_heat] <id>/<cid> law-safe in own lot heartlands_lot_01: skipping spawn`.
   Your heat still reads 55 (heat accrues inside the lot).
   RESULT:
3. Set heat to 0, then 80 (with `fh_spike_gated false`, at night, on a horse or wagon).
   Expected: no ambush ring and no mounted chase while you stay in the lot; the skip line does not repeat for the same lot.
   RESULT:
4. Walk out of the lot (more than 14 m from its center), set heat 0 then 55 (then 0 and 80).
   Expected: the roadblock spawns (and ambush/chase when gated off); the skipped ones started no cooldown.
   Set heat back to 0.
   RESULT:
5. (Optional, 2 players) Player B stands in player A's lot and runs the heat 0 -> 55 sequence on their own character.
   Expected: the roadblock still spawns for B (a stranger's lot is not safe); no skip line for B.
   RESULT:

### A-life: road ambush squads + contracts (a-life-02)

A-Life road raids (plan a-life-02): an outlaw-held camp can send an ambush squad to a road node, and the region jobs
board offers `alife_contract` jobs to break an ambush or clear an outlaw camp. Console lines start with `[fh_alife]`.
Needs `fh_alife` ensured (after `fh_zones`) and `fh_quests` for the board. Admin: `/alife`, `/alife tick n`
(`group.admin`). Ambush nodes come only from `regions[].ambush` in fh_core (@world world-03 H); until that data is on
main there are no raids. A held squad materialises only within `FhAlifeConfig.squads.ambushRadius` (45 m).

0. Precondition: run `/alife` and look for a region line with ambush nodes (e.g. `heartlands: 3 ambush node(s): ...`).
   If no region has ambush data, every line reads `<region>: no ambush nodes`.
   Expected: with data, each region line lists its nodes as `<label>=free`; with none, no raids ever start and steps
   1-5 are SKIP (that is the expected result until world-03 H is on main).
   RESULT:
1. Run `/alife` to find an outlaw-held camp (an owner without `(law)`). Run `/alife tick 5` and check `/alife` again;
   repeat until a squad line appears, e.g. `sq1 ambush@<node label> x3 travel`. Then tick until it reads `hold`.
   Expected: each tick replies `Advanced A-Life 5 tick(s) -> N effect(s).`; while a squad is out, `/alife` lists it by
   goal, node label and strength (`sq1 ambush@<label> x3 travel|hold`), and the region's ambush line shows
   `<label>=sq1 outlaws x3 hold`. `FhAlifeConfig.raids.chancePct` is 5 (out of 100) per outlaw camp per tick; a
   squad holds for `holdTicks` 15 (~15 min at 60 s/tick), with `regionCap` 2 per region.
   RESULT:
2. Ride to that node and stop within 45 m (`FhAlifeConfig.squads.ambushRadius`); then ride more than 45 m away.
   Expected: on approach the console prints `[fh_alife] squad <id> materialised at <node id> (<n> peds)` and `<n>`
   hostile peds are standing on foot at the node (no horses, no mounted riders); note the real ground position in
   RESULT if it floats or buries. Riding away prints `[fh_alife] squad <id> despawned (no_player_near)`, the peds
   vanish, and the squad's strength is unchanged in `/alife`.
   RESULT:
3. Kill every ped in the squad, checking `/alife` after each kill.
   Expected: the squad's `x<n>` strength drops by 1 per kill; after the last kill `/alife` no longer lists it and the
   node reads `<label>=free`. The console prints `[fh_alife] squad <id> despawned (wiped)` and the server emits
   `fh:alife:squad_wiped` (the event that pays the board job; `fh:alife:squad_wiped` has no separate console line).
   Killing a squad adds no heat (known follow-up).
   RESULT:
4. Open the region board with `/jobs` (or its trade-post prop). Look for `Break the ambush: <node label>` while a
   squad holds a node, and `Clear out: <camp label>` while a camp is outlaw-held. Accept the ambush job, then wipe
   the squad.
   Expected: both are `alife_contract` offers; `Clear out:` is absent for a law-held camp. The board keeps only 3-5
   offers and rotates hourly, so a specific job may be absent from this hour's board: reopen after the rotation. On
   the wipe the job completes and pays 30 cash and +2 region rep (the camp job pays 40 and +3 on `camp_cleared`).
   RESULT:
5. Clear an outlaw-held camp (e.g. the Heartlands camp if it is still outlaw-held), run `/alife`, then `/alife tick 1`.
   Expected: the camp shows `<camp id>=<law faction>(law)` and `/alife` lists a data-only reinforce squad
   `sq<n> reinforce-><camp id> x2 travel` (then `hold` after 3 ticks; it renews while the law holds the camp). No
   peds spawn for it: it adds holder strength only, and the camp's normal peds are unaffected.
   RESULT:

## World-01: walk the claims (fh_core regions, fh_homestead, fh_zones, fh_trade, fh_ui)

Ground-snap + enabled-gate check (plan world-01 block D). `/where` is the fix-up tool: run `/where plot` to get a
named claim, ride to it, and report any coordinate that floats/buries with the corrected coords from `/where`.
Unverified entries show `(unverified)`; the four enabled regions are heartlands, scarlett_meadows, bayou_nwa and
great_plains. Only those four should show anything — the other 11 regions are disabled and must show no blip, no
`/where` entry, no camp and no `/jobs` board.

world-03 J adds the fast path: `fh_tour <region>` steps you through that region's unverified places in riding order
(`fh_tour next` advances; it tells you when the tour is done), `fh_mark ok|bad [note]` records a verdict for the
nearest place within 30 m into `fh_core`'s `world_walk.json` (append-only, never committed), and `fh_tp <placeId>`
teleports straight to any claim/lot/camp/post/town/ambush id with a ground snap.

0. Fast path (world-03 J): `fh_tour heartlands`, then repeatedly `fh_tour next`; at each stop run `fh_mark ok`, or
   `fh_mark bad <note>` when it floats/buries (name the fix in the note). When the tour reports "complete", repeat for
   `fh_tour scarlett_meadows`, `fh_tour bayou_nwa`, `fh_tour great_plains`.
   Expected: each stop teleports you to the place with a ground snap; `fh_mark` appends a `{id,verdict,note,x,y,z,ts,by}`
   record to `world_walk.json` (and says "no place within 30 m" when you are not standing at one); the tour never
   revisits its origin town. `fh_tp heartlands_01` lands you on that claim the same way.
   RESULT:

1. Heartlands claims: `/where plot`, then ride to each named claim — Dakota Bend, Creekside Pines, Cattail Marsh,
   Larkspur Meadow (town lots show "coming soon").
   Expected: each claim's chest sits on the ground (no floating/buried prop) and the blip/destination is at ground
   level; nothing logs `fh:world:unsnapped <id>` for a claim whose area has streamed in.
   RESULT:
2. Heartlands camps: ride to Heartland Bluffs, Heartland Overflow, Dakota West, Dakota South.
   Expected: each camp's stash prompt appears at ground level; the four outlaw peds spawn on the ground and sit away
   from every claim and town; `camp <id> activated` on approach.
   RESULT:
3. Heartlands trade post: the Valentine Trade Post.
   Expected: shows on `/where` (as `(unverified)`), reachable, prices move with the region.
   RESULT:
4. Scarlett Meadows claims: Red Cane, Wildcat Hollow, Cedar Flat, Sorghum Furrow.
   Expected: ground snap as step 1; camps Hill Haven, Cedar Bottoms, Catfish Bottom spawn on ground away from claims;
   Rhodes Trade Post reachable.
   RESULT:
5. Bayou Nwa claims: Cypress Reach, Sugar Cane, Tupelo Gut.
   Expected: ground snap as step 1; camps Moss Bog, Bayou Railroad, Lagras Swamp, Cypress Hollow on ground; Saint
   Denis Trade Post reachable.
   RESULT:
6. Great Plains claims: Cottonwood Ford, Sage Creek, Pine Timber.
   Expected: ground snap as step 1; camps Bison Bluff, Great Plains North, Great Plains East on ground; Blackwater
   Trade Post reachable.
   RESULT:
7. Disabled regions (11): bluewater_marsh, roanoke_ridge, grizzlies_east, grizzlies_west, cumberland_forest,
   big_valley, tall_trees, hennigans_stead, cholla_springs, gaptooth_ridge, rio_bravo.
   Expected: `/where` shows no plot/camp/post for any of them; no blip; `/jobs` never offers one of them. Confirm and
   note anything that still appears.
   RESULT:
8. `/where` unverified tag: run `/where` with no argument and skim the list.
   Expected: every claim, camp and trade post shows `(unverified)` until you stand there and fix it; verified entries
   (after a fix) show no tag.
   RESULT:
9. Plot check (H16). As an admin, stand near the claims you want checked (the ground probe only sees streamed-in ground) and run `/fh_plotcheck all` once.
   Expected: chat shows a summary (`N plot(s): X ok, Y warn, Z fail` plus up to 8 problem ids and a pointer to the console); the server console has one block per claim and town lot with ground z vs config z, water at center, overlap at max radius and nearest town. `/fh_plotcheck <plotId>` prints that block in chat. A plot far from you reads `ground: NOT FOUND`: run `/fh_plotcheck <plotId>` next to it. Fix every `BAD` / `YES` / overlap line in `config.lua`. A non-admin gets the command refused.
   RESULT:
