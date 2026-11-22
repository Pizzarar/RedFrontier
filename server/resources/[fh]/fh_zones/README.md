# fh_zones

Seed of lane L3 (spec L89, M1 L107): one T1 outlaw camp, `heartlands_t1_01`, in the M1 region (heartlands).

- `config.lua`: camp center, activation radius, 4 outlaw peds (model/coords/heading/weapon), respawn minutes, loot table,
  and the two new items (`worn_rifle` bulky, `small_safe` cargo). **All coordinates/models/weapons are guesses: TODO-verify-in-game.**
- `shared/camp_rules.lua`: pure rules (state transitions, activation check, all-dead roll-up, loot roll with injectable RNG,
  report-distance check); specced in `spec/camp_rules_spec.lua`.
- `server/main.lua`: state machine `idle -> active -> cleared -> respawn_wait -> idle`.
  - A player within `activationRadius` wakes an idle camp; peds are requested with `exports.fh_core:requestSpawn`
    (tag `<camp>:outlaw:<n>`, owner `{ kind = 'camp' }`). `onReady` may fire again with a new netId (spike-gated re-request):
    the camp keeps one record per ped and ignores/despawns a re-adopted ped that was already seen dead.
  - Cleared when every ped is dead and at least one died. Death = server-side `GetEntityHealth <= 0` of the adopted entity,
    polled each tick; a client `fh:zones:ped_dead` report only triggers an early check (and is accepted only from a nearby player).
  - On clear: loot is rolled (`rollLoot`, `info.condition` on the rifle) into an fh_core `chest` container
    `fh:camp:<id>` (accepts cargo; the safe cannot go into a backpack/equipped/saddlebag). Open = `fh:zones:open_loot`
    -> `exports.fh_core:open` (server reach check), only after the camp is cleared.
  - After `respawnMinutes` the bodies are despawned, the stash is emptied and the camp is idle again.
- `client/main.lua`: hostile AI setup (relationship group hating players, weapon) in the handler of fh_core's local
  `fh:spawn:adopted` hook, death hints, stash prompt. All handlers via FH.on / FH.thread / FH.wrap.
- Events: `fh:zones:camp_activated`, `fh:zones:camp_cleared`, `fh:zones:camp_respawned` (fh_core/docs/events.md).
  Export: `getCamp(id)`. Gated behaviour: row 3 of fh_core/docs/spike-gated.md.
- Not runtime-tested (no Cfx key yet): see OWNER-TESTS.md "B6b".
